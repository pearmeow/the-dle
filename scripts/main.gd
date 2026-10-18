extends Control

const JevLogic = preload("res://scripts/jev_logic.gd")

const BG := Color("#09121d")
const PANEL := Color("#111f2e")
const PANEL_LIGHT := Color("#172a3a")
const BORDER := Color("#294051")
const TEXT := Color("#f4f4e8")
const MUTED := Color("#9cafb8")
const LIME := Color("#d9f583")
const BLUE := Color("#88c7f1")
const CORAL := Color("#fa9b82")

const SAVE_PATH := "user://daily_save.json"
const CURATED_PATH := "res://data/levels.json"
const GENERATED_PATH := "res://data/generated_levels.json"
const WORD_LIMITS := [18, 16, 14, 12, 11, 9, 8]
const ATTEMPT_LIMITS := [5, 5, 4, 4, 4, 3, 3]
const MONTHS := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

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

var http: HTTPRequest
var timer_label: Label
var count_label: Label
var hint_edit: LineEdit


func _ready() -> void:
	jev_url = OS.get_environment("JEV_API_URL").strip_edges()
	http = HTTPRequest.new()
	http.timeout = 9.0
	http.request_completed.connect(_on_http_completed)
	add_child(http)
	_load_game_data()
	_load_daily_progress()
	compact_layout = size.x < 1100.0
	tiny_layout = size.x < 600.0
	resized.connect(_on_resized)
	_render()


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
	var source := CURATED_PATH
	if FileAccess.file_exists(GENERATED_PATH):
		var generated_file := FileAccess.open(GENERATED_PATH, FileAccess.READ)
		if generated_file != null:
			var generated = JSON.parse_string(generated_file.get_as_text())
			if typeof(generated) == TYPE_DICTIONARY and generated.get("generated_for", "") == day_key:
				source = GENERATED_PATH
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null:
		push_error("Cannot open level catalog: " + source)
		return
	var data = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or not data.has("games") or not data.has("packs"):
		push_error("Invalid level catalog: " + source)
		return
	catalog = data["games"]
	data_source = String(data.get("source", "CURATED"))
	pack_index = posmod(_day_number(day_key), data["packs"].size())
	levels = data["packs"][pack_index]
	board_id = str(JSON.stringify(data).hash()) + ":" + str(pack_index)


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
	if stage == "hint" and not _current_ids().has(target_id):
		stage = "select"
		target_id = ""
		hints.clear()
		guesses.clear()


func _save_progress() -> void:
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
		"last_completed_day": last_completed_day
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
		if child != http:
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
	if not compact_layout and size.x >= 1100.0:
		_build_sidebar(body)
	_build_main(body)
	_build_jev(body)
	var footer := _hbox(page, 8)
	footer.add_child(_label("GUESS WHAT I MEAN!", 11, MUTED))
	_spacer(footer, true)
	if data_source == "RAWG":
		var attribution := _button("GAME DATA: RAWG ↗", false)
		attribution.custom_minimum_size.y = 25
		attribution.pressed.connect(func() -> void: OS.shell_open("https://rawg.io"))
		footer.add_child(attribution)
	elif not tiny_layout:
		footer.add_child(_label("A DAILY GAME ABOUT SAYING JUST ENOUGH", 11, MUTED))


func _build_header(parent: BoxContainer) -> void:
	var row := _hbox(parent, 10 if tiny_layout else 15)
	row.custom_minimum_size.y = 64
	var logo := _panel(row, LIME, LIME, 10, 0)
	logo.custom_minimum_size = Vector2(50, 50) if tiny_layout else Vector2(60, 60)
	var logo_text := _label("GW\nIM", 17, BG)
	logo_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	logo.add_child(logo_text)
	var title_box := _vbox(row, 0)
	title_box.add_child(_label("GUESS WHAT I MEAN!", 22 if tiny_layout else 28, TEXT, true))
	title_box.add_child(_label("THE DAILY AI GUESSING GAME", 11, MUTED))
	_spacer(row, true)
	if not tiny_layout:
		var date := Time.get_date_dict_from_system()
		var date_panel := _panel(row, PANEL, BORDER, 10, 12)
		var date_box := _vbox(date_panel, 1)
		date_box.add_child(_label("TODAY'S RUN", 10, LIME, true))
		date_box.add_child(_label("%s %02d  ·  %d / 7" % [MONTHS[date.month - 1], date.day, level_index + 1], 15, TEXT, true))


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
	var panel := _panel(parent, PANEL, BORDER, 18, 12 if tiny_layout else (18 if compact_layout else 25))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.x = 450 if not compact_layout else 0
	if compact_layout:
		panel.custom_minimum_size.y = 680
	var box := _vbox(panel, 14)
	if levels.is_empty():
		box.add_child(_label("Level data could not be loaded.", 22, CORAL))
		return
	match stage:
		"select": _build_select(box)
		"hint", "thinking": _build_hint(box)
		"won", "lost": _build_result(box)
		"complete": _build_complete(box)


func _build_select(box: BoxContainer) -> void:
	var level := _current_level()
	box.add_child(_label("LEVEL %02d / 07   •   SELECT YOUR SECRET" % [level_index + 1], 12, LIME, true))
	box.add_child(_paragraph(String(level.get("theme", "Today's challenge")), 28 if tiny_layout else 34, TEXT))
	box.add_child(_paragraph(String(level.get("note", "Choose a game and guide Jev to it.")), 15, MUTED))
	var rules := _hbox(box, 10)
	rules.add_child(_chip("%d CANDIDATES" % _current_ids().size(), BLUE))
	rules.add_child(_chip("%d GUESSES" % ATTEMPT_LIMITS[level_index], LIME))
	rules.add_child(_chip("%d WORDS / HINT" % WORD_LIMITS[level_index], CORAL))
	_gap(box, 5)
	box.add_child(_label("CHOOSE ONE GAME", 11, MUTED, true))
	var scroller := ScrollContainer.new()
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroller)
	var grid := GridContainer.new()
	grid.columns = 1 if compact_layout else 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(grid)
	var candidates := _candidates()
	for i in range(candidates.size()):
		var game: Dictionary = candidates[i]
		var feature := String(game.get("features", ["distinctive gameplay"])[0])
		var title := String(game.get("name", "Game"))
		var caption := String(game.get("genre", "Video game")) + "  ·  " + feature
		if tiny_layout:
			if title.length() > 25:
				title = title.substr(0, 24) + "…"
			caption = String(game.get("genre", "Video game"))
		var button := _button("%02d   %s\n        %s" % [i + 1, title, caption], false)
		button.custom_minimum_size = Vector2(0 if compact_layout else 310, 82 if tiny_layout else 101)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.pressed.connect(_choose_target.bind(String(game["id"])))
		grid.add_child(button)
	box.add_child(_label("Jev gets this list, but your selection stays secret.", 12, MUTED))


func _build_hint(box: BoxContainer) -> void:
	var level := _current_level()
	box.add_child(_label("LEVEL %02d / 07   •   HINT %d OF %d" % [level_index + 1, hints.size() + (0 if stage == "thinking" else 1), ATTEMPT_LIMITS[level_index]], 12, LIME, true))
	box.add_child(_label("Give Jev a clue." if tiny_layout else "Make Jev think of your game.", 26 if tiny_layout else 30, TEXT, true))
	box.add_child(_paragraph(String(level.get("note", "Use what makes it distinctive.")), 14, MUTED))
	var secret := _panel(box, PANEL_LIGHT, LIME, 12, 16)
	var secret_row := _hbox(secret, 12)
	var mark := _label("✦", 22, LIME)
	secret_row.add_child(mark)
	var secret_text := _vbox(secret_row, 2)
	secret_text.add_child(_label("YOUR SECRET GAME", 10, LIME, true))
	var secret_name := _label(_game_name(target_id), 19, TEXT, true)
	secret_name.clip_text = true
	secret_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	secret_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	secret_text.add_child(secret_name)
	_spacer(secret_row, true)
	if not compact_layout:
		secret_row.add_child(_label("ONLY YOU SEE THIS", 10, MUTED, true))
	var stats := _hbox(box, 10)
	stats.add_child(_chip("%d / %d GUESSES" % [guesses.size(), ATTEMPT_LIMITS[level_index]], BLUE))
	stats.add_child(_chip("%d WORD MAX" % WORD_LIMITS[level_index], CORAL))
	timer_label = _label(_format_time(elapsed), 14, TEXT, true)
	stats.add_child(timer_label)
	_gap(box, 3)
	if stage == "thinking":
		var thinking := _panel(box, LIME, LIME, 12, 16)
		thinking.add_child(_label("JEV IS THINKING…", 16, BG, true))
	else:
		var composer := _panel(box, PANEL_LIGHT, BLUE, 12, 16)
		var compose_box := _vbox(composer, 9)
		compose_box.add_child(_label("TYPE HINT %02d  /  BE SPECIFIC. BE BRIEF." % [hints.size() + 1], 12, LIME, true))
		hint_edit = LineEdit.new()
		hint_edit.placeholder_text = "Describe a standout feature" if tiny_layout else "e.g. Build a shelter beneath an alien ocean"
		hint_edit.text = hint_draft
		hint_edit.custom_minimum_size.y = 50
		hint_edit.add_theme_font_size_override("font_size", 17)
		hint_edit.add_theme_color_override("font_color", TEXT)
		hint_edit.add_theme_color_override("font_placeholder_color", MUTED)
		hint_edit.add_theme_stylebox_override("normal", _style(BG, BLUE, 8, 2, 10))
		hint_edit.add_theme_stylebox_override("focus", _style(BG, LIME, 8, 2, 10))
		hint_edit.text_changed.connect(_on_hint_changed)
		hint_edit.text_submitted.connect(func(_value: String) -> void: _submit_hint())
		compose_box.add_child(hint_edit)
		var compose_footer := _hbox(compose_box, 10)
		count_label = _label("%d / %d words" % [JevLogic.word_count(hint_draft), WORD_LIMITS[level_index]], 12, MUTED)
		compose_footer.add_child(count_label)
		_spacer(compose_footer, true)
		var submit := _button("SEND HINT  →", true)
		submit.pressed.connect(_submit_hint)
		compose_footer.add_child(submit)
		if not message.is_empty():
			compose_box.add_child(_label(message, 12, CORAL))
		if hint_draft.is_empty():
			call_deferred("_focus_current_hint")
	box.add_child(_label("JEV'S OPTIONS", 11, MUTED, true))
	var options_scroll := ScrollContainer.new()
	options_scroll.custom_minimum_size.y = 110
	options_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	options_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(options_scroll)
	var options := GridContainer.new()
	options.columns = 1 if compact_layout else 2
	options.add_theme_constant_override("h_separation", 9)
	options.add_theme_constant_override("v_separation", 9)
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_scroll.add_child(options)
	var prior := []
	for guess in guesses:
		prior.append(guess.get("id", ""))
	for game in _candidates():
		var item := _panel(options, PANEL_LIGHT, BORDER, 9, 12)
		item.custom_minimum_size = Vector2(0 if compact_layout else 300, 49)
		var name_color := MUTED if prior.has(game["id"]) else TEXT
		var option_name := _paragraph(String(game["name"]) + ("  ·  GUESSED" if prior.has(game["id"]) else ""), 13, name_color)
		option_name.custom_minimum_size.x = 120
		item.add_child(option_name)
	box.add_child(_label("Describe the game without its title or list position.", 11, MUTED))


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
	var panel := _panel(parent, PANEL, BORDER, 16, 20)
	panel.custom_minimum_size.x = 295 if not compact_layout else 0
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if compact_layout:
		panel.custom_minimum_size.y = 260
	var box := _vbox(panel, 13)
	var intro := _hbox(box, 12)
	var avatar := _panel(intro, BLUE, BLUE, 10, 0)
	avatar.custom_minimum_size = Vector2(45, 45)
	var initial := _label("J", 22, BG, true)
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar.add_child(initial)
	var title := _vbox(intro, 0)
	title.add_child(_label("JEV", 19, TEXT, true))
	title.add_child(_label("YOUR GUESSING PARTNER", 10, MUTED))
	var mode_text := "OFFLINE FALLBACK" if remote_failed else ("MODEL CONNECTED" if used_remote else ("MODEL ENDPOINT SET" if not jev_url.is_empty() else "OFFLINE MODE"))
	box.add_child(_chip(mode_text, BLUE))
	if stage == "select":
		_gap(box, 8)
		box.add_child(_label("How it works", 21, TEXT, true))
		_add_step(box, "01", "Pick a game", "Your choice stays hidden from Jev.")
		_add_step(box, "02", "Write a hint", "Name a standout feature.")
		_add_step(box, "03", "Read the guess", "Adapt your next hint if Jev misses.")
		_spacer(box, false)
		box.add_child(_label("Jev sees the list and your hints.", 12, MUTED))
		return
	box.add_child(_label("GUESS LOG", 11, LIME, true))
	if guesses.is_empty():
		var waiting := _panel(box, PANEL_LIGHT, BORDER, 11, 15)
		waiting.add_child(_label("Jev is waiting for your first clue…" if stage != "thinking" else "Analyzing your hint…", 14, MUTED))
	else:
		var log_scroll := ScrollContainer.new()
		log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		box.add_child(log_scroll)
		var log := _vbox(log_scroll, 10)
		log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for i in range(guesses.size()):
			var guess: Dictionary = guesses[i]
			var card := _panel(log, PANEL_LIGHT, LIME if guess.get("correct", false) else BORDER, 10, 13)
			var card_box := _vbox(card, 5)
			card_box.add_child(_label("GUESS %02d  •  %s" % [i + 1, "CORRECT" if guess.get("correct", false) else "NOPE"], 10, LIME if guess.get("correct", false) else CORAL, true))
			card_box.add_child(_label(_game_name(String(guess.get("id", ""))), 17, TEXT, true))
			if level_index <= 2:
				card_box.add_child(_label(String(guess.get("reason", "")), 12, MUTED))
			elif level_index <= 4:
				card_box.add_child(_label("That is my best read so far.", 12, MUTED))
	if stage == "hint" and not guesses.is_empty():
		box.add_child(_label("Try a feature that separates your game from that guess.", 12, MUTED))
	elif stage == "complete":
		box.add_child(_label("A new daily board appears tomorrow.", 12, MUTED))


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
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", BG if primary else TEXT)
	button.add_theme_color_override("font_hover_color", BG if primary else LIME)
	button.add_theme_color_override("font_pressed_color", BG)
	button.add_theme_stylebox_override("normal", _style(LIME if primary else PANEL_LIGHT, LIME if primary else BORDER, 9, 1, 13))
	button.add_theme_stylebox_override("hover", _style(Color("#eafcae") if primary else Color("#223a4a"), LIME, 9, 1, 13))
	button.add_theme_stylebox_override("pressed", _style(BLUE, BLUE, 9, 1, 13))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, LIME, 9, 2, 13))
	return button


func _label(value: String, font_size: int, color: Color, bold: bool = false) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	if bold:
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.17))
		label.add_theme_constant_override("shadow_offset_y", 1)
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
