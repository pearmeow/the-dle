extends Control

const JevLogic = preload("res://scripts/jev_logic.gd")
const LevelBuilder = preload("res://scripts/level_builder.gd")

const BG := Color("#f5efdf")
const PANEL := Color("#faf5e9")
const PANEL_LIGHT := Color("#eee4d0")
const BORDER := Color("#c8bba3")
const TEXT := Color("#28251f")
const MUTED := Color("#736b5d")
const LIME := Color("#747d42")
const BLUE := Color("#6c8580")
const CORAL := Color("#d96e58")

const SAVE_PATH := "user://daily_save.json"
const CURATED_PATH := "res://data/levels.json"
const GENERATED_PATH := "res://data/generated_levels.json"
const BUNDLED_POOL := "res://data/daily_pool.json"
const POOL_CACHE := "user://daily_pool.json"
const POOL_URL := "https://raw.githubusercontent.com/pearmeow/the-dle/naxin/data/daily_pool.json"
const MAX_REFRESHES := 2
const WORD_LIMITS := [18, 16, 14, 12, 11, 9, 8]
const ATTEMPT_LIMITS := [5, 5, 4, 4, 4, 3, 3]
const MONTHS := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

var playtest_mode := false
var catalog: Dictionary = {}
var levels: Array = []
var day_key := ""
var board_id := ""
var pack_index := 0
var level_index := 0
var stage := "select"
var target_id := ""
var hints: Array = []
var guesses: Array = []
var results: Array = []
var elapsed := 0.0
var streak := 0
var last_completed_day := ""
var message := ""
var hint_draft := ""
var jev_url := ""
var used_remote := false
var remote_failed := false
var compact_layout := false
var tiny_layout := false
var data_source := "CURATED"
var autosave_clock := 0.0
var pool_games: Dictionary = {}
var refresh_count := 0

var heading_font: Font = preload("res://assets/Bitter-Bold.ttf")
var body_font: Font = preload("res://assets/Lato-Regular.ttf")
var http: HTTPRequest
var pool_http: HTTPRequest
var timer_label: Label
var count_label: Label
var hint_edit: LineEdit


func _ready() -> void:
	playtest_mode = OS.get_cmdline_user_args().has("--playtest")
	if playtest_mode:
		get_window().title = "Guess What I Mean! · Playtest"
	jev_url = OS.get_environment("JEV_API_URL").strip_edges()
	http = HTTPRequest.new()
	http.timeout = 9.0
	http.request_completed.connect(_on_http_completed)
	add_child(http)
	_load_game_data()
	if not playtest_mode:
		_load_daily_progress()
	compact_layout = size.x < 1100.0
	tiny_layout = size.x < 600.0
	resized.connect(_on_resized)
	_render()
	_fetch_latest_pool()


func _process(delta: float) -> void:
	if stage == "hint" and get_window().has_focus():
		elapsed += delta
		autosave_clock += delta
		if is_instance_valid(timer_label):
			timer_label.text = _format_time(elapsed)
		if autosave_clock >= 5.0:
			autosave_clock = 0.0
			_save_progress()


func _on_resized() -> void:
	var now_compact := size.x < 1100.0
	var now_tiny := size.x < 600.0
	if now_compact != compact_layout or now_tiny != tiny_layout:
		compact_layout = now_compact
		tiny_layout = now_tiny
		call_deferred("_render")


func _load_game_data() -> void:
	var date := Time.get_date_dict_from_system()
	day_key = "%04d-%02d-%02d" % [date.year, date.month, date.day]
	# Preference order: freshly cached RAWG pool -> pool shipped with
	# the build (if CI committed one at export time) -> legacy
	# generated_levels.json -> hard-coded curated board.
	if _try_load_pool_board(POOL_CACHE):
		return
	if _try_load_pool_board(BUNDLED_POOL):
		return
	if _try_load_legacy_generated():
		return
	_load_curated_board()


func _try_load_pool_board(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var data = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if String(data.get("generated_for", "")) != day_key:
		return false
	var games_dict: Dictionary = data.get("games", {})
	if games_dict.is_empty():
		return false
	var pack := LevelBuilder.build_pack(games_dict, day_key + "#" + str(refresh_count))
	if pack.is_empty():
		return false
	pool_games = games_dict
	catalog = games_dict
	levels = pack
	pack_index = 0
	data_source = "RAWG"
	board_id = "pool:" + day_key + ":v" + str(refresh_count)
	return true


func _try_load_legacy_generated() -> bool:
	if not FileAccess.file_exists(GENERATED_PATH):
		return false
	var file := FileAccess.open(GENERATED_PATH, FileAccess.READ)
	if file == null:
		return false
	var data = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if data.get("generated_for", "") != day_key:
		return false
	if not data.has("games") or not data.has("packs"):
		return false
	catalog = data["games"]
	data_source = String(data.get("source", "CURATED"))
	pack_index = posmod(_day_number(day_key), data["packs"].size())
	levels = data["packs"][pack_index]
	board_id = str(JSON.stringify(data).hash()) + ":" + str(pack_index)
	return true


func _load_curated_board() -> void:
	var file := FileAccess.open(CURATED_PATH, FileAccess.READ)
	if file == null:
		push_error("Cannot open level catalog: " + CURATED_PATH)
		return
	var data = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or not data.has("games") or not data.has("packs"):
		push_error("Invalid level catalog: " + CURATED_PATH)
		return
	catalog = data["games"]
	data_source = String(data.get("source", "CURATED"))
	pack_index = posmod(_day_number(day_key), data["packs"].size())
	levels = data["packs"][pack_index]
	board_id = str(JSON.stringify(data).hash()) + ":" + str(pack_index)


func _fetch_latest_pool() -> void:
	if pool_http != null and is_instance_valid(pool_http):
		return
	pool_http = HTTPRequest.new()
	pool_http.timeout = 8.0
	pool_http.request_completed.connect(_on_pool_fetched)
	add_child(pool_http)
	var err := pool_http.request(POOL_URL)
	if err != OK:
		pool_http.queue_free()
		pool_http = null


func _on_pool_fetched(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if pool_http != null and is_instance_valid(pool_http):
		pool_http.queue_free()
	pool_http = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var text := body.get_string_from_utf8()
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return
	if String(data.get("generated_for", "")) != day_key:
		return
	var cache := FileAccess.open(POOL_CACHE, FileAccess.WRITE)
	if cache != null:
		cache.store_string(text)
	# Only replace the board if the player has not committed to the
	# current run yet; otherwise leave today's game in progress alone.
	if not _can_rebuild_board():
		return
	var games_dict: Dictionary = data.get("games", {})
	if games_dict.is_empty():
		return
	var pack := LevelBuilder.build_pack(games_dict, day_key + "#" + str(refresh_count))
	if pack.is_empty():
		return
	pool_games = games_dict
	catalog = games_dict
	levels = pack
	data_source = "RAWG"
	board_id = "pool:" + day_key + ":v" + str(refresh_count)
	_save_progress()
	_render()


func _can_rebuild_board() -> bool:
	return stage == "select" \
		and level_index == 0 \
		and results.is_empty() \
		and target_id.is_empty() \
		and hints.is_empty()


func _can_refresh() -> bool:
	return data_source == "RAWG" \
		and refresh_count < MAX_REFRESHES \
		and not pool_games.is_empty() \
		and _can_rebuild_board()


func _refresh_board() -> void:
	if not _can_refresh():
		return
	refresh_count += 1
	var pack := LevelBuilder.build_pack(pool_games, day_key + "#" + str(refresh_count))
	if pack.is_empty():
		refresh_count -= 1
		return
	levels = pack
	board_id = "pool:" + day_key + ":v" + str(refresh_count)
	message = ""
	_save_progress()
	_render()


func _load_daily_progress() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var saved = JSON.parse_string(file.get_as_text())
	if typeof(saved) != TYPE_DICTIONARY:
		return
	streak = int(saved.get("streak", 0))
	last_completed_day = String(saved.get("last_completed_day", ""))
	if saved.get("day", "") != day_key or saved.get("board_id", "") != board_id:
		return
	level_index = clampi(int(saved.get("level_index", 0)), 0, max(0, levels.size() - 1))
	stage = String(saved.get("stage", "select"))
	if stage == "thinking":
		stage = "hint"
	target_id = String(saved.get("target_id", ""))
	hints = saved.get("hints", [])
	if String(saved.get("stage", "")) == "thinking" and not hints.is_empty():
		hint_draft = String(hints.pop_back())
	guesses = saved.get("guesses", [])
	results = saved.get("results", [])
	elapsed = float(saved.get("elapsed", 0.0))
	refresh_count = clampi(int(saved.get("refresh_count", 0)), 0, MAX_REFRESHES)
	# Rebuild today's board with the saved variant so the player sees
	# the same shuffle they committed to before quitting.
	if data_source == "RAWG" and refresh_count > 0 and not pool_games.is_empty():
		var variant_pack := LevelBuilder.build_pack(pool_games, day_key + "#" + str(refresh_count))
		if not variant_pack.is_empty():
			levels = variant_pack
			board_id = "pool:" + day_key + ":v" + str(refresh_count)
	if stage == "hint" and not _current_ids().has(target_id):
		stage = "select"
		target_id = ""
		hints.clear()
		guesses.clear()


func _save_progress() -> void:
	if playtest_mode:
		return
	var record := {
		"day": day_key,
		"board_id": board_id,
		"pack": pack_index,
		"level_index": level_index,
		"stage": stage,
		"target_id": target_id,
		"hints": hints,
		"guesses": guesses,
		"results": results,
		"elapsed": elapsed,
		"streak": streak,
		"last_completed_day": last_completed_day,
		"refresh_count": refresh_count
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(record))


func _day_number(date_string: String) -> int:
	return int(Time.get_unix_time_from_datetime_string(date_string + "T00:00:00") / 86400.0)


func _current_level() -> Dictionary:
	if levels.is_empty():
		return {}
	return levels[level_index]


func _current_ids() -> Array:
	return _current_level().get("games", [])


func _candidates() -> Array:
	var ids: Array = _current_ids().duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(hash(day_key + ":" + str(level_index)))
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var hold = ids[i]
		ids[i] = ids[j]
		ids[j] = hold
	var items := []
	for id in ids:
		if catalog.has(id):
			var item: Dictionary = catalog[id].duplicate(true)
			item["id"] = id
			items.append(item)
	return items


func _game_name(id: String) -> String:
	return String(catalog.get(id, {}).get("name", "Unknown game"))


func _choose_target(id: String) -> void:
	if stage != "select" or not _current_ids().has(id):
		return
	target_id = id
	hints.clear()
	guesses.clear()
	elapsed = 0.0
	message = ""
	stage = "hint"
	_save_progress()
	_render()


func _on_hint_changed(value: String) -> void:
	hint_draft = value
	if is_instance_valid(count_label):
		var words := JevLogic.word_count(value)
		count_label.text = "%d / %d words" % [words, WORD_LIMITS[level_index]]
		count_label.add_theme_color_override("font_color", CORAL if words > WORD_LIMITS[level_index] else MUTED)


func _submit_hint() -> void:
	if stage != "hint" or not is_instance_valid(hint_edit):
		return
	var value := hint_edit.text.strip_edges()
	var words := JevLogic.word_count(value)
	if words == 0:
		_show_message("Give Jev at least one word to work with.")
		return
	if words > WORD_LIMITS[level_index]:
		_show_message("This level allows %d words per hint." % WORD_LIMITS[level_index])
		return
	if JevLogic.reveals_title(value, _game_name(target_id)):
		_show_message("Keep the title out of your hint. Describe the game instead.")
		return
	if JevLogic.reveals_shortcut(value):
		_show_message("Describe the game, not its place in the list.")
		return
	hint_draft = ""
	message = ""
	hints.append(value)
	stage = "thinking"
	_save_progress()
	_render()
	var previous := []
	for guess in guesses:
		previous.append(guess.get("id", ""))
	if jev_url.is_empty():
		get_tree().create_timer(0.48).timeout.connect(_resolve_local_guess)
		return
	var payload := {"candidates": _candidates(), "hints": hints, "previous_guesses": previous, "level": level_index + 1}
	var error := http.request(jev_url, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		remote_failed = true
		get_tree().create_timer(0.48).timeout.connect(_resolve_local_guess)


func _show_message(value: String) -> void:
	message = value
	_render()
	call_deferred("_focus_current_hint")


func _on_http_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if stage != "thinking":
		return
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var parsed = JSON.parse_string(body.get_string_from_utf8())
		if typeof(parsed) == TYPE_DICTIONARY:
			var id := String(parsed.get("guess_id", ""))
			var previous := []
			for guess in guesses:
				previous.append(guess.get("id", ""))
			if _current_ids().has(id) and not previous.has(id):
				used_remote = true
				remote_failed = false
				_resolve_guess(id, String(parsed.get("reason", "Jev has a hunch.")))
				return
	remote_failed = true
	_resolve_local_guess()


func _resolve_local_guess() -> void:
	if stage != "thinking":
		return
	var previous := []
	for guess in guesses:
		previous.append(guess.get("id", ""))
	var response := JevLogic.guess(_candidates(), hints, previous)
	_resolve_guess(String(response.get("id", "")), String(response.get("reason", "Jev has a hunch.")))


func _resolve_guess(id: String, reason: String) -> void:
	if stage != "thinking" or not _current_ids().has(id):
		return
	var correct := id == target_id
	guesses.append({"id": id, "hint": hints.back(), "reason": reason, "correct": correct})
	if correct:
		_finish_level(true)
	elif guesses.size() >= ATTEMPT_LIMITS[level_index]:
		_finish_level(false)
	else:
		stage = "hint"
	_save_progress()
	_render()


func _finish_level(won: bool) -> void:
	stage = "won" if won else "lost"
	var total_words := 0
	for hint in hints:
		total_words += JevLogic.word_count(String(hint))
	var score := 0
	if won:
		score = maxi(100, int(round(1000.0 - (guesses.size() - 1) * 220.0 - total_words * 2.0 - minf(elapsed, 150.0))))
	results.append({"score": score, "won": won, "attempts": guesses.size(), "words": total_words, "seconds": elapsed, "target": target_id})


func _next_level() -> void:
	if stage != "won" and stage != "lost":
		return
	if level_index + 1 >= levels.size():
		stage = "complete"
		if last_completed_day != day_key:
			streak = streak + 1 if not last_completed_day.is_empty() and _day_number(day_key) - _day_number(last_completed_day) == 1 else 1
			last_completed_day = day_key
	else:
		level_index += 1
		stage = "select"
		target_id = ""
		hints.clear()
		guesses.clear()
		elapsed = 0.0
		message = ""
	_save_progress()
	_render()


func _total_score() -> int:
	var sum := 0
	for result in results:
		sum += int(result.get("score", 0))
	return sum


func _format_time(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds / 60.0), int(seconds) % 60]


func _render() -> void:
	for child in get_children():
		if child != http and child != pool_http:
			remove_child(child)
			child.queue_free()
	timer_label = null
	count_label = null
	hint_edit = null
	var background := ColorRect.new()
	background.color = BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var paper := TextureRect.new()
	paper.texture = preload("res://assets/paper.svg")
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.stretch_mode = TextureRect.STRETCH_TILE
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(paper)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16 if tiny_layout else 26)
	margin.add_theme_constant_override("margin_right", 16 if tiny_layout else 26)
	margin.add_theme_constant_override("margin_top", 12 if tiny_layout else 20)
	margin.add_theme_constant_override("margin_bottom", 12 if tiny_layout else 18)
	add_child(margin)
	var page := _vbox(margin, 16)
	_build_header(page)
	var body: BoxContainer
	if compact_layout:
		var scroller := ScrollContainer.new()
		scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		page.add_child(scroller)
		body = _vbox(scroller, 16)
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		body = _hbox(page, 16)
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_main(body)
	_build_jev(body)
	var footer := _hbox(page, 8)
	footer.add_child(_label("Level %d of 7  ·  %s" % [level_index + 1, _current_level().get("theme", "Today’s mystery")], 13, MUTED))
	_spacer(footer, true)
	if data_source == "RAWG":
		var attribution := _button("GAME DATA: RAWG ↗", false)
		attribution.custom_minimum_size.y = 25
		attribution.pressed.connect(func() -> void: OS.shell_open("https://rawg.io"))
		footer.add_child(attribution)
	footer.add_child(_label("★  Score %s" % _total_score(), 17, TEXT, true))


func _build_header(parent: BoxContainer) -> void:
	var row := _hbox(parent, 20)
	row.custom_minimum_size.y = 54
	row.add_child(_label("Guess What I Mean!", 22 if tiny_layout else 27, TEXT, true))
	_spacer(row, true)
	if not tiny_layout:
		var date := Time.get_date_dict_from_system()
		row.add_child(_label("%s %d" % [MONTHS[date.month - 1].capitalize(), date.day], 14, MUTED))
	var help := _button("?", false)
	help.tooltip_text = "How to play"
	help.pressed.connect(_show_help)
	row.add_child(help)
	var steps := _hbox(parent, 8 if tiny_layout else 14)
	for i in range(levels.size()):
		var marker := _panel(steps, LIME if i < results.size() else (CORAL if i == level_index else PANEL), BORDER, 24, 6)
		marker.custom_minimum_size = Vector2(32, 32)
		var number := _label("✓" if i < results.size() else str(i + 1), 13, PANEL if i < results.size() else TEXT)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		marker.add_child(number)
		if i < levels.size() - 1:
			var line := HSeparator.new()
			line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			steps.add_child(line)

func _show_help() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "How to play"
	dialog.dialog_text = "Pick a secret game. Jev sees the options, but never your choice.\n\nWrite a distinctive clue without using the title or list position.\nAfter each guess, try a new detail if Jev misses.\n\nFewer clues, fewer words, and less active time earn more points.\nSeven levels make up today's run."
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(520, 300))


func _build_sidebar(parent: BoxContainer) -> void:
	var panel := _panel(parent, PANEL, BORDER, 16, 18)
	panel.custom_minimum_size.x = 198
	var box := _vbox(panel, 12)
	box.add_child(_label("THE SEVEN", 11, LIME, true))
	box.add_child(_label("Today's levels", 19, TEXT, true))
	_gap(box, 5)
	for i in range(levels.size()):
		var done := i < results.size()
		var active := i == level_index and stage != "complete"
		var row := _hbox(box, 10)
		var bullet := _label("✓" if done else ("◆" if active else "%02d" % [i + 1]), 14, LIME if done or active else MUTED, true)
		bullet.custom_minimum_size.x = 27
		row.add_child(bullet)
		var label_color := TEXT if active or done else MUTED
		var title := String(levels[i].get("theme", "Level"))
		if title.length() > 17:
			title = title.substr(0, 16) + "…"
		row.add_child(_label(title, 13, label_color, active))
		if done:
			box.add_child(_label("      %d PTS" % int(results[i].get("score", 0)), 10, MUTED))
		_gap(box, 2)
	_spacer(box, false)
	var rule := ColorRect.new()
	rule.color = BORDER
	rule.custom_minimum_size.y = 1
	box.add_child(rule)
	box.add_child(_label("RUN SCORE", 10, MUTED, true))
	box.add_child(_label(str(_total_score()), 27, LIME, true))
	box.add_child(_label("%d day streak" % streak, 12, MUTED))


func _build_main(parent: BoxContainer) -> void:
	var box := _vbox(parent, 12)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if compact_layout:
		box.custom_minimum_size.y = 650
	if levels.is_empty():
		box.add_child(_label("Level data could not be loaded.", 22, CORAL))
		return
	match stage:
		"select": _build_select(box)
		"hint", "thinking": _build_hint(box)
		"won", "lost": _build_result(box)
		"complete": _build_complete(box)


func _build_select(box: BoxContainer) -> void:
	box.add_child(_label("Pick your secret.", 34 if tiny_layout else 48, TEXT, true))
	box.add_child(_paragraph("%s games. One hidden answer. Make Jev guess yours." % _current_ids().size(), 17, MUTED))
	_build_cards(box, true)
	var note := _panel(box, PANEL, BORDER, 4, 18)
	var note_box := _vbox(note, 8)
	note_box.add_child(_label("What would give it away?", 23, TEXT, true))
	note_box.add_child(_paragraph("Choose a card above, then describe a distinctive feature.", 15, MUTED))
	note_box.add_child(_paragraph("Keep the title secret. You have %d guesses and %d words per clue." % [ATTEMPT_LIMITS[level_index], WORD_LIMITS[level_index]], 13, MUTED))
	if _can_refresh():
		var refresh := _button("Reshuffle board · %d left" % (MAX_REFRESHES - refresh_count), false)
		refresh.pressed.connect(_refresh_board)
		box.add_child(refresh)

func _cover_index(game: Dictionary) -> int:
	var words := (String(game.get("name", "")) + " " + String(game.get("genre", ""))).to_lower()
	for feature in game.get("features", []):
		if not "steam" in String(feature).to_lower():
			words += " " + String(feature).to_lower()
	if "horror" in words or "evil" in words or "dark souls" in words:
		return 0
	if "war" in words or "racing" in words or "shooter" in words or "fps" in words:
		return 1
	if "space" in words or "alien" in words or "outer" in words or "sci-fi" in words:
		return 3
	if "puzzle" in words or "deckbuilding" in words or "tetris" in words:
		return 5
	if "rpg" in words or "fantasy" in words or "knight" in words:
		return 2
	return 4

func _card_caption(game: Dictionary) -> String:
	var blurb := String(game.get("blurb", ""))
	if not blurb.is_empty() and not blurb.begins_with("Gameplay tags:"):
		return blurb
	var useful: Array = []
	for feature in game.get("features", []):
		var word := String(feature).replace("-", " ")
		if "steam" in word.to_lower() or "controller" in word.to_lower() or "workshop" in word.to_lower() or "leaderboard" in word.to_lower():
			continue
		useful.append(word.capitalize())
		if useful.size() == 2:
			break
	return String(game.get("genre", "Video game")) + (" · " + " / ".join(useful) if not useful.is_empty() else "")

func _build_cards(box: BoxContainer, selectable: bool) -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 330 if selectable else 240
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var row := _hbox(scroll, 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var candidates := _candidates()
	var width := clampf((size.x - (70 if compact_layout else 340) - (candidates.size() - 1) * 12) / max(1, candidates.size()), 156, 250)
	for i in range(candidates.size()):
		var game: Dictionary = candidates[i]
		var selected := String(game["id"]) == target_id
		var card := _panel(row, PANEL, CORAL if selected else BORDER, 5, 7)
		card.custom_minimum_size.x = width
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if selected:
			card.add_theme_stylebox_override("panel", _style(PANEL, CORAL, 5, 3, 7))
		var content := _vbox(card, 6)
		var artwork := TextureRect.new()
		var atlas := AtlasTexture.new()
		var sheet: Texture2D = preload("res://assets/covers.png")
		atlas.atlas = sheet
		var tile := sheet.get_size() / Vector2(3, 2)
		var index := _cover_index(game)
		atlas.region = Rect2(Vector2(index % 3, floori(index / 3.0)) * tile, tile)
		artwork.texture = atlas
		artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		artwork.custom_minimum_size = Vector2(width - 14, 180 if selectable else 110)
		artwork.size_flags_vertical = Control.SIZE_EXPAND_FILL
		artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(artwork)
		var title := _paragraph(String(game["name"]), 15, TEXT)
		title.add_theme_font_override("font", heading_font)
		title.custom_minimum_size.x = width - 14
		title.max_lines_visible = 2
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		content.add_child(title)
		var caption := _paragraph(_card_caption(game), 12, MUTED)
		caption.max_lines_visible = 3 if selectable else 2
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		content.add_child(caption)
		if selected:
			content.add_child(_label("YOUR SECRET", 11, CORAL, true))
		if selectable:
			var choose := _button("%02d   Choose this game" % [i + 1], false)
			choose.add_theme_font_size_override("font_size", 12)
			choose.pressed.connect(_choose_target.bind(String(game["id"])))
			content.add_child(choose)
			card.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					_choose_target(String(game["id"]))
			)
			for child in content.get_children():
				if not child is Button:
					child.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			card.tooltip_text = "Keep " + String(game["name"]) + " secret from Jev"


func _build_hint(box: BoxContainer) -> void:
	box.add_child(_label("What would give it away?", 29 if tiny_layout else 40, TEXT, true))
	box.add_child(_paragraph("Your secret is %s. Help Jev find it." % _game_name(target_id), 16, MUTED))
	_build_cards(box, false)
	var composer := _panel(box, PANEL, BORDER, 5, 18)
	var compose := _vbox(composer, 9)
	compose.add_child(_label("Jev is following your clues…" if stage == "thinking" else "A little detail. A big revelation.", 23, TEXT, true))
	if stage != "thinking":
		hint_edit = LineEdit.new()
		hint_edit.placeholder_text = "Describe a distinctive feature…"
		hint_edit.text = hint_draft
		hint_edit.custom_minimum_size.y = 52
		hint_edit.add_theme_font_override("font", body_font)
		hint_edit.add_theme_font_size_override("font_size", 17)
		hint_edit.add_theme_color_override("font_color", TEXT)
		hint_edit.add_theme_color_override("font_placeholder_color", MUTED)
		hint_edit.add_theme_stylebox_override("normal", _style(Color("#fffdf7"), BORDER, 6, 1, 12))
		hint_edit.add_theme_stylebox_override("focus", _style(Color("#fffdf7"), CORAL, 6, 2, 12))
		hint_edit.text_changed.connect(_on_hint_changed)
		hint_edit.text_submitted.connect(func(_value: String) -> void: _submit_hint())
		compose.add_child(hint_edit)
	var bottom := _hbox(compose, 12)
	count_label = _label("%d / %d words" % [JevLogic.word_count(hint_draft), WORD_LIMITS[level_index]], 13, MUTED)
	bottom.add_child(count_label)
	_spacer(bottom, true)
	if stage != "thinking":
		var submit := _button("Send clue →", true)
		submit.pressed.connect(_submit_hint)
		bottom.add_child(submit)
	var stats := _hbox(compose, 12)
	stats.add_child(_label("Keep the title secret. %d guesses left." % (ATTEMPT_LIMITS[level_index] - guesses.size()), 13, MUTED))
	_spacer(stats, true)
	timer_label = _label(_format_time(elapsed), 13, MUTED)
	stats.add_child(timer_label)
	if not message.is_empty():
		compose.add_child(_paragraph(message, 13, CORAL))
	if stage == "hint":
		call_deferred("_focus_current_hint")


func _focus_current_hint() -> void:
	if is_instance_valid(hint_edit) and hint_edit.is_inside_tree():
		hint_edit.grab_focus()


func _build_result(box: BoxContainer) -> void:
	var won := stage == "won"
	var result: Dictionary = results.back()
	box.add_child(_label("LEVEL %02d / 07   •   %s" % [level_index + 1, "SOLVED" if won else "OUT OF GUESSES"], 12, LIME if won else CORAL, true))
	_gap(box, 35)
	box.add_child(_paragraph("Jev got it!" if won else "Jev missed this one.", 29 if tiny_layout else 39, TEXT))
	box.add_child(_label("Your game was %s." % _game_name(target_id), 19, MUTED))
	_gap(box, 15)
	var score_panel := _panel(box, LIME if won else PANEL_LIGHT, LIME if won else BORDER, 16, 24)
	var score_box := _vbox(score_panel, 4)
	score_box.add_child(_label("LEVEL SCORE", 11, BG if won else MUTED, true))
	score_box.add_child(_label(str(result.get("score", 0)), 58, BG if won else TEXT, true))
	score_box.add_child(_paragraph("Fewer hints, fewer words, and less active time earn more points." if won else "A missed level earns 0 points. The run continues.", 13, BG if won else MUTED))
	var next := _button("SEE TODAY'S RESULTS  →" if level_index + 1 == levels.size() else "NEXT LEVEL  →", true)
	next.custom_minimum_size.y = 52
	next.pressed.connect(_next_level)
	if compact_layout:
		box.add_child(next)
	var metrics: BoxContainer = _vbox(box, 10) if tiny_layout else _hbox(box, 10)
	metrics.add_child(_metric("HINTS", str(result.get("attempts", 0))))
	metrics.add_child(_metric("WORDS", str(result.get("words", 0))))
	metrics.add_child(_metric("ACTIVE TIME", _format_time(float(result.get("seconds", 0.0)))))
	if not compact_layout:
		_spacer(box, false)
		box.add_child(next)


func _build_complete(box: BoxContainer) -> void:
	box.add_child(_label("DAILY RUN COMPLETE", 12, LIME, true))
	box.add_child(_label("That's a wrap.", 30 if tiny_layout else 38, TEXT, true))
	box.add_child(_paragraph("Seven levels, one conversation at a time. Come back tomorrow for the next board.", 16, MUTED))
	var total := _panel(box, LIME, LIME, 15, 24)
	var total_box := _vbox(total, 2)
	total_box.add_child(_label("TODAY'S TOTAL", 11, BG, true))
	total_box.add_child(_label(str(_total_score()), 52, BG, true))
	total_box.add_child(_label("%d day streak" % streak, 14, BG))
	_gap(box, 9)
	for i in range(results.size()):
		var result: Dictionary = results[i]
		var row := _panel(box, PANEL_LIGHT, BORDER, 8, 10)
		var content := _hbox(row, 9)
		content.add_child(_label("%02d" % [i + 1], 12, LIME, true))
		content.add_child(_label(String(levels[i].get("theme", "Level")), 13, TEXT))
		_spacer(content, true)
		content.add_child(_label("%d PTS" % int(result.get("score", 0)), 13, LIME if result.get("won", false) else CORAL, true))
	box.add_child(_label("Progress is saved locally for this date.", 12, MUTED))


func _build_jev(parent: BoxContainer) -> void:
	var box := _vbox(parent, 10)
	box.custom_minimum_size.x = 235 if not compact_layout else 0
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bubble := _panel(box, PANEL, BORDER, 22, 17)
	var speech := "A secret?\nI'm listening."
	if stage == "thinking":
		speech = "Hmm… let me follow that clue."
	elif stage == "won":
		speech = "Aha! Case closed."
	elif stage == "lost":
		speech = "You stumped me! Another case?"
	elif not guesses.is_empty():
		speech = "My hunch: %s?" % _game_name(String(guesses.back().get("id", "")))
	elif stage == "hint":
		speech = "What's your first clue?"
	bubble.add_child(_paragraph(speech, 21, TEXT))
	var portrait := TextureRect.new()
	var jev_art := AtlasTexture.new()
	jev_art.atlas = preload("res://assets/jev.png")
	jev_art.region = Rect2(0, 220, 1024, 1120)
	portrait.texture = jev_art
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size.y = 220 if compact_layout else 290
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(portrait)
	box.add_child(_label("Jev · your guessing detective", 13, TEXT, true))
	var mode := "Offline clue matcher" if jev_url.is_empty() else ("Offline fallback" if remote_failed else "AI guessing partner")
	box.add_child(_label(mode, 11, MUTED))
	if not guesses.is_empty():
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size.y = 160
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		box.add_child(scroll)
		var log := _vbox(scroll, 8)
		log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for i in range(guesses.size()):
			var guess: Dictionary = guesses[i]
			log.add_child(_paragraph("%d. %s%s" % [i + 1, _game_name(String(guess.get("id", ""))), " ✓" if guess.get("correct", false) else " · missed"], 14, LIME if guess.get("correct", false) else TEXT))
			if level_index <= 2:
				log.add_child(_paragraph(String(guess.get("reason", "")), 12, MUTED))
	else:
		box.add_child(_paragraph("I see the games and your clues. Your choice stays with you.", 13, MUTED))


func _add_step(parent: BoxContainer, number: String, heading: String, detail: String) -> void:
	var row := _hbox(parent, 9)
	row.add_child(_label(number, 12, LIME, true))
	var text_box := _vbox(row, 3)
	text_box.add_child(_label(heading, 15, TEXT, true))
	text_box.add_child(_label(detail, 12, MUTED))


func _metric(title: String, value: String) -> PanelContainer:
	var panel := _panel(null, PANEL_LIGHT, BORDER, 10, 15)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := _vbox(panel, 4)
	box.add_child(_label(title, 10, MUTED, true))
	box.add_child(_label(value, 21, TEXT, true))
	return panel


func _chip(value: String, color: Color) -> PanelContainer:
	var chip := _panel(null, PANEL_LIGHT, BORDER, 8, 8)
	chip.add_child(_label(value, 10, color, true))
	return chip


func _style(fill: Color, line: Color, radius: int, width: int, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = line
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style


func _panel(parent: Node, fill: Color, line: Color, radius: int, padding: int) -> PanelContainer:
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", _style(fill, line, radius, 1, padding))
	if parent != null:
		parent.add_child(node)
	return node


func _button(value: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 42
	button.add_theme_font_override("font", body_font)
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", PANEL if primary else TEXT)
	button.add_theme_color_override("font_hover_color", PANEL if primary else CORAL)
	button.add_theme_color_override("font_pressed_color", PANEL)
	button.add_theme_stylebox_override("normal", _style(CORAL if primary else PANEL, CORAL if primary else BORDER, 6, 1, 12))
	button.add_theme_stylebox_override("hover", _style(Color("#c65e49") if primary else Color("#eee1ca"), CORAL, 6, 2, 12))
	button.add_theme_stylebox_override("pressed", _style(CORAL, CORAL, 6, 2, 12))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, CORAL, 6, 2, 12))
	return button


func _label(value: String, font_size: int, color: Color, bold: bool = false) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_override("font", heading_font if bold or font_size >= 28 else body_font)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _paragraph(value: String, font_size: int, color: Color) -> Label:
	var label := _label(value, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 120
	return label


func _vbox(parent: Node, separation: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	parent.add_child(box)
	return box


func _hbox(parent: Node, separation: int) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	parent.add_child(box)
	return box


func _gap(parent: BoxContainer, height: float) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = height
	parent.add_child(gap)


func _spacer(parent: BoxContainer, horizontal: bool) -> void:
	var gap := Control.new()
	if horizontal:
		gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(gap)
