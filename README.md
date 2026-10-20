# Guess What I Mean!

A daily Godot game about describing video games to a guessing partner named Jev. Choose a secret game, write a short clue, and try to get Jev to identify it in as few hints as possible.

## Play

The illustrated title screen offers **Start today’s game**, **How to play**, and **Settings** (fullscreen). Returning to the menu preserves the current run. The timer remains stopped on the title screen and starts after pressing Start or Continue.

Open `project.godot` in Godot 4.7 or run:

```sh
godot --path .
```

The game works immediately in **offline mode**. It has two curated daily boards, each with seven levels. The board alternates by local date. Candidate order changes by date. The current `PERSIST_PROGRESS = false` setting starts a fresh run after closing the game; set it to `true` to save progress and streaks in Godot's `user://daily_save.json` for the current device.

1. Pick one of the displayed games as your secret target.
2. Write a hint without using words from its title.
3. Read Jev's guess. If it misses, use another clue.

Later levels have more similar candidates, shorter per-hint word limits, fewer guesses, and less explanation from Jev. A correct answer scores `max(100, 1000 − 220 × extra hints − 2 × total words − active seconds)`, with the time penalty capped at 150. A missed level scores zero. The per-level timer starts when the candidate cards appear and includes Quick intro reading and clue-writing time. It pauses while Jev is thinking or the window is unfocused.

Offline Jev is a deterministic clue matcher. It scores words and phrases against candidate features, favors details that are rare among the current options, and avoids prior guesses. It never receives the selected target. For real model guesses, use the optional server below.

## Fresh UI playtest

Run `godot --path . -- --playtest` for a fresh run without reading or writing daily progress. The window is labeled **Playtest**. Close it when finished. Normal launches use the `PERSIST_PROGRESS` setting.

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

1. **GitHub Actions** runs `tools/fetch_pool.py` once a day using the `RAWG_API_KEY` repository secret. It fetches up to 800 games (20 pages, before filtering), reads the persistent history from `naxin`, and excludes games reserved on the previous six calendar dates. It precomputes seven levels and two refresh variants, then commits the board and history to `naxin` together.
2. **The Godot client** fetches `https://raw.githubusercontent.com/pearmeow/the-dle/naxin/data/daily_pool.json` on launch and caches it to `user://daily_pool.json`. It validates and reads the precomputed variants directly, so every player sees the same boards. If the network is unreachable or the file is stale, the game falls back to the bundled copy or the curated `levels.json`.

The in-game **RESHUFFLE BOARD** button switches to the next precomputed variant without contacting RAWG. It is only available before the first secret is picked and limited to two uses per run. With `PERSIST_PROGRESS = true`, remaining refreshes are saved across launches for the current day. The result still counts for scoring.

### Seven-day freshness policy

Each day reserves 45 games: 40 distinct candidates for the initial seven levels plus five alternatives. Both refresh variants stay inside the same reserve. Refreshes preserve distinct candidates, uniquely describable clues, and increasing tag similarity. If no valid membership changes exist, a refresh can retain the same groups with a different option order.

The next six calendar dates exclude all 45 reserved IDs, so **any seven consecutive published calendar dates have no repeated games**, including refresh options. Games become eligible again after seven days. The policy starts when history is first recorded; it cannot reconstruct old client-generated boards. It does not apply to the two fixed offline curated boards or the standalone `generate_levels.py` command.

History is stored inside `daily_pool.json` and mirrored in `data/daily_history.json`. This preserves the cooldown even when an older workflow commits only `daily_pool.json`. Keep the published JSON between runs: runner-local caches alone are insufficient. Successful same-day reruns keep the published board unchanged. Backdated generation against newer history is rejected; use separate `--output` and `--history` paths for experiments.

The minimum catalog size is 315 usable games for seven days of reserves; similarity and solvability constraints can require more. If fewer than 45 fresh games remain, or no valid board can be formed, generation fails without relaxing the cooldown or changing history. Increase `--pages` in the workflow if this happens.

The updated workflow checks out generator code from the branch being run and published data from `naxin` separately. To publish immediately, manually run **Daily game pool** with branch **naxin** selected, then verify the resulting commit contains both JSON files. Scheduled workflows use the repository's default branch: merge the updated workflow and generator there to use the new workflow automatically. The previous workflow also checks out `naxin`, so it can still execute the updated generator and preserve embedded history. The runner defaults to UTC dates while clients check local dates; near a date boundary clients can temporarily use the offline fallback.

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
# standalone one-off board, without the seven-day history policy
RAWG_API_KEY=your_key python3 tools/generate_levels.py --date 2026-10-19
```

The generator compares gameplay tag sets with Jaccard similarity, selects candidate groups for seven increasing difficulty targets, and rejects duplicate or nearly indistinguishable candidates. Generated boards should be playtested before distribution; source tags can be sparse or noisy. Review [RAWG's API terms](https://rawg.io/apidocs) before publishing a game that uses its data.

## Checks

```sh
python3 -m unittest discover -s tests -p 'test_*.py' -v
godot --headless --path . -s res://tests/test_game.gd
godot --headless --path . -s res://tests/test_layout.gd
godot --headless --path . -s res://tests/test_daily_pool.gd
```
