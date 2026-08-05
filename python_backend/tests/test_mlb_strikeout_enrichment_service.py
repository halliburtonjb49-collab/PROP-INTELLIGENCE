from types import SimpleNamespace

from services import mlb_strikeout_enrichment_service


def test_enrich_mlb_strikeout_props_populates_pitcher_lineup_and_umpire_inputs(monkeypatch) -> None:
    monkeypatch.setattr(mlb_strikeout_enrichment_service, "database_is_configured", lambda: True)
    monkeypatch.setattr(
        mlb_strikeout_enrichment_service,
        "_pitcher_metrics",
        lambda _player_id, _event_date: {
            "pitcher_k_pct": 0.31,
            "pitcher_csw": 0.295,
            "pitches_per_start": 96.0,
            "pitches_per_batter": 3.91,
        },
    )
    monkeypatch.setattr(
        mlb_strikeout_enrichment_service,
        "_lineup_split_metrics",
        lambda _lineup, _event_date, _pitcher_hand: {
            "lineup_k_pct": 0.247,
            "lineup_csw_against": 0.281,
        },
    )
    monkeypatch.setattr(
        mlb_strikeout_enrichment_service,
        "_umpire_boost",
        lambda _game_pk: 0.012,
    )
    monkeypatch.setattr(
        mlb_strikeout_enrichment_service,
        "game_temperature_f",
        lambda _matchup, _start_time: 61.5,
    )

    prop = SimpleNamespace(
        sport="MLB",
        market="Pitcher Strikeouts",
        marketKey="pitcher_strikeouts",
        category="STRIKEOUTS",
        startTimeUtc="2026-08-05T23:10:00Z",
        sourcePlayerId="656876",
        player="Pitcher Name",
        mlbProjectedLineupMatchup={
            "throws": "L",
            "opposingLineup": [{"player": "Batter One", "battingOrder": 1}],
        },
        apiSportsGameId="12345",
        matchup="COL @ SD",
        pitcherKPercent=None,
        pitcherCsw=None,
        pitchesPerStart=None,
        pitchesPerBatter=None,
        lineupKPercent=None,
        umpireKBoost=None,
        temperatureF=None,
        parkKFactor=None,
    )

    mlb_strikeout_enrichment_service.enrich_mlb_strikeout_props([prop])

    assert prop.pitcherKPercent == 0.31
    assert prop.pitcherCsw == 0.295
    assert prop.pitchesPerStart == 96.0
    assert prop.pitchesPerBatter == 3.91
    assert prop.lineupKPercent == 0.247
    assert prop.lineupCswAgainst == 0.281
    assert prop.umpireKBoost == 0.012
    assert prop.temperatureF == 61.5
    assert prop.parkKFactor is not None


def test_lineup_k_rate_prefers_exact_provider_player_ids(monkeypatch) -> None:
    calls: list[str] = []

    def fake_latest_player_features(*, role: str, player_id: str, before_date: object):
        calls.append(player_id)
        return {
            "features": {
                "pregame_plate_appearances_avg_10d": 4.0,
                "pregame_strikeouts_avg_10d": 1.0,
            },
        }

    monkeypatch.setattr(
        mlb_strikeout_enrichment_service,
        "latest_player_features",
        fake_latest_player_features,
    )

    rate = mlb_strikeout_enrichment_service._lineup_k_rate(
        [{"player": "Ignored Name", "providerPlayerId": "12345", "battingOrder": 1}],
        object(),
    )

    assert rate == 0.25
    assert calls == ["12345"]


def test_enrichment_falls_back_to_generic_lineup_rate_when_handed_split_missing(monkeypatch) -> None:
    monkeypatch.setattr(mlb_strikeout_enrichment_service, "database_is_configured", lambda: True)
    monkeypatch.setattr(
        mlb_strikeout_enrichment_service,
        "_pitcher_metrics",
        lambda _player_id, _event_date: {},
    )
    monkeypatch.setattr(
        mlb_strikeout_enrichment_service,
        "_lineup_split_metrics",
        lambda _lineup, _event_date, _pitcher_hand: {},
    )
    monkeypatch.setattr(
        mlb_strikeout_enrichment_service,
        "_lineup_k_rate",
        lambda _lineup, _event_date: 0.233,
    )
    monkeypatch.setattr(
        mlb_strikeout_enrichment_service,
        "_umpire_boost",
        lambda _game_pk: None,
    )
    monkeypatch.setattr(
        mlb_strikeout_enrichment_service,
        "game_temperature_f",
        lambda _matchup, _start_time: None,
    )

    prop = SimpleNamespace(
        sport="MLB",
        market="Pitcher Strikeouts",
        marketKey="pitcher_strikeouts",
        category="STRIKEOUTS",
        startTimeUtc="2026-08-05T23:10:00Z",
        sourcePlayerId="656876",
        player="Pitcher Name",
        mlbProjectedLineupMatchup={
            "throws": "R",
            "opposingLineup": [{"player": "Batter One", "battingOrder": 1}],
        },
        apiSportsGameId="12345",
        matchup="COL @ SD",
        pitcherKPercent=None,
        pitcherCsw=None,
        pitchesPerStart=None,
        pitchesPerBatter=None,
        lineupKPercent=None,
        lineupCswAgainst=None,
        umpireKBoost=None,
        temperatureF=None,
        parkKFactor=None,
    )

    mlb_strikeout_enrichment_service.enrich_mlb_strikeout_props([prop])

    assert prop.lineupKPercent == 0.233
    assert prop.lineupCswAgainst is None
