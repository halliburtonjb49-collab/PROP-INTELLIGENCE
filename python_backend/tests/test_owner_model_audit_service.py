from datetime import datetime, timezone

from services import owner_model_audit_service as audit


def test_model_audit_summarizes_accuracy_pushes_calibration_roi_and_sides() -> None:
    rows = [
        {
            "id": "one", "player": "Player One", "sport": "WNBA",
            "market": "Points", "side": "OVER", "line": 20.5,
            "actualValue": 24, "hitProbability": .72, "hit": True,
            "modelVersion": "wnba-v2", "entryOdds": -110,
        },
        {
            "id": "two", "player": "Player Two", "sport": "WNBA",
            "market": "Rebounds", "side": "UNDER", "line": 8.5,
            "actualValue": 9, "hitProbability": .65, "hit": False,
            "modelVersion": "wnba-v2", "entryOdds": -110,
        },
        {
            "id": "three", "player": "Player Three", "sport": "NBA",
            "market": "Assists", "side": "OVER", "line": 6,
            "actualValue": 6, "hitProbability": .81, "hit": False,
            "modelVersion": "nba-v4", "entryOdds": -105,
        },
    ]

    result = audit.summarize_model_audit(rows)

    assert result["summary"]["graded"] == 3
    assert result["summary"]["decisions"] == 2
    assert result["summary"]["hits"] == 1
    assert result["summary"]["losses"] == 1
    assert result["summary"]["pushes"] == 1
    assert result["summary"]["accuracy"] == .5
    assert result["summary"]["oddsSampleSize"] == 3
    assert result["dimensions"]["sports"] == ["NBA", "WNBA"]
    assert result["dimensions"]["modelVersions"] == ["nba-v4", "wnba-v2"]
    assert result["predictions"][2]["push"] is True
    assert result["predictions"][2]["correct"] is None
    calibration = {row["tier"]: row for row in result["calibration"]}
    assert calibration["70-79%"]["accuracy"] == 1
    sides = {row["side"]: row for row in result["sidePerformance"]}
    assert sides["OVER"]["pushes"] == 1


def test_model_audit_degrades_truthfully_without_database(monkeypatch) -> None:
    monkeypatch.setattr(audit, "database_is_configured", lambda: False)

    result = audit.owner_model_audit_snapshot(
        "today", now=datetime(2026, 8, 11, 15, 0, tzinfo=timezone.utc),
    )

    assert result["available"] is False
    assert result["summary"]["graded"] == 0
    assert result["predictions"] == []
    assert result["window"]["key"] == "today"

def test_prediction_explanation_uses_only_captured_pregame_evidence() -> None:
    explanation = audit.build_prediction_explanation({
        "projection": 23.1,
        "line": 20.5,
        "hitProbability": .72,
        "closingLine": 21.5,
        "lineClvPoints": 1.0,
        "modelVersion": "wnba-v2",
        "inputs": {
            "projectedMinutes": 33,
            "projectionSampleSize": 12,
            "projectionVolatility": 4.2,
            "injuryStatus": "healthy",
            "lineupStatus": "confirmed starter",
            "pregameAvailability": {"summary": "Starter confirmed 35 minutes before tip."},
            "openingLine": 19.5,
            "currentLine": 20.5,
            "marketProbability": .55,
            "dataQualityScore": .91,
            "dataAgeSeconds": 84,
            "recommendationExplanation": "Projection cleared the line with a confirmed role.",
        },
        "featureSnapshot": {
            "matchup": "Connecticut Sun",
            "paceMultiplier": 1.04,
            "matchupMultiplier": 1.03,
            "restDays": 2,
            "travelMiles": 310,
            "fatigueMultiplier": .99,
        },
        "sourceVersions": {"projection": "wnba-v2", "availability": "sportradar"},
    })

    sections = {section["key"]: section for section in explanation["sections"]}
    assert explanation["summary"] == "Projection cleared the line with a confirmed role."
    assert sections["projection"]["status"] == "AVAILABLE"
    assert sections["opportunity"]["value"].startswith("33.0 projected minutes")
    assert sections["availability"]["status"] == "AVAILABLE"
    assert sections["line_movement"]["value"] == "open 19.50 -> snapshot 20.50 -> close 21.50"
    assert sections["data_quality"]["value"] == "Quality 91%"
    assert not any("Injury status" in warning for warning in explanation["warnings"])
    assert explanation["sourceVersions"]["availability"] == "sportradar"


def test_prediction_explanation_labels_missing_evidence_instead_of_inventing_it() -> None:
    explanation = audit.build_prediction_explanation({
        "projection": 8.2,
        "line": 7.5,
        "hitProbability": .61,
        "modelVersion": "generic-v1",
    })

    warnings = " ".join(explanation["warnings"])
    sections = {section["key"]: section for section in explanation["sections"]}
    assert "Projected minutes were not captured" in warnings
    assert "Injury status was not captured" in warnings
    assert "Lineup status was not captured" in warnings
    assert "Closing line was not captured" in warnings
    assert sections["availability"]["status"] == "MISSING"
    assert sections["schedule"]["status"] == "MISSING"


def test_model_audit_returns_explanation_but_not_raw_evidence() -> None:
    result = audit.summarize_model_audit([{
        "id": "one",
        "sport": "WNBA",
        "market": "Points",
        "side": "OVER",
        "line": 20.5,
        "projection": 23.1,
        "actualValue": 24,
        "hitProbability": .72,
        "hit": True,
        "modelVersion": "wnba-v2",
        "inputs": {"projectedMinutes": 33, "lineupStatus": "confirmed"},
        "featureSnapshot": {"restDays": 2},
        "sourceVersions": {"projection": "wnba-v2"},
    }])

    row = result["predictions"][0]
    assert row["explanation"]["sections"]
    assert "inputs" not in row
    assert "featureSnapshot" not in row
    assert "sourceVersions" not in row