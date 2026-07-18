from config import ODDS_REGIONS, PREFERRED_BOOKMAKERS


def test_default_odds_scope_targets_configured_books() -> None:
    regions = {region.strip() for region in ODDS_REGIONS.split(",")}
    assert regions
    assert regions <= {"us", "us2", "eu", "uk", "au"}
    assert "draftkings" in PREFERRED_BOOKMAKERS
    assert "fanduel" in PREFERRED_BOOKMAKERS
