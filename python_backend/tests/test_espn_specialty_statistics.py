from datetime import date

from providers import espn_specialty_statistics as provider


def test_tennis_completed_match_derives_sets_and_games(monkeypatch) -> None:
    monkeypatch.setattr(provider, "_get", lambda *_args, **_kwargs: [{
        "groupings": [{"competitions": [{"id": "match", "date": "2026-08-02T12:00Z",
          "status": {"type": {"completed": True}}, "competitors": [
            {"id": "1", "winner": True, "athlete": {"displayName": "Winner"},
             "linescores": [{"value": 6}, {"value": 7}]},
            {"id": "2", "winner": False, "athlete": {"displayName": "Loser"},
             "linescores": [{"value": 4}, {"value": 5}]},
          ]}]}]
    }])
    rows = provider.tennis_logs(tour="ATP", target_date=date(2026, 8, 2))
    assert rows[0]["stats"] == {"sets_won": 2.0, "games_won": 13.0, "match_win": 1.0}
    assert rows[1]["stats"] == {"sets_won": 0.0, "games_won": 9.0, "match_win": 0.0}


def test_golf_round_derives_score_types(monkeypatch) -> None:
    monkeypatch.setattr(provider, "_get", lambda *_args, **_kwargs: [{
        "id": "event", "date": "2026-08-02T04:00Z", "competitions": [{"competitors": [{
            "id": "p1", "athlete": {"displayName": "Golfer"}, "linescores": [{
                "period": 1, "value": 69, "linescores": [
                    {"scoreType": {"displayValue": "-1"}},
                    {"scoreType": {"displayValue": "E"}},
                    {"scoreType": {"displayValue": "+1"}},
                ]}]}]}]
    }])
    rows = provider.golf_logs(target_date=date(2026, 8, 2))
    assert rows[0]["stats"] == {"round_score": 69.0, "birdies": 1.0, "bogeys": 1.0, "pars": 1.0}


def test_ufc_completed_fight_maps_prop_statistics(monkeypatch) -> None:
    monkeypatch.setattr(provider, "_get", lambda *_args, **_kwargs: [{
        "id": "event", "competitions": [{
            "id": "fight", "date": "2026-08-02T12:00Z",
            "status": {"period": 2, "clock": 75,
                       "type": {"completed": True}},
            "competitors": [{"id": "10", "winner": True,
                             "athlete": {"displayName": "Fighter"}}],
        }],
    }])
    monkeypatch.setattr(provider, "_ufc_statistics", lambda **_kwargs: {
        "sigStrikesLanded": 44, "totalStrikesLanded": 60,
        "takedownsLanded": 2, "knockDowns": 1, "submissions": 3,
    })
    rows = provider.ufc_logs(target_date=date(2026, 8, 2))
    assert rows[0]["stats"] == {
        "significant_strikes": 44, "total_strikes": 60,
        "takedowns": 2, "knockdowns": 1, "submission_attempts": 3,
        "fight_time_seconds": 375.0, "fight_win": 1.0,
    }


def test_ufc_upcoming_fight_is_never_ingested(monkeypatch) -> None:
    monkeypatch.setattr(provider, "_get", lambda *_args, **_kwargs: [{
        "id": "event", "competitions": [{
            "id": "fight", "date": "2026-08-02T12:00Z",
            "status": {"type": {"completed": False}},
            "competitors": [{"id": "10", "athlete": {"displayName": "Fighter"}}],
        }],
    }])
    assert provider.ufc_logs(target_date=date(2026, 8, 2)) == []
