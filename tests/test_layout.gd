extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for dimensions in [Vector2(1440, 900), Vector2(1024, 768), Vector2(800, 600), Vector2(480, 800), Vector2(360, 720)]:
		var game = load("res://main.tscn").instantiate()
		root.add_child(game)
		game.set_anchors_preset(Control.PRESET_TOP_LEFT)
		game.size = dimensions
		game.stage = "select"
		game.level_index = 0
		game.results.clear()
		await process_frame
		await process_frame
		_assert_readable(game, dimensions)
		var card := _find_button(game, "01   ")
		assert(card != null and _fits(card.get_global_rect(), dimensions), "A target card is off-screen at %s." % dimensions)
		game._choose_target(game._current_ids()[0])
		await process_frame
		await process_frame
		_assert_hint_controls(game, dimensions)
		game.hints.append("A clear gameplay detail")
		game.stage = "thinking"
		game._resolve_guess(game.target_id, "That fits.")
		await process_frame
		await process_frame
		var next := _find_button(game, "NEXT LEVEL")
		assert(next != null and _fits(next.get_global_rect(), dimensions), "Next level button is off-screen at %s." % dimensions)
		game.stage = "select"
		game.level_index = 6
		game._render()
		await process_frame
		for i in range(game._current_ids().size()):
			var candidate := _find_button(game, "%02d   " % [i + 1])
			assert(candidate != null and candidate.get_global_rect().end.x <= dimensions.x, "A candidate card is clipped horizontally at %s." % dimensions)
		var longest := ""
		for id in game._current_ids():
			if game._game_name(id).length() > game._game_name(longest).length():
				longest = id
		game._choose_target(longest)
		await process_frame
		await process_frame
		_assert_hint_controls(game, dimensions)
		game.queue_free()
		await process_frame
	print("Godot layout tests passed")
	quit(0)


func _assert_hint_controls(game: Node, dimensions: Vector2) -> void:
	_assert_readable(game, dimensions)
	var send := _find_button(game, "SEND HINT")
	assert(game.hint_edit != null and send != null, "Hint input or send button is missing.")
	assert(_fits(game.hint_edit.get_global_rect(), dimensions), "Hint input is off-screen at %s." % dimensions)
	assert(_fits(send.get_global_rect(), dimensions), "Send button is off-screen at %s." % dimensions)


func _assert_readable(node: Node, dimensions: Vector2) -> void:
	if node is Label and node.text.length() > 5:
		assert(node.size.x >= 24.0, "A label collapsed into vertical text at %s: %s" % [dimensions, node.text])
	for child in node.get_children():
		_assert_readable(child, dimensions)


func _find_button(node: Node, start: String) -> Button:
	if node is Button and node.text.begins_with(start):
		return node
	for child in node.get_children():
		var found := _find_button(child, start)
		if found != null:
			return found
	return null


func _fits(rect: Rect2, dimensions: Vector2) -> bool:
	return rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= dimensions.x and rect.end.y <= dimensions.y
