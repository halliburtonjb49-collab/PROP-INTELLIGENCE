from types import SimpleNamespace

from pytest import approx

from services import outdoor_weather_service


class _FakeResponse:
    def __init__(self, payload):
        self._payload = payload

    def raise_for_status(self) -> None:
        return None

    def json(self):
        return self._payload


def _forecast_payload(time_value: str) -> dict[str, object]:
    return {
        "hourly": {
            "time": [time_value],
            "temperature_2m": [42.0],
            "apparent_temperature": [36.0],
            "precipitation_probability": [75.0],
            "wind_speed_10m": [21.0],
            "wind_gusts_10m": [31.0],
            "weather_code": [61],
        }
    }


def test_known_outdoor_venue_fetches_game_hour_forecast(monkeypatch) -> None:
    outdoor_weather_service.game_weather.cache_clear()

    def fake_get(url, params, timeout):
        assert url == outdoor_weather_service._FORECAST_URL
        assert params["latitude"] == approx(42.7738)
        assert params["longitude"] == approx(-78.7870)
        assert params["timezone"] == "GMT"
        return _FakeResponse(_forecast_payload("2026-08-16T17:00"))

    monkeypatch.setattr(outdoor_weather_service.requests, "get", fake_get)

    result = outdoor_weather_service.game_weather(
        "NFL",
        "New York Jets @ Buffalo Bills",
        "2026-08-16T17:25:00Z",
    )

    assert result["status"] == "outdoor"
    assert result["venue"] == "Buffalo Bills home venue"
    assert result["temperatureF"] == 42.0
    assert result["windSpeedMph"] == 21.0
    assert result["precipitationProbability"] == 75.0
    assert result["source"] == "open-meteo"


def test_fixed_indoor_venue_stays_neutral_without_network(monkeypatch) -> None:
    outdoor_weather_service.game_weather.cache_clear()

    def fail_get(*args, **kwargs):
        raise AssertionError("indoor events must not request outdoor weather")

    monkeypatch.setattr(outdoor_weather_service.requests, "get", fail_get)
    result = outdoor_weather_service.game_weather(
        "NFL",
        "Chicago Bears @ Detroit Lions",
        "2026-08-16T17:00:00Z",
    )

    assert result["status"] == "indoor"
    assert result["multiplier"] == 1.0


def test_roof_unknown_does_not_apply_outdoor_adjustment(monkeypatch) -> None:
    prop = SimpleNamespace(
        sport="NFL",
        matchup="New York Giants @ Dallas Cowboys",
        startTimeUtc="2026-08-16T20:00:00Z",
        market="Passing Yards",
        marketKey="passing_yards",
        category="Passing",
    )
    monkeypatch.setattr(
        outdoor_weather_service,
        "game_weather",
        lambda *_: {
            "status": "roof_unknown",
            "venue": "dallas cowboys",
            "temperatureF": 96.0,
            "windSpeedMph": 25.0,
            "precipitationProbability": 80.0,
            "source": "open-meteo",
        },
    )

    outdoor_weather_service.enrich_outdoor_weather([prop])

    assert prop.weatherStatus == "roof_unknown"
    assert prop.weatherMultiplier == 1.0


def test_outdoor_passing_prop_receives_conservative_weather_penalty(monkeypatch) -> None:
    props = [
        SimpleNamespace(
            sport="NFL",
            matchup="New York Jets @ Buffalo Bills",
            startTimeUtc="2026-08-16T17:25:00Z",
            market="Passing Yards",
            marketKey="passing_yards",
            category="Passing",
        ),
        SimpleNamespace(
            sport="NFL",
            matchup="New York Jets @ Buffalo Bills",
            startTimeUtc="2026-08-16T17:25:00Z",
            market="Receiving Yards",
            marketKey="receiving_yards",
            category="Receiving",
        ),
    ]
    calls = []

    def fake_weather(*args):
        calls.append(args)
        return {
            "status": "outdoor",
            "venue": "buffalo bills",
            "temperatureF": 22.0,
            "apparentTemperatureF": 10.0,
            "precipitationProbability": 70.0,
            "windSpeedMph": 21.0,
            "windGustMph": 31.0,
            "weatherCode": 61,
            "source": "open-meteo",
            "forecastForUtc": "2026-08-16T17:25:00+00:00",
        }

    monkeypatch.setattr(outdoor_weather_service, "game_weather", fake_weather)
    outdoor_weather_service.enrich_outdoor_weather(props)

    assert len(calls) == 1
    assert props[0].weatherStatus == "outdoor"
    assert props[0].weatherVenue == "buffalo bills"
    assert props[0].weatherMultiplier == approx(0.88)
    assert props[1].weatherMultiplier == approx(0.88)

def test_neutral_site_stays_unadjusted_without_fetch(monkeypatch) -> None:
    prop = SimpleNamespace(
        sport="NFL",
        matchup="New York Jets @ Buffalo Bills",
        startTimeUtc="2026-08-16T17:25:00Z",
        market="Passing Yards",
        marketKey="passing_yards",
        category="Passing",
        isNeutralSite=True,
    )

    def fail_weather(*args):
        raise AssertionError("neutral site requires an actual venue")

    monkeypatch.setattr(outdoor_weather_service, "game_weather", fail_weather)
    outdoor_weather_service.enrich_outdoor_weather([prop])

    assert prop.weatherStatus == "location_unavailable"
    assert prop.weatherVenue == "Neutral site (venue unavailable)"
    assert prop.weatherMultiplier == 1.0


def test_unrelated_market_remains_neutral() -> None:
    multiplier = outdoor_weather_service._weather_multiplier(
        "NFL",
        "Tackles",
        temperature_f=10,
        wind_mph=30,
        precipitation_probability=90,
    )

    assert multiplier == 1.0
