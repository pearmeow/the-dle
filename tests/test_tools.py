import json
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "server"))
sys.path.insert(0, str(ROOT / "tools"))

import jev_server
import generate_levels


class FakeResponse:
    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self):
        return json.dumps({"output": [{"type": "message", "content": [
            {"type": "output_text", "text": '{"guess_id":"a","reason":"It fits."}'},
        ]}]}).encode()


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
            return FakeResponse()

        with patch.dict(os.environ, {"OPENAI_API_KEY": "test-only"}), patch.object(jev_server, "urlopen", fake_urlopen):
            answer = jev_server.ask_jev(*clean)
        self.assertEqual(answer["guess_id"], "a")
        self.assertNotIn("target_id", captured["body"]["input"])

    def test_jaccard_and_distinctiveness(self):
        first = {"name": "First", "features": ["cards", "train", "spells"]}
        second = {"name": "Second", "features": ["cards", "poker", "jokers"]}
        self.assertAlmostEqual(generate_levels.jaccard(first, second), 0.2)
        self.assertTrue(generate_levels.distinguishable([first, second]))

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
