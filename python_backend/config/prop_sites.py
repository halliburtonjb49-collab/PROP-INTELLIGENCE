PROP_SITE_ALIASES = {
    "prizepicks": "PrizePicks",
    "prize picks": "PrizePicks",
    "underdog": "Underdog",
    "underdog fantasy": "Underdog",
    "sleeper": "Sleeper",
    "fanduel": "FanDuel",
    "fan duel": "FanDuel",
    "draft picks": "Draft Picks",
    "draftpicks": "Draft Picks",
    "draft pick": "Draft Picks",
}

SUPPORTED_PROP_SITES = [
    "PrizePicks",
    "Underdog",
    "FanDuel",
    "Sleeper",
    "Draft Picks",
]

DEFAULT_PROP_SITES = [
    "PrizePicks",
    "Underdog",
    "FanDuel",
    "Sleeper",
    "Draft Picks",
]


def normalize_prop_site(value: str) -> str:
    normalized = value.strip().lower()
    return PROP_SITE_ALIASES.get(
        normalized,
        value.strip(),
    )


def is_supported_prop_site(value: str) -> bool:
    normalized = normalize_prop_site(value)
    return normalized in set(SUPPORTED_PROP_SITES)
