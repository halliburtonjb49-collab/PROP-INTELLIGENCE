from random import Random

import pytest

from services.game_state_simulation_service import (
    DEFAULT_SIMULATIONS,
    GameConditions,
    PropSpec,
    draw_game_state,
    simulate_game,
    ticket_probability,
)


def _spec(prop_id, player, team="HOME", **kwargs):
    base = dict(
        line=20.5, side="OVER", projection=21.0, volatility=5.0,
        distribution="normal",
    )
    base.update(kwargs)
    return PropSpec(prop_id=prop_id, player=player, team=team, **base)


def test_the_spec_default_is_ten_thousand_draws() -> None:
    assert DEFAULT_SIMULATIONS == 10_000


def test_a_drawn_game_is_internally_consistent() -> None:
    random = Random(3)
    for _ in range(500):
        state = draw_game_state(random, GameConditions(blowout_margin=16.0))
        # Overtime only follows from a game that was close to level.
        if state.overtime_periods:
            assert abs(state.score_margin) < 4.0
        assert state.blowout == (abs(state.score_margin) >= 16.0)
        assert 0.80 <= state.pace_factor <= 1.32


def test_two_props_from_one_game_come_out_correlated() -> None:
    result = simulate_game(
        [_spec("a", "Alice"), _spec("b", "Bob")],
        simulations=4000,
    )
    correlation = result.correlations[("a", "b")]

    # Nothing asserted this. Two different players share only the game -- its
    # pace and its script -- so the link is real but slight, and the fitted
    # pace volatility of about 0.056 is what sets its size.
    assert 0.01 < correlation < 0.15


def test_one_players_markets_move_together_more_than_two_players_do() -> None:
    result = simulate_game(
        [
            _spec("points", "Alice"),
            _spec("pra", "Alice"),
            _spec("other", "Bob"),
        ],
        simulations=4000,
    )

    same_player = result.correlations[("points", "pra")]
    across_players = result.correlations[("points", "other")]

    # A player's own minutes drive all of his markets; two players share only
    # the game.
    assert same_player > across_players


def test_pace_insensitive_props_decouple_from_the_game() -> None:
    result = simulate_game(
        [
            _spec("volume", "Alice", pace_sensitivity=1.0),
            _spec("rate", "Bob", pace_sensitivity=0.0, minutes_driven=False),
        ],
        simulations=4000,
    )
    # A stat that does not scale with possessions should barely track one that
    # does.
    assert abs(result.correlations[("volume", "rate")]) < 0.10


def test_a_blowout_costs_starters_their_late_minutes() -> None:
    lopsided = simulate_game(
        [_spec("starter", "Alice", blowout_sensitivity=1.0)],
        conditions=GameConditions(expected_margin=26.0, margin_volatility=4.0),
        simulations=3000,
    )
    close = simulate_game(
        [_spec("starter", "Alice", blowout_sensitivity=1.0)],
        conditions=GameConditions(expected_margin=0.0, margin_volatility=4.0),
        simulations=3000,
    )
    assert lopsided.outcomes["starter"].mean_outcome < (
        close.outcomes["starter"].mean_outcome
    )


def test_a_bench_stat_is_untouched_by_the_blowout() -> None:
    lopsided = simulate_game(
        [_spec("reserve", "Alice", blowout_sensitivity=0.0)],
        conditions=GameConditions(expected_margin=26.0, margin_volatility=4.0),
        simulations=3000,
    )
    close = simulate_game(
        [_spec("reserve", "Alice", blowout_sensitivity=0.0)],
        conditions=GameConditions(expected_margin=0.0, margin_volatility=4.0),
        simulations=3000,
    )
    assert lopsided.outcomes["reserve"].mean_outcome == pytest.approx(
        close.outcomes["reserve"].mean_outcome, rel=0.05
    )


def test_probabilities_account_for_every_draw() -> None:
    result = simulate_game([_spec("a", "Alice")], simulations=2000)
    outcome = result.outcomes["a"]

    assert outcome.over_probability + outcome.under_probability + (
        outcome.push_probability
    ) == pytest.approx(1.0, abs=1e-4)


def test_an_inactive_player_produces_no_output() -> None:
    always_out = simulate_game(
        [_spec("a", "Alice", inactive_probability=1.0)],
        simulations=500,
    )
    assert always_out.outcomes["a"].mean_outcome == 0.0
    assert always_out.outcomes["a"].over_probability == 0.0


def test_a_ticket_is_counted_jointly_not_multiplied() -> None:
    result = simulate_game(
        [_spec("a", "Alice"), _spec("b", "Alice")],
        simulations=4000,
    )
    ticket = ticket_probability(result, ["a", "b"])

    # Two markets on one player hit together far more often than independence
    # implies; multiplying their individual probabilities underprices it.
    assert ticket["jointProbability"] > ticket["independentProbability"]
    assert ticket["correlationEffect"] > 0


def test_a_ticket_naming_an_unknown_prop_is_refused() -> None:
    result = simulate_game([_spec("a", "Alice")], simulations=200)
    assert ticket_probability(result, ["a", "ghost"])["jointProbability"] is None


def test_simulation_is_reproducible_for_a_seed() -> None:
    specs = [_spec("a", "Alice"), _spec("b", "Bob")]
    first = simulate_game(specs, simulations=1000, seed=11)
    second = simulate_game(specs, simulations=1000, seed=11)
    assert first.outcomes["a"] == second.outcomes["a"]
    assert first.correlations == second.correlations


def test_no_props_yields_an_empty_result_rather_than_an_error() -> None:
    result = simulate_game([], simulations=100)
    assert result.outcomes == {} and result.simulations == 0


def test_simulated_spread_matches_the_volatility_it_was_given() -> None:
    # The variance split must not change the marginal distribution. If it did,
    # every probability the simulator reports would be wrong.
    result = simulate_game(
        [_spec("a", "Alice", projection=19.2, volatility=6.0)],
        simulations=8000,
    )
    outcome = result.outcomes["a"]

    assert outcome.mean_outcome == pytest.approx(19.2, rel=0.03)
    assert outcome.outcome_volatility == pytest.approx(6.0, rel=0.06)


def test_shared_variance_is_removed_from_the_prop_s_own_draw() -> None:
    from services.game_state_simulation_service import residual_volatility

    spec = _spec("a", "Alice", projection=20.0, volatility=6.0)
    residual = residual_volatility(
        spec, minutes_volatility=0.12, pace_volatility=0.06,
    )
    # Drawing at full volatility on top of a shared state would count the same
    # game-to-game variation twice.
    assert residual < spec.volatility


def test_residual_never_collapses_to_nothing() -> None:
    from services.game_state_simulation_service import residual_volatility

    # A prop whose shared channels would explain more than its total variance
    # must keep some randomness of its own rather than becoming a deterministic
    # function of the game state.
    spec = _spec("a", "Alice", projection=40.0, volatility=1.0)
    residual = residual_volatility(
        spec, minutes_volatility=0.30, pace_volatility=0.20,
    )
    # At most 85% of a prop's variance may come from the shared state, so the
    # residual keeps the square root of the remaining fifteen percent.
    assert residual == pytest.approx(1.0 * (0.15 ** 0.5), abs=1e-6)


def test_player_form_ties_a_players_markets_beyond_shared_minutes() -> None:
    # Wide props, so the shared channels are not already capped by the prop's
    # own spread. Where the cap binds, minutes alone saturate the coupling and
    # form has nothing left to add -- which the fitted values make the common
    # case rather than the exception.
    specs = [
        _spec("pts", "Alice", projection=20.0, volatility=10.0),
        _spec("reb", "Alice", projection=8.0, volatility=4.5),
    ]
    with_form = simulate_game(
        specs, simulations=5000, minutes_volatility=0.20, form_volatility=0.20
    )
    without_form = simulate_game(
        specs, simulations=5000, minutes_volatility=0.20, form_volatility=0.0
    )

    assert with_form.correlations[("pts", "reb")] > (
        without_form.correlations[("pts", "reb")]
    )


def test_coupling_volatilities_are_fitted_per_league() -> None:
    from services.game_state_simulation_service import (
        DEFAULT_COUPLING, coupling_for,
    )

    assert coupling_for("NBA") != coupling_for("WNBA")
    # An unfitted sport falls back rather than silently borrowing a league.
    assert coupling_for("KABADDI") == DEFAULT_COUPLING


def test_a_count_prop_keeps_the_spread_it_was_given() -> None:
    # A Poisson or negative binomial cannot hold variance below its mean. If
    # the split ignores that, the draw silently falls back to a Poisson whose
    # variance is the mean and the marginal reinflates.
    result = simulate_game(
        [
            PropSpec(
                prop_id="reb", player="Alice", team="HOME", line=6.5,
                side="OVER", projection=7.0, volatility=3.2,
                distribution="negative-binomial",
            )
        ],
        simulations=8000,
        sport="NBA",
    )
    assert result.outcomes["reb"].outcome_volatility == pytest.approx(3.2, rel=0.10)


def test_a_narrow_prop_scales_back_the_shared_channels() -> None:
    from services.game_state_simulation_service import variance_split

    # League-wide minutes and pace swings imply more variance than this prop
    # has. Correlation gives way so the marginal stays right.
    narrow = _spec("a", "Alice", projection=30.0, volatility=1.5)
    _, scale = variance_split(
        narrow, minutes_volatility=0.293, pace_volatility=0.056,
    )
    assert scale < 1.0

    wide = _spec("b", "Bob", projection=20.0, volatility=9.0)
    _, wide_scale = variance_split(
        wide, minutes_volatility=0.293, pace_volatility=0.056,
    )
    assert wide_scale == pytest.approx(1.0)


def test_fitted_coupling_keeps_the_marginal_intact() -> None:
    result = simulate_game(
        [_spec("a", "Alice", projection=19.2, volatility=6.0)],
        simulations=8000,
        sport="NBA",
    )
    outcome = result.outcomes["a"]
    assert outcome.mean_outcome == pytest.approx(19.2, rel=0.03)
    assert outcome.outcome_volatility == pytest.approx(6.0, rel=0.05)
