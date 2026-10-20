extends SceneTree

class PoolGame extends "res://scripts/main.gd":
	func _ready() -> void:
		pass
	func _save_progress() -> void:
		pass
	func _render() -> void:
		pass


func _initialize() -> void:
	var game := PoolGame.new()
	var games := {}
	var pack := []
	var offset := 0
	for count in game.LevelBuilder.SIZES:
		var ids := []
		for index in range(count):
			var id := "game_%d" % offset
			games[id] = {"name": id}
			ids.append(id)
			offset += 1
		pack.append({"theme": "Test", "note": "Test", "games": ids})
	var second: Array = pack.duplicate(true)
	second[0]["games"].reverse()
	var variants := [pack, second, pack.duplicate(true)]
	game.day_key = "2026-10-20"
	assert(game._pool_pack(games, variants, 0) == pack, "Use CI's exact board without recomposing it.")
	assert(game._pool_pack(games, variants, 1) == second, "Use the requested CI variant.")
	assert(game._pool_pack(games, variants, 3).is_empty(), "Reject missing variants.")
	var invalid: Array = pack.duplicate(true)
	invalid[1]["games"][0] = invalid[0]["games"][0]
	assert(game._pool_pack(games, [invalid], 0).is_empty(), "Reject repeated candidates across levels.")
	invalid = pack.duplicate(true)
	invalid[0]["games"][0] = "unknown"
	assert(game._pool_pack(games, [invalid], 0).is_empty(), "Reject unknown games.")
	var copy := game._pool_pack(games, variants, 0)
	copy[0]["games"].clear()
	assert(pack[0]["games"].size() == 3, "Client edits must not mutate the published variants.")
	game.pool_games = games
	game.pool_variants = variants
	game.data_source = "RAWG"
	game._refresh_board()
	assert(game.refresh_count == 1 and game.levels == second, "Refresh must load the CI variant.")
	game.jev_url = game.DEFAULT_JEV_URL
	assert(not game.jev_url.is_empty(), "The merged build must retain the web AI endpoint.")
	game.used_remote = true
	game.remote_failed = true
	game._toggle_remote_jev()
	assert(not game.use_remote_jev and not game.used_remote and not game.remote_failed,
		"The AI toggle must retain offline mode and clear stale model status.")
	game._toggle_remote_jev()
	assert(game.use_remote_jev, "The AI toggle must allow the model to be re-enabled.")
	game.free()
	print("Precomputed daily board and refresh checks passed")
	quit(0)
