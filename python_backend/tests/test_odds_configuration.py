from config import LIVE_ODDS_SYNC_MIN_SECONDS, ODDS_REGIONS, PREFERRED_BOOKMAKERS


def test_default_odds_scope_targets_configured_books() -> None:
    regions = {region.strip() for region in ODDS_REGIONS.split(",")}
    assert regions
    assert regions <= {"us", "us2", "eu", "uk", "au"}
    assert "draftkings" in PREFERRED_BOOKMAKERS
    assert "fanduel" in PREFERRED_BOOKMAKERS


def test_live_line_base_refresh_is_never_slower_than_two_minutes() -> None:
    assert 60 <= LIVE_ODDS_SYNC_MIN_SECONDS <= 120
