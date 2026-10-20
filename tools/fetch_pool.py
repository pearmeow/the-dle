"""Precompute daily RAWG boards with a persistent seven-day cooldown."""

from __future__ import annotations

import argparse
import json
import os
import random
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import generate_levels  # reuse fetch_games() and its filtering rules

OUTPUT = ROOT / "data" / "daily_pool.json"
HISTORY = ROOT / "data" / "daily_history.json"
COOLDOWN_DAYS = 7
DAILY_POOL_SIZE = 45


def build_pool(api_key: str, pages: int) -> list[dict]:
    pool = generate_levels.fetch_games(api_key, pages)
    # Stable ordering keeps the dated boards independent of API ordering jitter.
    pool.sort(key=lambda game: game["id"])
    return pool


def recent_ids(history: dict, day: str) -> set[str]:
    today = date.fromisoformat(day)
    return {
        game_id
        for previous, ids in history.items()
        if 0 < (today - date.fromisoformat(previous)).days < COOLDOWN_DAYS
        for game_id in ids
    }


def refresh_variant(primary: list[dict], pool: list[dict], seed: str) -> list[dict]:
    """Mutate a valid board without greedily consuming its late-level choices."""
    rng = random.Random(seed)
    pack = json.loads(json.dumps(primary))
    lookup = {g["id"]: g for g in pool}
    for _ in range(200):
        trial = json.loads(json.dumps(pack))
        level = rng.randrange(len(trial))
        position = rng.randrange(len(trial[level]["games"]))
        replacement = rng.choice(sorted(lookup))
        old = trial[level]["games"][position]
        if replacement == old:
            continue
        # Swap with another level if the replacement is already on the board.
        for other in trial:
            if replacement in other["games"]:
                other["games"][other["games"].index(replacement)] = old
                break
        trial[level]["games"][position] = replacement
        previous = 0.0
        valid = True
        for index, entry in enumerate(trial):
            group = [lookup[game_id] for game_id in entry["games"]]
            score = generate_levels.similarity(group)
            if (score < previous + 0.004 or not generate_levels.distinguishable(group)
                    or not generate_levels.solvable(group)
                    or abs(score - generate_levels.TARGET_SIMILARITY[index]) > 0.04):
                valid = False
                break
            previous = score
        if valid:
            pack = trial
    # Even when no valid membership changes exist, change presentation order.
    for level in pack:
        rng.shuffle(level["games"])
    return pack


def to_output(day: str, pool: list[dict], history: dict | None = None) -> dict:
    """Reserve 45 games per day; all refreshes stay inside that reserve.

    Reserving the whole slate prevents refreshes from leaking games into the
    next day's board. A seven-day window needs at least 315 eligible games.
    Never relax the cooldown silently if the catalog is too small.
    """
    day = date.fromisoformat(day).isoformat()
    blocked = recent_ids(history or {}, day)
    available = sorted({g["id"]: g for g in pool if g["id"] not in blocked}.values(),
                       key=lambda game: game["id"])
    if len(available) < DAILY_POOL_SIZE:
        raise ValueError(
            f"Only {len(available)} fresh games remain after the seven-day cooldown; "
            f"need {DAILY_POOL_SIZE}. Increase --pages; history was not changed."
        )
    primary = generate_levels.generate(available, f"{day}#0")["packs"][0]
    selected = {game_id for level in primary for game_id in level["games"]}
    extras = [game for game in available if game["id"] not in selected]
    selected.update(g["id"] for g in random.Random(day + "#reserve").sample(
        extras, DAILY_POOL_SIZE - len(selected)))
    daily_pool = [g for g in available if g["id"] in selected]
    variants = [primary]
    for index in range(1, 3):
        variants.append(refresh_variant(primary, daily_pool, f"{day}#{index}"))
    games = {
        game["id"]: {key: value for key, value in game.items() if key not in ("id", "_tagset")}
        for game in daily_pool
    }
    return {
        "generated_for": day,
        "source": "RAWG",
        "pool_size": len(games),
        "games": games,
        "variants": variants,
        "cooldown_days": COOLDOWN_DAYS,
    }


def updated_history(history: dict, day: str, output: dict) -> dict:
    today = date.fromisoformat(day)
    result = {
        previous: sorted(set(ids)) for previous, ids in history.items()
        if 0 <= (today - date.fromisoformat(previous)).days < COOLDOWN_DAYS
    }
    # Store the full reserve, not just variant zero's forty candidates.
    result[day] = sorted(output["games"])
    return dict(sorted(result.items()))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--date", default=date.today().isoformat(), help="local date in YYYY-MM-DD")
    parser.add_argument("--pages", type=int, default=20, help="40 games fetched per page")
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--history", type=Path, default=HISTORY)
    args = parser.parse_args()
    day = date.fromisoformat(args.date).isoformat()
    if args.pages < 1:
        parser.error("--pages must be positive.")
    existing = json.loads(args.output.read_text(encoding="utf-8")) if args.output.exists() else {}
    history = existing.get("history", {})
    if args.history.exists():
        mirror = json.loads(args.history.read_text(encoding="utf-8"))
        # Older scheduled workflows may publish a newer embedded history but
        # leave the mirror untouched. Merge both instead of preferring stale data.
        for previous, ids in mirror.items():
            history[previous] = sorted(set(history.get(previous, [])) | set(ids))
    # Backdated generation could invalidate already published later boards.
    if any(date.fromisoformat(previous) > date.fromisoformat(day) for previous in history):
        parser.error("Cannot overwrite history with a backdated board; use separate --history and --output paths.")
    if day in history:
        if (existing.get("generated_for") == day and existing.get("variants")
                and set(existing.get("games", {})) == set(history[day])):
            print(f"Boards for {day} are already published; keeping them unchanged.")
            return
        parser.error("Today's history exists but its board is missing or inconsistent; restore the published board.")
    api_key = os.environ.get("RAWG_API_KEY")
    if not api_key:
        parser.error("Set RAWG_API_KEY in the environment.")
    try:
        pool = build_pool(api_key, args.pages)
    except Exception as exc:
        raise SystemExit("RAWG fetch failed: " + type(exc).__name__) from None
    if len(pool) < 45:
        raise SystemExit("Only %d usable games fetched; need at least 45." % len(pool))
    output = to_output(day, pool, history)
    history = updated_history(history, day, output)
    # Keep the cooldown durable even for older workflows that commit only
    # daily_pool.json. The separate history file is a readable mirror.
    output["history"] = history
    for path, payload in ((args.output, output), (args.history, history)):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote 3 boards from {output['pool_size']} reserved games to {args.output} for {day}; "
          f"catalog={len(pool)}, recent overlap=0")


if __name__ == "__main__":
    main()
