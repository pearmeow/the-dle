# Guess What I Mean!

A daily Godot game about describing video games to a guessing partner named Jev. Choose a secret game, write a short clue, and try to get Jev to identify it in as few hints as possible.

## Play

The illustrated title screen offers **Start today’s game**, **How to play**, and **Settings** (fullscreen). Returning players can continue their saved run. The timer remains stopped on the title screen and starts after pressing Start or Continue.

Open `project.godot` in Godot 4.7 or run:

```sh
godot --path .
```

The game works immediately in **offline mode**. It has two curated daily boards, each with seven levels. The board alternates by local date. Candidate order changes by date. Progress and streaks are saved in Godot's `user://daily_save.json` for the current device.

1. Pick one of the displayed games as your secret target.
2. Write a hint without using words from its title.
3. Read Jev's guess. If it misses, use another clue.

Later levels have more similar candidates, shorter per-hint word limits, fewer guesses, and less explanation from Jev. A correct answer scores `max(100, 1000 − 220 × extra hints − 2 × total words − active seconds)`, with the time penalty capped at 150. A missed level scores zero. The per-level timer starts when the candidate cards appear and includes Quick intro reading and clue-writing time. It pauses while Jev is thinking or the window is unfocused.

Offline Jev is a deterministic clue matcher. It scores words and phrases against candidate features, favors details that are rare among the current options, and avoids prior guesses. It never receives the selected target. For real model guesses, use the optional server below.

## Fresh UI playtest

Run `godot --path . -- --playtest` for a fresh run without reading or writing daily progress. The window is labeled **Playtest**. Close it when finished. Normal launches continue using the daily save.

The tabletop interface uses matching game covers where available and typographic game-file cards for other titles. Cover sources are recorded in `assets/game-covers.json`; original mascot prompts and font license information are in `assets/ARTWORK.md`.

## Music

“Thinking Music” by Kevin MacLeod plays quietly across the title screen and gameplay, with a fade-in and looping playback. Use **Music on/off** during a run or **Settings** for volume and mute. Audio preferences are saved separately from daily progress. Full source and CC BY 4.0 attribution are in `assets/audio/CREDITS.md` and the in-game Settings panel.

## Interaction feedback

Buttons use a soft tap; correct guesses, missed guesses, level advancement, and daily completion each have their own quiet sound. Sound effects have independent volume and mute controls in Settings. The shared `_button` helper adds click feedback automatically to new buttons. Original effects are reproducible with `tools/generate_sfx.py`.

## Use a model for Jev

Jev can be powered by [TypeSafe's Jev API](https://docs.typesafe.ai/api) with a [Choice question](https://docs.typesafe.ai/primitives/choice) over the unguessed games. The API returns a game ID, not generated prose, so the game supplies a short fixed line beneath the guess. Godot sends only the candidate list, hints, and previous guesses; the selected target is checked locally and never leaves the client.

The TypeSafe API key must stay on a backend you control. Two paths ship:

### Option A — Cloudflare Worker (recommended for itch.io / web builds)

See `server/jev_worker/README.md` for the full walkthrough. Short version:

```powershell
cd server\jev_worker
npm install
npx wrangler login
npx wrangler secret put JEV_API_KEY   # paste the TypeSafe key when prompted
npx wrangler deploy                   # publishes to <name>.<account>.workers.dev
```

Update `DEFAULT_JEV_URL` in `scripts/main.gd` to the Worker URL (plus `/guess`). The game picks this up automatically on launch; HTML5 builds have no process env, so the constant is the only way they find the endpoint. The Worker holds the key in Cloudflare's secret store and is the only process that ever sees it.

### Option B — Local Python server (handy during development)

Copy `.env.example` to `.env` in the project root and add your key:

```dotenv
JEV_API_KEY=your_typesafe_api_key
```

The project `.env` file is ignored by Git. Start the server, then the game, in separate terminals:

```sh
python3 server/jev_server.py
```

```sh
JEV_API_URL=http://127.0.0.1:8765/guess godot --path .
```

The server reads `.env` from the project root regardless of your working directory. A process `JEV_API_KEY` takes precedence over `.env`; `JEV_MODEL` defaults to `jev-latest`. If the server is unreachable or returns an invalid answer, the game visibly falls back to offline Jev. The server listens on `127.0.0.1` by default. For a browser export, set `JEV_ALLOWED_ORIGIN` to the exact site origin and host the server behind HTTPS — or just use the Cloudflare Worker above, which already runs on HTTPS.

## Daily RAWG pool (CI-driven)

The curated boards ship with the game, so a RAWG key is not needed to play. For a live daily board that stays fresh after release, the project ships a two-step pipeline that keeps the RAWG API key out of the game binary:

1. **GitHub Actions** runs `tools/fetch_pool.py` once a day. The workflow at `.github/workflows/daily-pool.yml` uses the `RAWG_API_KEY` repository secret, fetches ~200 games, and commits `data/daily_pool.json` to the `naxin` branch.
2. **The Godot client** fetches that file from `https://raw.githubusercontent.com/pearmeow/the-dle/naxin/data/daily_pool.json` on launch, caches it to `user://daily_pool.json`, and loads one of the three seven-level boards precomputed by CI. The seed is the date, so every player on the same day sees the same board. If the network is unreachable or the file is stale, the game falls back to the bundled copy or the curated `levels.json`.

The in-game **Reshuffle board** button on level 1 switches to another precomputed variant without contacting RAWG or blocking the game with level generation. It is only available before the first secret is picked, limited to two uses per day (`refresh_count` in `user://daily_save.json`), and the result still counts for scoring.

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

## Integrated branch

`integration/matt-naxin-main` combines `Matt`, `naxin`, and shared `main`. It keeps Matt’s illustrated interface, timed Quick intros, menu, restart, music, and effects; adds Naxin’s Worker proxy, AI/offline switch, and precomputed daily variants; and preserves daily Continue saves. The AI switch is disabled while a guess is pending. Main was already an ancestor of Matt at integration time.

## Local game information library

The integrated build bundles `data/game-library.json` with matching images in `assets/daily-covers/` for all 384 games in the current daily pool. Each record contains an original concise gameplay overview and the RAWG game-page and image-source links. The card and Quick intro use the same overview supplied to Jev; every overview fits the existing remote proxy’s 250-character limit. Reading intros remains part of the active timer.

This library stays separate from the downloaded daily pool, so refreshed boards retain local artwork and introductions for known IDs or matching titles. A newly introduced title outside these 384 entries still uses its supplied metadata and the existing fallback artwork until added to the library. The older curated-board cover collection remains available.
