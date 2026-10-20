extends SceneTree

class LibraryGame extends "res://scripts/main.gd":
	func _load_game_data() -> void:
		day_key = JSON.parse_string(FileAccess.get_file_as_string(BUNDLED_POOL))["generated_for"]
		assert(_try_load_pool_board(BUNDLED_POOL))
	func _load_daily_progress() -> void:
		pass
	func _save_progress() -> void:
		pass
	func _fetch_latest_pool() -> void:
		pass

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game := LibraryGame.new()
	game.size = Vector2(1440, 900)
	root.add_child(game)
	assert(game.game_library.size() >= game.catalog.size(), "Every bundled daily game needs library coverage.")
	for id in game.catalog:
		var detail := game._game_details(String(id))
		assert(not String(detail.get("blurb", "")).begins_with("Gameplay tags:"))
		assert(String(detail.get("blurb", "")).length() > 40)
		assert(String(detail.get("blurb", "")).length() <= 250, "Remote Jev must receive the complete overview.")
		assert(String(detail.get("source", "")).begins_with("https://rawg.io/games/"))
		var art := game._card_art(detail, 220, 180)
		assert(art is TextureRect and art.texture != null, "Every daily game must display matching artwork.")
		art.free()
	for variant in game.pool_variants:
		game.levels = variant
		for index in range(7):
			game.level_index = index
			for candidate in game._candidates():
				assert(candidate["blurb"] == game._game_details(candidate["id"])["blurb"], "Jev and player need identical overviews.")
	game.level_index = 1
	game._start_game()
	game._show_game_intro(String(game._current_ids()[0]))
	assert(game.has_node("GameIntro"))
	print("All bundled daily games have matching artwork, readable overviews, attribution, and equal Jev information.")
	await create_timer(1.1).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	quit()
