import re

TEAM_ALIASES = {
    "la sparks": "los angeles sparks",
    "ny liberty": "new york liberty",
    "lv aces": "las vegas aces",
    "conn sun": "connecticut sun",
    "la clippers": "los angeles clippers",
    "lac": "los angeles clippers",
    "clips": "los angeles clippers",
    "gsw": "golden state warriors",
    "nyk": "new york knicks",
    "nop": "new orleans pelicans",
    "okc": "oklahoma city thunder",
    "sas": "san antonio spurs",
    "uta": "utah jazz",
    "was": "washington wizards",
    "chi": "chicago bulls",
    "bos": "boston celtics",
    "phi": "philadelphia 76ers",
    "phx": "phoenix suns",
    "tb": "tampa bay rays",
    "sf": "san francisco giants",
    "sd": "san diego padres",
    "kc": "kansas city royals",
    "nyy": "new york yankees",
    "nym": "new york mets",
    "wsh": "washington nationals",
    "cws": "chicago white sox",
    "lad": "los angeles dodgers",
    "ath": "athletics",
}


def normalize_team_name(value: str) -> str:
    normalized = re.sub(
        r"[^a-z0-9]+",
        " ",
        value.lower(),
    ).strip()
    normalized = " ".join(normalized.split())
    return TEAM_ALIASES.get(
        normalized,
        normalized,
    )
