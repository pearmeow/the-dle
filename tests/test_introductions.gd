extends SceneTree

class IntroGame extends "res://scripts/main.gd":
	func _game_has_focus() -> bool:
		return true
	func _load_game_data() -> void:
		day_key = "2026-10-19"
		_load_curated_board()
	func _load_daily_progress() -> void:
		pass
	func _save_progress() -> void:
		pass
	func _fetch_latest_pool() -> void:
		pass

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game := IntroGame.new()
	game.size = Vector2(1440, 900)
	root.add_child(game)
	game._start_game()
	for id in game.catalog:
		game._show_game_intro(id)
		assert(game.intro_open and game.has_node("GameIntro"), "Every game needs an introduction.")
		assert(game.stage == "select" and game.target_id.is_empty(), "Reading must not select a target.")
		game._close_game_intro(game.get_node("GameIntro"))
		await process_frame
	game._show_game_intro(game._current_ids()[0])
	var selection_before := game.elapsed
	game._process(4.0)
	assert(is_equal_approx(game.elapsed, selection_before + 4.0), "Reading before choosing must count.")
	game._close_game_intro(game.get_node("GameIntro"))
	await process_frame
	var choice_before := game.elapsed
	game._choose_target(game._current_ids()[0])
	assert(is_equal_approx(game.elapsed, choice_before), "Choosing must preserve reading time.")
	game.hint_draft = "A clue in progress"
	game._show_game_intro(game.target_id)
	var before := game.elapsed
	game._process(3.0)
	assert(is_equal_approx(game.elapsed, before + 3.0), "Reading must count toward active time.")
	assert(game.stage == "hint" and game.hint_draft == "A clue in progress", "Reading must preserve the clue.")
	game._close_game_intro(game.get_node("GameIntro"))
	assert(not game.intro_open, "Closing must dismiss the introduction.")
	print("All 70 game introductions and reading-time checks passed")
	quit()
