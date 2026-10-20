extends SceneTree
class MusicGame extends "res://scripts/main.gd":
	var saved_audio: Dictionary = {}
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
		saved_audio = {"volume": music_volume, "muted": music_muted}
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var game := MusicGame.new()
	game.size = Vector2(1440,900)
	root.add_child(game)
	var player := game.music_player
	assert(player.stream.get_length() > 190.0 and player.stream.loop, "Track must decode and loop.")
	assert(player.playing, "Music must start.")
	game._start_game()
	game._back_to_main_menu()
	game._restart_run()
	assert(game.music_player == player and is_instance_valid(player), "Navigation must preserve the same audio player.")
	game._set_music_muted(true)
	assert(player.stream_paused and game.saved_audio.muted, "Mute must silence and save.")
	game._set_music_muted(false)
	game._set_music_volume(0.25)
	assert(not player.stream_paused and is_equal_approx(db_to_linear(player.volume_db), 0.25))
	assert(is_equal_approx(game.saved_audio.volume, 0.25), "Volume must be saved.")
	game._set_music_volume(0.0)
	assert(player.stream_paused, "Zero volume must silence.")
	game._set_music_volume(0.18)
	assert(not player.stream_paused, "Raising volume must resume playback.")
	print("Music decode, loop, navigation continuity, mute, volume, and save checks passed")
	game.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	quit()
