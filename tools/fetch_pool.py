"""Fetch a stable daily game pool from RAWG.

Writes ``data/daily_pool.json``. The file contains only the game
dictionary; the actual 7 levels are composed on the client by
``scripts/level_builder.gd`` using the date as the seed, so every
player with the same pool deterministically sees the same board.

Separating "fetch" (which needs the RAWG API key) from "compose
levels" (pure math) lets GitHub Actions keep the key private while
the client can still regenerate boards on demand (for the in-game
refresh button) without ever contacting RAWG.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import generate_levels  # reuse fetch_games() and its filtering rules

OUTPUT = ROOT / "data" / "daily_pool.json"


def build_pool(api_key: str, pages: int) -> list[dict]:
    pool = generate_levels.fetch_games(api_key, pages)
    # Stable ordering so the client's level builder is bit-for-bit
    # deterministic regardless of RAWG result ordering jitter.
    pool.sort(key=lambda game: game["id"])
    return pool


def precompute_variants(pool: list[dict], day: str, count: int = 3) -> list[list[dict]]:
    """Precompose the N boards the player might see today.

    The in-game refresh button is capped at 2 uses, so three variants
    (initial + two reshuffles) is enough. Doing it here in Python
    means the Godot client never runs its own expensive composer and
    the window never freezes at startup, no matter how large the pool.
    """

    variants: list[list[dict]] = []
    for index in range(count):
        seed = f"{day}#{index}"
        try:
            board = generate_levels.generate(pool, seed)
        except Exception as exc:  # noqa: BLE001 - skip remaining if we fail
            print(f"Variant {index} failed to compose: {type(exc).__name__}: {exc}")
            break
        variants.append(board["packs"][0])
    return variants


def to_output(day: str, pool: list[dict]) -> dict:
    games = {
        game["id"]: {key: value for key, value in game.items() if key not in ("id", "_tagset")}
        for game in pool
    }
    variants = precompute_variants(pool, day)
    return {
        "generated_for": day,
        "source": "RAWG",
        "pool_size": len(games),
        "games": games,
        "variants": variants,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--date", default=date.today().isoformat(), help="local date in YYYY-MM-DD")
    parser.add_argument("--pages", type=int, default=10, help="40 games fetched per page")
    args = parser.parse_args()
    day = date.fromisoformat(args.date).isoformat()
    api_key = os.environ.get("RAWG_API_KEY")
    if not api_key:
        parser.error("Set RAWG_API_KEY in the environment.")
    try:
        pool = build_pool(api_key, args.pages)
    except Exception as exc:
        raise SystemExit("RAWG fetch failed: " + type(exc).__name__) from None
    if len(pool) < 45:
        raise SystemExit("Only %d usable games fetched; need at least 45." % len(pool))
    output = to_output(day, pool)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(output, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {len(pool)} games to {OUTPUT} for {day}")


if __name__ == "__main__":
    main()
