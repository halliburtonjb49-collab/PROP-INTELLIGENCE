from datetime import date

from providers.espn_soccer_statistics import EspnSoccerStatisticsProvider


def test_espn_soccer_provider_fetches_only_completed_event_summaries(
    monkeypatch,
) -> None:
    responses = {
        "scoreboard": {
            "events": [
                {"id": "done", "date": "2026-07-20T19:00:00Z"},
                {"id": "scheduled", "date": "2026-07-21T19:00:00Z"},
                {"id": "outside", "date": "2026-07-22T19:00:00Z"},
            ],
        },
        "done": {
            "header": {
                "competitions": [{
                    "status": {"type": {"completed": True}},
                }],
            },
            "rosters": [{"team": {"id": "1"}, "roster": []}],
        },
        "scheduled": {
            "header": {
                "competitions": [{
                    "status": {"type": {"completed": False}},
                }],
            },
            "rosters": [],
        },
    }

    def fake_json(self, url, *, params=None):
        if url.endswith("/scoreboard"):
            assert params["dates"] == "20260720-20260721"
            return responses["scoreboard"]
        return responses[str(params["event"])]

    monkeypatch.setattr(EspnSoccerStatisticsProvider, "_json", fake_json)
    fixtures = list(
        EspnSoccerStatisticsProvider().completed_fixtures(
            start_date=date(2026, 7, 20),
            end_date=date(2026, 7, 21),
        )
    )

    assert fixtures == [{
        "id": "done",
        "league_id": "779",
        "starting_at": "2026-07-20T19:00:00Z",
        "rosters": [{"team": {"id": "1"}, "roster": []}],
    }]
