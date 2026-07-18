from services.engagement_service import sentiment_rollup


def test_sentiment_rollup_degrades_without_database(monkeypatch) -> None:
    monkeypatch.setattr("services.engagement_service.database_is_configured", lambda: False)
    result = sentiment_rollup("prop-1")
    assert result["label"] == "NEUTRAL"
    assert result["sampleSize"] == 0
