import json
import io
import os
import sys
import tempfile
import unittest
from datetime import date, timedelta
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "server"))
sys.path.insert(0, str(ROOT / "tools"))

import jev_server
import generate_levels
import fetch_pool


class FakeResponse:
    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self):
        return json.dumps({"answers": {"game_guess": {
            "type": "choice", "choice": "a", "probabilities": {"a": 0.8, "b": 0.2},
            "confidence": 0.6,
        }}}).encode()


class GameToolTests(unittest.TestCase):
    @staticmethod
    def diverse_pool(size=400):
        return [
            {"id": f"rawg_{i:04d}", "name": f"Game {i}", "genre": "Arcade",
             "features": [f"cluster {i % 8}", f"style {i % 7}", f"mechanic {i % 11}",
                          f"setting {i % 13}", f"unique {i}"]}
            for i in range(size)
        ]

    def test_curated_catalog_has_two_complete_boards(self):
        data = json.loads((ROOT / "data" / "levels.json").read_text())
        for board in data["packs"]:
            self.assertEqual(len(board), 7)
            for index, level in enumerate(board):
                self.assertEqual(len(level["games"]), generate_levels.SIZES[index])
                self.assertTrue(all(game_id in data["games"] for game_id in level["games"]))

    def test_target_marker_never_reaches_model(self):
        body = {
            "target_id": "a",
            "candidates": [
                {"id": "a", "name": "Alpha", "features": ["cars"]},
                {"id": "b", "name": "Beta", "features": ["cards"]},
            ],
            "hints": ["Vehicles"],
            "previous_guesses": [],
            "level": 1,
        }
        clean = jev_server.validate_game_request(body)
        captured = {}

        def fake_urlopen(request, timeout):
            captured["body"] = json.loads(request.data)
            captured["authorization"] = request.get_header("Authorization")
            return FakeResponse()

        with patch.dict(os.environ, {"JEV_API_KEY": "test-only"}), patch.object(jev_server, "urlopen", fake_urlopen):
            answer = jev_server.ask_jev(*clean)
        self.assertEqual(answer["guess_id"], "a")
        self.assertEqual(captured["authorization"], "Bearer test-only")
        self.assertEqual(captured["body"]["model"], "jev-latest")
        self.assertEqual(captured["body"]["state"], {"hints_in_order": ["Vehicles"]})
        self.assertEqual(captured["body"]["questions"]["game_guess"]["type"], "choice")
        self.assertEqual(set(captured["body"]["questions"]["game_guess"]["criteria"]), {"a", "b"})
        self.assertNotIn("target_id", json.dumps(captured["body"]))

    def test_jev_uses_the_only_remaining_game_without_api_call(self):
        games = [
            {"id": "a", "name": "Alpha", "genre": "Arcade", "description": "Cars", "features": []},
            {"id": "b", "name": "Beta", "genre": "Puzzle", "description": "Cards", "features": []},
        ]
        with patch.object(jev_server, "urlopen") as api_call:
            answer = jev_server.ask_jev(games, ["cards"], ["a"], 1)
        self.assertEqual(answer["guess_id"], "b")
        api_call.assert_not_called()

    def test_jev_rejects_invalid_choice(self):
        games = [
            {"id": "a", "name": "Alpha", "genre": "Arcade", "description": "Cars", "features": []},
            {"id": "b", "name": "Beta", "genre": "Puzzle", "description": "Cards", "features": []},
        ]

        class InvalidResponse(FakeResponse):
            def read(self):
                return b'{"answers":{"game_guess":{"type":"choice","choice":"missing"}}}'

        with patch.dict(os.environ, {"JEV_API_KEY": "test-only"}), patch.object(jev_server, "urlopen", return_value=InvalidResponse()):
            with self.assertRaisesRegex(ValueError, "invalid candidate ID"):
                jev_server.ask_jev(games, ["cards"], [], 1)

    def test_jev_api_key_loads_from_env_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / ".env"
            path.write_text('JEV_API_KEY="file-key" # local test key\n')
            with patch.dict(os.environ, {"JEV_API_KEY": ""}):
                self.assertEqual(jev_server.get_api_key(path), "file-key")
            with patch.dict(os.environ, {"JEV_API_KEY": "shell-key"}):
                self.assertEqual(jev_server.get_api_key(path), "shell-key")

    def test_jaccard_and_distinctiveness(self):
        first = {"name": "First", "features": ["cards", "train", "spells"]}
        second = {"name": "Second", "features": ["cards", "poker", "jokers"]}
        self.assertAlmostEqual(generate_levels.jaccard(first, second), 0.2)
        self.assertTrue(generate_levels.distinguishable([first, second]))

    def test_fetch_pool_output_has_stable_shape(self):
        pool = self.diverse_pool(70)
        with patch.object(fetch_pool.generate_levels, "fetch_games", return_value=pool):
            built = fetch_pool.build_pool("fake-key", pages=1)
        self.assertEqual([g["id"] for g in built], sorted(g["id"] for g in pool))
        payload = fetch_pool.to_output("2026-10-19", built)
        self.assertEqual(payload["generated_for"], "2026-10-19")
        self.assertEqual(payload["source"], "RAWG")
        self.assertEqual(payload["pool_size"], fetch_pool.DAILY_POOL_SIZE)
        self.assertTrue(set(payload["games"]) <= {g["id"] for g in pool})
        self.assertEqual(len(payload["variants"]), 3)
        self.assertNotIn("id", next(iter(payload["games"].values())))

    def test_fourteen_days_have_no_repeated_games_in_any_seven_day_window(self):
        pool = self.diverse_pool()
        history = {}
        published = []
        for offset in range(14):
            day = (date(2026, 10, 19) + timedelta(days=offset)).isoformat()
            output = fetch_pool.to_output(day, pool, history)
            reserve = set(output["games"])
            for previous in published[-6:]:
                self.assertFalse(reserve & previous)
            for pack in output["variants"]:
                self.assertEqual([len(level["games"]) for level in pack], generate_levels.SIZES)
                ids = [game_id for level in pack for game_id in level["games"]]
                self.assertEqual(len(ids), len(set(ids)))
                self.assertTrue(set(ids) <= reserve)
                lookup = {g["id"]: g for g in pool}
                previous_score = 0.0
                for level in pack:
                    group = [lookup[game_id] for game_id in level["games"]]
                    self.assertTrue(generate_levels.distinguishable(group))
                    self.assertTrue(generate_levels.solvable(group))
                    score = generate_levels.similarity(group)
                    self.assertGreaterEqual(score, previous_score + 0.004)
                    previous_score = score
            published.append(reserve)
            history = fetch_pool.updated_history(history, day, output)
            self.assertLessEqual(len(history), 7)

    def test_cooldown_boundary_uses_calendar_days_and_ignores_today(self):
        history = {"2026-10-12": ["expired"], "2026-10-13": ["blocked"],
                   "2026-10-18": ["yesterday"], "2026-10-19": ["today"]}
        self.assertEqual(fetch_pool.recent_ids(history, "2026-10-19"), {"blocked", "yesterday"})

    def test_short_pool_fails_without_relaxing_cooldown(self):
        pool = self.diverse_pool(70)
        history = {"2026-10-18": [g["id"] for g in pool[:40]]}
        with self.assertRaisesRegex(ValueError, "Increase --pages"):
            fetch_pool.to_output("2026-10-19", pool, history)
        self.assertEqual(len(history["2026-10-18"]), 40)

    def test_same_day_is_deterministic_even_with_reordered_pool(self):
        pool = self.diverse_pool(70)
        first = fetch_pool.to_output("2026-10-19", pool)
        history = fetch_pool.updated_history({}, "2026-10-19", first)
        self.assertEqual(first, fetch_pool.to_output("2026-10-19", list(reversed(pool)), history))

    def test_cli_rerun_preserves_published_board_without_fetching(self):
        with tempfile.TemporaryDirectory() as directory:
            output_path = Path(directory) / "daily_pool.json"
            history_path = Path(directory) / "daily_history.json"
            output = {"generated_for": "2026-10-19", "variants": [["published"]],
                      "games": {"a": {}}}
            output_path.write_text(json.dumps(output), encoding="utf-8")
            history_path.write_text(json.dumps({"2026-10-19": ["a"]}), encoding="utf-8")
            before = (output_path.read_bytes(), history_path.read_bytes())
            argv = ["fetch_pool", "--date", "2026-10-19", "--output", str(output_path),
                    "--history", str(history_path)]
            with patch.object(sys, "argv", argv), patch.object(fetch_pool, "build_pool") as fetch:
                fetch_pool.main()
            fetch.assert_not_called()
            self.assertEqual(before, (output_path.read_bytes(), history_path.read_bytes()))

    def test_cli_failed_generation_does_not_modify_published_files(self):
        with tempfile.TemporaryDirectory() as directory:
            output_path = Path(directory) / "daily_pool.json"
            history_path = Path(directory) / "daily_history.json"
            pool = self.diverse_pool(70)
            output_path.write_text('{"generated_for":"2026-10-18"}', encoding="utf-8")
            history_path.write_text(json.dumps({"2026-10-18": [g["id"] for g in pool[:40]]}),
                                    encoding="utf-8")
            before = (output_path.read_bytes(), history_path.read_bytes())
            argv = ["fetch_pool", "--date", "2026-10-19", "--output", str(output_path),
                    "--history", str(history_path)]
            with (patch.object(sys, "argv", argv), patch.dict(os.environ, {"RAWG_API_KEY": "test"}),
                  patch.object(fetch_pool, "build_pool", return_value=pool)):
                with self.assertRaisesRegex(ValueError, "Increase --pages"):
                    fetch_pool.main()
            self.assertEqual(before, (output_path.read_bytes(), history_path.read_bytes()))

    def test_cli_rejects_backdated_history_before_fetching(self):
        with tempfile.TemporaryDirectory() as directory:
            history_path = Path(directory) / "daily_history.json"
            history_path.write_text('{"2026-10-20":["a"]}', encoding="utf-8")
            argv = ["fetch_pool", "--date", "2026-10-19", "--history", str(history_path)]
            with (patch.object(sys, "argv", argv), patch.object(sys, "stderr", io.StringIO()),
                  patch.object(fetch_pool, "build_pool") as fetch):
                with self.assertRaises(SystemExit) as error:
                    fetch_pool.main()
            self.assertEqual(error.exception.code, 2)
            fetch.assert_not_called()

    def test_cli_uses_embedded_history_when_older_workflow_did_not_commit_mirror(self):
        with tempfile.TemporaryDirectory() as directory:
            output_path = Path(directory) / "daily_pool.json"
            history_path = Path(directory) / "daily_history.json"
            pool = self.diverse_pool(70)
            output = {"generated_for": "2026-10-18",
                      "history": {"2026-10-18": [g["id"] for g in pool[:40]]}}
            output_path.write_text(json.dumps(output), encoding="utf-8")
            before = output_path.read_bytes()
            argv = ["fetch_pool", "--date", "2026-10-19", "--output", str(output_path),
                    "--history", str(history_path)]
            with (patch.object(sys, "argv", argv), patch.dict(os.environ, {"RAWG_API_KEY": "test"}),
                  patch.object(fetch_pool, "build_pool", return_value=pool)):
                with self.assertRaisesRegex(ValueError, "Increase --pages"):
                    fetch_pool.main()
            self.assertEqual(before, output_path.read_bytes())
            self.assertFalse(history_path.exists())

    def test_cli_publishes_identical_embedded_and_mirrored_history(self):
        with tempfile.TemporaryDirectory() as directory:
            output_path = Path(directory) / "daily_pool.json"
            history_path = Path(directory) / "daily_history.json"
            payload = {"generated_for": "2026-10-19", "games": {"new": {}},
                       "variants": [[], [], []], "pool_size": 1}
            argv = ["fetch_pool", "--date", "2026-10-19", "--output", str(output_path),
                    "--history", str(history_path)]
            with (patch.object(sys, "argv", argv), patch.dict(os.environ, {"RAWG_API_KEY": "test"}),
                  patch.object(fetch_pool, "build_pool", return_value=self.diverse_pool(70)),
                  patch.object(fetch_pool, "to_output", return_value=payload)):
                fetch_pool.main()
            published = json.loads(output_path.read_text(encoding="utf-8"))
            mirror = json.loads(history_path.read_text(encoding="utf-8"))
            self.assertEqual(published["history"], mirror)
            self.assertEqual(mirror, {"2026-10-19": ["new"]})

    def test_cli_stale_mirror_cannot_hide_newer_embedded_history(self):
        with tempfile.TemporaryDirectory() as directory:
            output_path = Path(directory) / "daily_pool.json"
            history_path = Path(directory) / "daily_history.json"
            pool = self.diverse_pool(70)
            output = {"generated_for": "2026-10-18",
                      "history": {"2026-10-18": [g["id"] for g in pool[:40]]}}
            output_path.write_text(json.dumps(output), encoding="utf-8")
            history_path.write_text('{"2026-10-17":["older"]}', encoding="utf-8")
            argv = ["fetch_pool", "--date", "2026-10-19", "--output", str(output_path),
                    "--history", str(history_path)]
            with (patch.object(sys, "argv", argv), patch.dict(os.environ, {"RAWG_API_KEY": "test"}),
                  patch.object(fetch_pool, "build_pool", return_value=pool)):
                with self.assertRaisesRegex(ValueError, "Increase --pages"):
                    fetch_pool.main()

    def test_generated_board_gets_more_similar(self):
        pool = [
            {
                "id": str(i),
                "name": f"Game {i}",
                "genre": "Arcade",
                "features": [
                    f"cluster {i // 10}", f"style {i % 7}", f"mechanic {i % 11}",
                    f"setting {i % 13}", f"unique {i}",
                ],
            }
            for i in range(70)
        ]
        board = generate_levels.generate(pool, "2026-10-18")
        lookup = {game["id"]: game for game in pool}
        scores = [
            generate_levels.similarity([lookup[game_id] for game_id in level["games"]])
            for level in board["packs"][0]
        ]
        self.assertTrue(all(a < b for a, b in zip(scores, scores[1:])))


if __name__ == "__main__":
    unittest.main()
