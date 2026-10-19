extends SceneTree

class PreviewGame extends "res://scripts/main.gd":
	func _load_game_data() -> void:
		day_key = "2026-10-19"
		_load_curated_board()
	func _save_progress() -> void:
		pass
	func _fetch_latest_pool() -> void:
		pass


const Logic = preload("res://scripts/jev_logic.gd")
const Builder = preload("res://scripts/level_builder.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = PreviewGame.new()
	root.add_child(game)
	await process_frame
	assert(game.levels.size() == 7, "The daily run needs seven levels.")
	assert(Logic.reveals_title("It is Tetris", "Tetris"))
	assert(not Logic.reveals_title("falling blocks clear lines", "Tetris"))
	assert(Logic.reveals_shortcut("the third game"))
	assert(not Logic.reveals_shortcut("three dimensional sword fights"))
	var sample := [
		{"id": "tetris", "name": "Tetris", "blurb": "Rotate falling shapes", "features": ["falling blocks", "clear lines"]},
		{"id": "stardew", "name": "Stardew Valley", "blurb": "Farm crops", "features": ["farming", "villagers"]},
		{"id": "rocket_league", "name": "Rocket League", "blurb": "Car soccer", "features": ["cars", "goals"]},
	]
	assert(Logic.guess(sample, ["falling blocks clear lines"], [])["id"] == "tetris")
	_check_level_builder()
	game.stage = "select"
	game.results.clear()
	game.level_index = 0
	for index in range(7):
		var id: String = game._current_ids()[0]
		game._choose_target(id)
		assert(game.stage == "hint")
		if index == 0:
			game.hint_edit.text = game._game_name(id)
			game._submit_hint()
			assert(game.stage == "hint" and game.hints.is_empty(), "Title clues must be rejected.")
		game.hints.append("A distinctive feature")
		game.stage = "thinking"
		game._resolve_guess(id, "That feature fits.")
		assert(game.stage == "won" and game.results.size() == index + 1)
		game._next_level()
	assert(game.stage == "complete")
	assert(game.results.size() == 7)
	assert(game._total_score() > 0)
	print("Godot gameplay tests passed")
	quit(0)


func _check_level_builder() -> void:
	# Synthesize a diverse pool so LevelBuilder has room to work.
	var games_dict := {}
	for i in range(70):
		var id := "fake_%02d" % i
		games_dict[id] = {
			"name": "Game %02d" % i,
			"genre": "Arcade",
			"blurb": "Pretend blurb.",
			"features": [
				"cluster %d" % (i / 10),
				"style %d" % (i % 7),
				"mechanic %d" % (i % 11),
				"setting %d" % (i % 13),
				"unique %d" % i,
			],
		}
	var pack_a := Builder.build_pack(games_dict, "2026-10-19#0")
	var pack_b := Builder.build_pack(games_dict, "2026-10-19#1")
	assert(pack_a.size() == 7, "LevelBuilder must emit seven levels.")
	assert(pack_b.size() == 7, "Refresh variant must emit seven levels.")
	for i in range(Builder.SIZES.size()):
		assert(pack_a[i]["games"].size() == int(Builder.SIZES[i]), "Level %d has wrong candidate count." % i)
	var pack_a_ids := _flatten_ids(pack_a)
	var pack_b_ids := _flatten_ids(pack_b)
	assert(pack_a_ids != pack_b_ids, "Different refresh seeds should produce different boards.")
	# Determinism: same seed, same result.
	var pack_a_repeat := Builder.build_pack(games_dict, "2026-10-19#0")
	assert(_flatten_ids(pack_a_repeat) == pack_a_ids, "LevelBuilder must be deterministic for a given seed.")
	print("LevelBuilder tests passed")


func _flatten_ids(pack: Array) -> Array:
	var out: Array = []
	for level in pack:
		for id in level["games"]:
			out.append(String(id))
	return out
