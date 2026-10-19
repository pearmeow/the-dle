# Guess What I Mean!

A daily Godot game about describing video games to a guessing partner named Jev. Choose a secret game, write a short clue, and try to get Jev to identify it in as few hints as possible.

## Play

Open `project.godot` in Godot 4.7 or run:

```sh
godot --path .
```

The game works immediately in **offline mode**. It has two curated daily boards, each with seven levels. The board alternates by local date. Candidate order changes by date. Progress and streaks are saved in Godot's `user://daily_save.json` for the current device.

1. Pick one of the displayed games as your secret target.
2. Write a hint without using words from its title.
3. Read Jev's guess. If it misses, use another clue.

Later levels have more similar candidates, shorter per-hint word limits, fewer guesses, and less explanation from Jev. A correct answer scores `max(100, 1000 − 220 × extra hints − 2 × total words − active seconds)`, with the time penalty capped at 150. A missed level scores zero. The game pauses its active timer while Jev is thinking or the window is unfocused.

Offline Jev is a deterministic clue matcher. It scores words and phrases against candidate features, favors details that are rare among the current options, and avoids prior guesses. It never receives the selected target. For real model guesses, use the optional server below.

## Use a model for Jev

The included Python server calls [TypeSafe's Jev API](https://docs.typesafe.ai/api) with a [Choice question](https://docs.typesafe.ai/primitives/choice) over the unguessed games. Jev returns a game ID, not generated prose, so the game supplies a short fixed line beneath the guess. The API key stays in the server process. Godot sends only the candidate list, hints, and previous guesses; it checks the selected target locally.

Copy `.env.example` to `.env` in the project root and put your TypeSafe API key there:

```dotenv
JEV_API_KEY=your_typesafe_api_key
```

The project `.env` file is ignored by Git. Start the server in one terminal, then the game in another:

```sh
python3 server/jev_server.py
```

```sh
JEV_API_URL=http://127.0.0.1:8765/guess godot --path .
```

The server reads `.env` from the project root regardless of your working directory. A process `JEV_API_KEY` takes precedence over `.env`; `JEV_MODEL` defaults to `jev-latest`. If the server is unreachable or returns an invalid answer, the game visibly falls back to offline Jev. The server listens on `127.0.0.1` by default. For a browser export, set `JEV_ALLOWED_ORIGIN` to the exact site origin and host the server behind HTTPS.

## Daily RAWG pool (CI-driven)

The curated boards ship with the game, so a RAWG key is not needed to play. For a live daily board that stays fresh after release, the project ships a two-step pipeline that keeps the RAWG API key out of the game binary:

1. **GitHub Actions** runs `tools/fetch_pool.py` once a day. The workflow at `.github/workflows/daily-pool.yml` uses the `RAWG_API_KEY` repository secret, fetches ~200 games, and commits `data/daily_pool.json` to the `naxin` branch.
2. **The Godot client** fetches that file from `https://raw.githubusercontent.com/pearmeow/the-dle/naxin/data/daily_pool.json` on launch, caches it to `user://daily_pool.json`, and asks `scripts/level_builder.gd` to compose the 7 levels locally. The seed is the date, so every player on the same day sees the same board. If the network is unreachable or the file is stale, the game falls back to the bundled copy or the curated `levels.json`.

Because level composition happens on the client, the in-game **RESHUFFLE BOARD** button on level 1 can rebuild the day's board with a different sub-seed without ever contacting RAWG. It is only available before the first secret is picked, limited to two uses per day (`refresh_count` in `user://daily_save.json`), and the result still counts for scoring.

### Set the RAWG secret once

In the GitHub repository, open **Settings → Secrets and variables → Actions → New repository secret** and add:

```
Name:  RAWG_API_KEY
Value: <your RAWG key>
```

Rotating the key later is a one-click edit in that same page; no code changes are needed. The workflow can also be triggered manually from the **Actions** tab (`workflow_dispatch`), optionally pinning a date.

### Local one-off generation

To create a pre-generated board on your own machine (useful for playtesting without touching CI):

```sh
RAWG_API_KEY=your_key python3 tools/fetch_pool.py --date 2026-10-19
# or the full pre-composed board (writes data/generated_levels.json)
RAWG_API_KEY=your_key python3 tools/generate_levels.py --date 2026-10-19
```

The generator compares gameplay tag sets with Jaccard similarity, selects candidate groups for seven increasing difficulty targets, and rejects duplicate or nearly indistinguishable candidates. Generated boards should be playtested before distribution; source tags can be sparse or noisy. Review [RAWG's API terms](https://rawg.io/apidocs) before publishing a game that uses its data.

## Checks

```sh
python3 -m unittest discover -s tests -p 'test_*.py' -v
godot --headless --path . -s res://tests/test_game.gd
godot --headless --path . -s res://tests/test_layout.gd
```
