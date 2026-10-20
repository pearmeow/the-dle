extends SceneTree

class IntegratedGame extends "res://scripts/main.gd":
	func _load_game_data() -> void:
		day_key = "2026-10-19"
		assert(_try_load_pool_board(BUNDLED_POOL), "Bundled daily variants must load.")
	func _load_daily_progress() -> void:
		pass
	func _save_progress() -> void:
		pass
	func _fetch_latest_pool() -> void:
		pass

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game := IntegratedGame.new()
	game.size = Vector2(1440, 900)
	root.add_child(game)
	assert(game.showing_title and game.levels.size() == 7)
	assert(game.pool_variants.size() == 3)
	assert(game.jev_url == game.DEFAULT_JEV_URL)
	game._start_game()
	var first := JSON.stringify(game.levels)
	game._refresh_board()
	assert(game.refresh_count == 1 and JSON.stringify(game.levels) != first)
	game._refresh_board()
	assert(game.refresh_count == 2 and not game._can_refresh())
	game._toggle_remote_jev()
	assert(not game.use_remote_jev)
	game._choose_target(String(game._current_ids()[0]))
	game.hint_edit.text = "mysterious distant world"
	game._submit_hint()
	assert(game.stage == "thinking")
	game._toggle_remote_jev()
	assert(not game.use_remote_jev, "Cannot switch guess engines during a pending guess.")
	await create_timer(0.7).timeout
	assert(game.stage != "thinking" and game.guesses.size() == 1)
	game._restart_run()
	assert(game.level_index == 0 and game.guesses.is_empty() and game.refresh_count == 2)
	print("Integrated daily variants, AI toggle, offline hint, and restart passed")
	await create_timer(1.1).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	quit()
