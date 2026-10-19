extends SceneTree
class TitleGame extends "res://scripts/main.gd":
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
	var game := TitleGame.new()
	game.size = Vector2(1440,900)
	root.add_child(game)
	game._process(10.0)
	assert(game.showing_title and game.elapsed == 0.0, "Title screen must not start the timer.")
	game._show_help()
	game._process(5.0)
	assert(game.has_node("MenuSheet") and game.elapsed == 0.0, "Rules before Start must be untimed.")
	game.get_node("MenuSheet").queue_free()
	await process_frame
	game._show_settings()
	assert(game.has_node("MenuSheet"), "Settings must open.")
	game.get_node("MenuSheet").queue_free()
	await process_frame
	game._start_game()
	game._process(3.0)
	assert(not game.showing_title and game.elapsed >= 3.0, "Start must begin the level timer.")
	assert(game.stage == "select", "Start must show the candidate board.")
	print("Title screen, rules, settings, and timer checks passed")
	await create_timer(1.1).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	quit()
