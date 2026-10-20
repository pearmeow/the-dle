extends SceneTree
class SoundGame extends "res://scripts/main.gd":
	var cues: Array[String] = []
	func _load_game_data() -> void:
		day_key = "2026-10-19"
		_load_curated_board()
	func _load_daily_progress() -> void:
		pass
	func _save_progress() -> void:
		pass
	func _fetch_latest_pool() -> void:
		pass
	func _save_audio_settings() -> void:
		pass
	func _play_sfx(kind: String) -> void:
		cues.append(kind)
		super._play_sfx(kind)
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var game := SoundGame.new()
	game.size = Vector2(1440,900)
	root.add_child(game)
	game.sfx_muted = false
	game.sfx_volume = 0.5
	assert(game.sfx_players.size() == 5)
	for player in game.sfx_players.values():
		assert(player.stream.get_length() > 0.05, "All effects must decode.")
	var click := game._button("Test", false)
	game.add_child(click)
	click.pressed.emit()
	assert(game.cues.back() == "button", "Buttons must produce feedback.")
	click.queue_free()
	game._start_game()
	var audio_root := game.sfx_root
	game._choose_target(game._current_ids()[0])
	game.hints.append("A distinctive feature")
	game.stage = "thinking"
	game._resolve_guess(game._current_ids()[1], "Not quite")
	assert(game.cues.back() == "miss")
	game.hints.append("Another detail")
	game.stage = "thinking"
	game._resolve_guess(game.target_id, "That fits")
	assert(game.cues.back() == "correct")
	game._next_level()
	assert(game.cues.back() == "progress" and game.sfx_root == audio_root)
	game.level_index = 6
	game.stage = "won"
	game._next_level()
	assert(game.cues.back() == "complete")
	game._set_sfx_muted(true)
	game._play_sfx("button")
	for player in game.sfx_players.values():
		assert(not player.playing, "Muted effects must be silent.")
	game._set_sfx_muted(false)
	game._set_sfx_volume(0.0)
	game._play_sfx("correct")
	assert(not game.sfx_players.correct.playing)
	await create_timer(1.1).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("Button, correct, miss, progress, completion, mute, and volume checks passed")
	quit()
