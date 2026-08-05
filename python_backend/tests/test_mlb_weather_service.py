from services import mlb_weather_service


class _FakeResponse:
    def __init__(self, payload):
        self._payload = payload

    def raise_for_status(self) -> None:
        return None

    def json(self):
        return self._payload


def test_game_temperature_f_uses_home_park_and_returns_fahrenheit(monkeypatch) -> None:
    mlb_weather_service._weather_hour.cache_clear()

    def fake_get(url, params, timeout):
        assert params["hourly"] == "temperature_2m"
        return _FakeResponse(
            {
                "hourly": {
                    "time": ["2026-08-05T23:00"],
                    "temperature_2m": [20.0],
                },
            }
        )

    monkeypatch.setattr(mlb_weather_service.requests, "get", fake_get)

    temperature = mlb_weather_service.game_temperature_f(
        "CIN @ CHC",
        "2026-08-05T23:10:00Z",
    )

    assert temperature == 68.0