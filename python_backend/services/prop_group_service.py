"""One identity for the same prop offered at several sportsbooks.

The board renders one card per book, so 13,053 distinct props arrive as
28,194 cards -- 2.16 to one, and the worst of them appear fourteen times.
Grouping needs an identity that is stable across a refresh and identical for
every book carrying the same offer, which is what this computes.

The line is deliberately not part of the key. Books disagree about the
number, and "who has the best line" is precisely the question being asked;
folding 25.5 and 26.5 into separate groups would leave the near-duplicate
cards this exists to collapse. The line still distinguishes the variants
inside a group, so nothing about that disagreement is lost.
"""

from __future__ import annotations

import re
import unicodedata
from hashlib import blake2s

# Short on purpose. This rides on every prop in a catalog that reached
# roughly 112 MiB uncompressed and exhausted its instance today, so the
# identity is sized to be unambiguous rather than decorative.
_DIGEST_SIZE = 6


def _normalized(value: object) -> str:
    text = unicodedata.normalize("NFKD", str(value or ""))
    ascii_text = "".join(
        character for character in text if not unicodedata.combining(character)
    )
    return re.sub(r"[^a-z0-9]+", "", ascii_text.lower())


def prop_group_key(
    *,
    sport: object,
    event_id: object,
    player_id: object,
    player: object,
    market_key: object,
    market: object,
) -> str:
    """A stable identity for the same offer across books.

    Player id is preferred and the name is the fallback, because two players
    with similar names must never merge; when neither is present the group
    degenerates to the prop's own identity rather than guessing, which keeps
    an unidentifiable prop separate instead of silently merged into another.
    """

    identity = _normalized(player_id) or _normalized(player)
    market_identity = _normalized(market_key) or _normalized(market)
    event_identity = _normalized(event_id)
    if not identity or not market_identity or not event_identity:
        return ""
    parts = (
        _normalized(sport),
        event_identity,
        identity,
        market_identity,
    )
    return blake2s(
        "|".join(parts).encode("utf-8"), digest_size=_DIGEST_SIZE
    ).hexdigest()


def assign_prop_groups(props: list) -> dict[str, int]:
    """Stamp every prop with its group and how many books share it.

    Returns the group sizes, so a caller can report how much of the board is
    repetition without walking it a second time.
    """

    sizes: dict[str, int] = {}
    for prop in props:
        key = prop_group_key(
            sport=getattr(prop, "sport", ""),
            event_id=getattr(prop, "eventId", ""),
            player_id=getattr(prop, "playerId", ""),
            player=getattr(prop, "player", ""),
            market_key=getattr(prop, "marketKey", ""),
            market=getattr(prop, "market", ""),
        )
        # A prop that cannot be identified stands alone rather than joining
        # a group it might not belong to.
        resolved = key or f"solo:{getattr(prop, 'id', '')}"
        try:
            prop.propGroupId = resolved
        except (AttributeError, ValueError):
            continue
        sizes[resolved] = sizes.get(resolved, 0) + 1
    for prop in props:
        group = getattr(prop, "propGroupId", "")
        if group:
            try:
                prop.propGroupBookCount = sizes.get(group, 1)
            except (AttributeError, ValueError):
                continue
    return sizes
