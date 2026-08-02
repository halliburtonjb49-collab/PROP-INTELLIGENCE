from providers.historical_data import NbaHistoricalProvider


class _Frame:
    empty = False

    def notna(self):
        return True

    def where(self, _condition, _replacement):
        return self

    def to_dict(self, *, orient):
        assert orient == "records"
        return [{"GAME_ID": "1022600001", "PLAYER1_ID": 7}]


class _Endpoint:
    def get_data_frames(self):
        return [_Frame()]


def test_game_scoped_wnba_inputs_do_not_invent_a_league_parameter(monkeypatch) -> None:
    calls = []

    class Endpoints:
        @staticmethod
        def PlayByPlayV2(**kwargs):
            calls.append(("pbp", kwargs))
            return _Endpoint()

        @staticmethod
        def BoxScoreTraditionalV2(**kwargs):
            calls.append(("box", kwargs))
            return _Endpoint()

    provider = NbaHistoricalProvider()
    monkeypatch.setattr(provider, "_endpoints", lambda: Endpoints)

    assert provider.game_play_by_play(game_id="1022600001")[0]["PLAYER1_ID"] == 7
    assert provider.game_box_score_players(game_id="1022600001")[0]["PLAYER1_ID"] == 7
    assert calls == [
        ("pbp", {"game_id": "1022600001", "timeout": 60}),
        ("box", {"game_id": "1022600001", "timeout": 60}),
    ]
