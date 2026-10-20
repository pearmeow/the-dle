extends SceneTree
class NavGame extends "res://scripts/main.gd":
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
	var game := NavGame.new()
	game.size = Vector2(1440,900)
	root.add_child(game)
	game._start_game()
	var board := game.levels.duplicate(true)
	game._choose_target(game._current_ids()[0])
	game.hint_edit.text = "A draft clue"
	game.elapsed = 12.0
	var target := game.target_id
	game._back_to_main_menu()
	game._process(5.0)
	assert(game.showing_title and game.elapsed == 12.0, "Menu must pause the timer.")
	game._start_game()
	assert(game.target_id == target and game.hint_edit.text == "A draft clue", "Continue must preserve the target and draft.")
	game.results = [{"score": 500}]
	game.hints = ["old hint"]
	var old_generation := game.run_generation
	game._restart_run()
	assert(game.level_index == 0 and game.stage == "select" and not game.showing_title)
	assert(game.elapsed == 0 and game.results.is_empty() and game.hints.is_empty() and game.target_id.is_empty())
	assert(game.levels == board, "Restart must preserve today's board.")
	game.stage = "thinking"
	game._resolve_local_guess_for_run(old_generation)
	assert(game.guesses.is_empty(), "Old pending guesses must not enter a restarted run.")
	print("Main menu, continue, restart, and stale-guess checks passed")
	quit()
