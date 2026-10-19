import json
import os
import sys
import tempfile
import unittest
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
        pool = [
            {
                "id": f"rawg_{i}",
                "name": f"Game {i}",
                "genre": "Arcade",
                "blurb": "Gameplay tags: alpha, beta.",
                "features": [f"cluster {i // 10}", f"mechanic {i % 11}", "shared tag"],
                "rawg_url": f"https://rawg.io/games/{i}",
            }
            for i in range(60)
        ]
        with patch.object(fetch_pool.generate_levels, "fetch_games", return_value=pool):
            built = fetch_pool.build_pool("fake-key", pages=1)
        self.assertEqual([g["id"] for g in built], sorted(g["id"] for g in pool))
        payload = fetch_pool.to_output("2026-10-19", built)
        self.assertEqual(payload["generated_for"], "2026-10-19")
        self.assertEqual(payload["source"], "RAWG")
        self.assertEqual(payload["pool_size"], len(pool))
        self.assertEqual(set(payload["games"]), {g["id"] for g in pool})
        self.assertNotIn("id", next(iter(payload["games"].values())))

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
