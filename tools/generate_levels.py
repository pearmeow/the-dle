"""Generate a dated seven-level board from RAWG metadata.

Requires RAWG_API_KEY. The output is deliberately reviewed by simple
solvability checks; it is still worth playtesting before distribution.
"""

from __future__ import annotations

import argparse
import json
import os
import random
from datetime import date
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "data" / "generated_levels.json"
TITLES = [
    "Opening act", "Spot the mechanic", "Shared territory", "Closer calls",
    "Fine details", "Near neighbors", "The final read",
]
NOTES = [
    "These games have little in common.",
    "Find a mechanic that sets your pick apart.",
    "Use one memorable feature.",
    "Setting and play style both help.",
    "Pick a detail the others do not share.",
    "Similar tags make every word count.",
    "Eight close options. Be exact.",
]
SIZES = [3, 4, 5, 6, 7, 7, 8]
TARGET_SIMILARITY = [0.025, 0.045, 0.065, 0.085, 0.10, 0.115, 0.13]
IGNORED_TAGS = {
    "singleplayer", "multiplayer", "steam achievements", "steam cloud", "steam trading cards",
    "full controller support", "controller", "achievements", "online co-op", "co-op",
    "indie", "great soundtrack", "atmospheric", "2d", "3d", "early access",
    "open world", "action", "adventure", "rpg", "casual", "strategy", "simulation",
    "difficult", "family friendly", "free to play", "f2p", "pvp", "pve",
}


def fetch_games(api_key: str, pages: int) -> list[dict]:
    games = []
    for page in range(1, pages + 1):
        query = urlencode({"key": api_key, "page": page, "page_size": 40, "ordering": "-added"})
        # Never print the URL: it contains the API key.
        with urlopen("https://api.rawg.io/api/games?" + query, timeout=30) as response:
            body = json.load(response)
        for item in body.get("results", []):
            tags = [
                tag["name"].strip() for tag in item.get("tags", [])
                if tag.get("language") in ("eng", None)
                and tag.get("name", "").strip().lower() not in IGNORED_TAGS
                and 3 <= len(tag.get("name", "")) <= 35
            ]
            tags = list(dict.fromkeys(tags))[:12]
            if len(tags) < 4 or not item.get("genres") or not item.get("name"):
                continue
            slug = str(item.get("slug", ""))
            games.append({
                "id": "rawg_%s" % item["id"],
                "name": str(item["name"])[:100],
                "genre": str(item["genres"][0]["name"])[:50],
                "blurb": "Gameplay tags: " + ", ".join(tags[:5]) + ".",
                "features": tags,
                "rawg_url": "https://rawg.io/games/" + slug,
            })
    return list({game["id"]: game for game in games}.values())


def tag_set(game: dict) -> set[str]:
    if "_tagset" not in game:
        game["_tagset"] = {tag.casefold() for tag in game["features"]}
    return game["_tagset"]


def jaccard(left: dict, right: dict) -> float:
    a, b = tag_set(left), tag_set(right)
    return len(a & b) / len(a | b) if a or b else 0.0


def similarity(group: list[dict]) -> float:
    pairs = [jaccard(left, right) for i, left in enumerate(group) for right in group[i + 1:]]
    return sum(pairs) / len(pairs) if pairs else 0.0


def distinguishable(group: list[dict]) -> bool:
    for i, left in enumerate(group):
        for right in group[i + 1:]:
            if left["name"].casefold() == right["name"].casefold():
                return False
            if len(tag_set(left) ^ tag_set(right)) < 3 or jaccard(left, right) > 0.78:
                return False
    return True


def choose_group(pool: list[dict], count: int, target: float, minimum: float, used: set[str], rng: random.Random) -> list[dict]:
    best: list[dict] = []
    best_cost = float("inf")
    for _ in range(130):
        anchor = rng.choice(pool)
        group = [anchor]
        while len(group) < count:
            choices = [game for game in pool if game not in group and distinguishable(group + [game])]
            if not choices:
                break
            # The small random sample keeps each dated board fresh while the
            # target similarity keeps later levels closer together.
            choices = rng.sample(choices, min(len(choices), 70))
            next_game = min(
                choices,
                key=lambda game: abs(similarity(group + [game]) - target)
                + (0.07 if game["id"] in used else 0.0)
                + rng.random() * 0.025,
            )
            group.append(next_game)
        if len(group) != count or similarity(group) < minimum:
            continue
        cost = abs(similarity(group) - target) + sum(game["id"] in used for game in group) * 0.04
        if cost < best_cost:
            best, best_cost = group, cost
    if not best:
        raise RuntimeError("Could not form a distinguishable level; fetch more RAWG pages.")
    return best


def generate(pool: list[dict], seed: str) -> dict:
    if len(pool) < 45:
        raise ValueError("At least 45 usable games are needed.")
    rng = random.Random(seed)
    used: set[str] = set()
    previous_similarity = 0.0
    levels = []
    selected = {}
    for index, (count, target) in enumerate(zip(SIZES, TARGET_SIMILARITY)):
        group = choose_group(pool, count, target, previous_similarity + 0.004, used, rng)
        previous_similarity = similarity(group)
        ids = [game["id"] for game in group]
        levels.append({"theme": TITLES[index], "note": NOTES[index], "games": ids})
        for game in group:
            used.add(game["id"])
            selected[game["id"]] = {key: value for key, value in game.items() if key not in ("id", "_tagset")}
    return {"generated_for": seed, "source": "RAWG", "games": selected, "packs": [levels]}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--date", default=date.today().isoformat(), help="local date in YYYY-MM-DD")
    parser.add_argument("--pages", type=int, default=7, help="40 games fetched per page")
    args = parser.parse_args()
    day = date.fromisoformat(args.date).isoformat()
    key = os.environ.get("RAWG_API_KEY")
    if not key:
        parser.error("Set RAWG_API_KEY in the environment.")
    try:
        pool = fetch_games(key, args.pages)
        pool.sort(key=lambda game: game["id"])
        board = generate(pool, day)
    except Exception as exc:
        raise SystemExit("Level generation failed: " + type(exc).__name__) from None
    OUTPUT.write_text(json.dumps(board, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote seven levels for {day} from {len(pool)} RAWG games to {OUTPUT}")


if __name__ == "__main__":
    main()
