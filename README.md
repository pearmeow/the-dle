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

## Generate a board from RAWG

The curated boards ship with the game, so a RAWG key is not needed to play. To create a fresh dated board from [RAWG's game database](https://rawg.io/apidocs):

```sh
RAWG_API_KEY=your_key python3 tools/generate_levels.py --date 2026-10-18
```

The generator fetches public game metadata, compares gameplay tag sets with Jaccard similarity, selects candidate groups for seven increasing difficulty targets, and rejects duplicate or nearly indistinguishable candidates. It writes `data/generated_levels.json`. The game uses that board only on its matching local date and shows a clickable RAWG attribution link. Generated boards should be playtested before distribution; source tags can be sparse or noisy. Review [RAWG's API terms](https://rawg.io/apidocs) before publishing a game that uses its data.

## Checks

```sh
python3 -m unittest discover -s tests -p 'test_*.py' -v
godot --headless --path . -s res://tests/test_game.gd
godot --headless --path . -s res://tests/test_layout.gd
```
