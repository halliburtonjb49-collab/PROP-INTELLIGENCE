PROP_SITE_ALIASES = {
    "prizepicks": "PrizePicks",
    "prize picks": "PrizePicks",
    "underdog": "Underdog",
    "underdog fantasy": "Underdog",
    "pick6": "DraftKings Pick6",
    "pick 6": "DraftKings Pick6",
    "draftkings pick6": "DraftKings Pick6",
    "dk pick6": "DraftKings Pick6",
    "fanduel": "FanDuel",
    "fan duel": "FanDuel",
    "draft picks": "Draft Picks",
    "draftpicks": "Draft Picks",
    "draft pick": "Draft Picks",
    "betr": "Betr",
    "betr picks": "Betr",
    "betr_us_dfs": "Betr",
}

SUPPORTED_PROP_SITES = [
    "PrizePicks",
    "Underdog",
    "FanDuel",
    "DraftKings Pick6",
    "Draft Picks",
    "Betr",
]

DEFAULT_PROP_SITES = [
    "PrizePicks",
    "Underdog",
    "FanDuel",
    "DraftKings Pick6",
    "Draft Picks",
    "Betr",
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
