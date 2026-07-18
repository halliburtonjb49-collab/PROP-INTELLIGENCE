from services.officiating_profile_service import calculate_basketball_official_profiles, calculate_mlb_umpire_profiles


def test_umpire_profiles_shrink_small_samples() -> None:
    rows = []
    for _ in range(20):
        rows.append({"umpire": "Wide Zone", "plate_x": .9, "description": "called_strike"})
        rows.append({"umpire": "League Ump", "plate_x": .9, "description": "ball"})
    profiles = calculate_mlb_umpire_profiles(rows, prior_pitches=200)
    wide = next(profile for profile in profiles if profile["officialName"] == "Wide Zone")
    assert wide["rawRate"] == 1
    assert 1 < wide["tendencyIndex"] < 2
    assert wide["confidence"] < .1


def test_umpire_profiles_ignore_non_borderline_pitches() -> None:
    assert calculate_mlb_umpire_profiles([
        {"umpire": "Ump", "plate_x": 0, "description": "called_strike"}
    ]) == []


def test_basketball_whistle_profiles_use_game_sample_shrinkage() -> None:
    rows = ([{"sport": "NBA", "official_id": "wide", "official_name": "Wide", "whistle_events": 70}] * 5 +
            [{"sport": "NBA", "official_id": "normal", "official_name": "Normal", "whistle_events": 40}] * 20)
    profiles = calculate_basketball_official_profiles(rows, prior_games=20)
    wide = next(profile for profile in profiles if profile["officialId"] == "wide")
    assert wide["tendencyIndex"] > 1
    assert wide["confidence"] == .2
