extends SceneTree

const Logic = preload("res://scripts/jev_logic.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://main.tscn")
	var game = scene.instantiate()
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
