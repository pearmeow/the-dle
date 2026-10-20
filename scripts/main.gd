extends Control

const JevLogic = preload("res://scripts/jev_logic.gd")
const LevelBuilder = preload("res://scripts/level_builder.gd")

const BG := Color("#f5efdf")
const PANEL := Color("#faf5e9")
const PANEL_LIGHT := Color("#eee4d0")
const BORDER := Color("#c8bba3")
const TEXT := Color("#28251f")
const MUTED := Color("#5f594d")
const LIME := Color("#5a642d")
const BLUE := Color("#6c8580")
const CORAL := Color("#b84e39")

const SAVE_PATH := "user://daily_save.json"
const CURATED_PATH := "res://data/levels.json"
const GENERATED_PATH := "res://data/generated_levels.json"
const BUNDLED_POOL := "res://data/daily_pool.json"
const POOL_CACHE := "user://daily_pool.json"
const POOL_URL := "https://raw.githubusercontent.com/pearmeow/the-dle/naxin/data/daily_pool.json"
# Public URL of the Cloudflare Worker that proxies the TypeSafe Jev
# API. The TypeSafe key never ships with the game; the Worker holds
# it as a Cloudflare secret. Set JEV_API_URL in the process env (for
# native builds) to override this at runtime; HTML5 builds always use
# the constant because browsers have no process env. Leave empty to
# force offline Jev.
const DEFAULT_JEV_URL := "https://jev-proxy.thedle.workers.dev/guess"
const MAX_REFRESHES := 2
# Preserve daily progress for Continue; --playtest bypasses progress storage.
const PERSIST_PROGRESS := true
const WORD_LIMITS := [18, 16, 14, 12, 11, 9, 8]
const ATTEMPT_LIMITS := [5, 5, 4, 4, 4, 3, 3]
const MONTHS := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

var run_generation := 0
var showing_title := true
var intro_open := false
var cover_catalog: Dictionary = {}
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
var use_remote_jev := true
var compact_layout := false
var tiny_layout := false
var data_source := "CURATED"
var autosave_clock := 0.0
var pool_games: Dictionary = {}
var pool_variants: Array = []
var refresh_count := 0

var heading_font: Font = preload("res://assets/Bitter-Bold.ttf")
var body_font: Font = preload("res://assets/Lato-Regular.ttf")
var sfx_root: Node
var sfx_players: Dictionary = {}
var sfx_volume := 0.5
var sfx_muted := false
var music_player: AudioStreamPlayer
var music_volume := 0.18
var music_muted := false
var music_fade: Tween
var http: HTTPRequest
var pool_http: HTTPRequest
var timer_label: Label
var count_label: Label
var hint_edit: LineEdit


func _ready() -> void:
	var cover_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/game-covers.json"))
	if cover_data is Dictionary:
		cover_catalog = cover_data
	playtest_mode = OS.get_cmdline_user_args().has("--playtest")
	if playtest_mode:
		get_window().title = "Guess What I Mean! · Playtest"
	jev_url = OS.get_environment("JEV_API_URL").strip_edges()
	if jev_url.is_empty():
		jev_url = DEFAULT_JEV_URL
	http = HTTPRequest.new()
	http.timeout = 9.0
	http.request_completed.connect(_on_http_completed)
	add_child(http)
	_setup_music()
	_setup_sound_effects()
	_load_game_data()
	if not playtest_mode:
		_load_daily_progress()
	compact_layout = size.x < 1100.0
	tiny_layout = size.x < 600.0
	resized.connect(_on_resized)
	_render()
	_fetch_latest_pool()


func _exit_tree() -> void:
	for player in sfx_players.values():
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	sfx_players.clear()
	if is_instance_valid(music_player):
		music_player.stop()
		music_player.stream = null


func _setup_sound_effects() -> void:
	var settings := ConfigFile.new()
	if settings.load("user://audio_settings.cfg") == OK:
		sfx_volume = clampf(float(settings.get_value("effects", "volume", 0.5)), 0.0, 1.0)
		sfx_muted = bool(settings.get_value("effects", "muted", false))
	sfx_root = Node.new()
	sfx_root.name = "SoundEffects"
	add_child(sfx_root)
	var sounds := {
		"button": preload("res://assets/audio/sfx/button.wav"),
		"correct": preload("res://assets/audio/sfx/correct.wav"),
		"miss": preload("res://assets/audio/sfx/miss.wav"),
		"progress": preload("res://assets/audio/sfx/progress.wav"),
		"complete": preload("res://assets/audio/sfx/complete.wav")
	}
	for key in sounds:
		var player := AudioStreamPlayer.new()
		player.name = String(key).capitalize()
		player.stream = sounds[key]
		player.max_polyphony = 3
		player.volume_db = linear_to_db(maxf(sfx_volume, 0.0001))
		sfx_root.add_child(player)
		sfx_players[key] = player

func _play_sfx(kind: String) -> void:
	if sfx_muted or sfx_volume <= 0.0 or not sfx_players.has(kind):
		return
	var player: AudioStreamPlayer = sfx_players[kind]
	player.volume_db = linear_to_db(maxf(sfx_volume, 0.0001))
	player.play()

func _set_sfx_muted(value: bool) -> void:
	sfx_muted = value
	if value:
		for player in sfx_players.values():
			player.stop()
	_save_audio_settings()

func _set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	for player in sfx_players.values():
		player.volume_db = linear_to_db(maxf(sfx_volume, 0.0001))
		if sfx_volume <= 0.0:
			player.stop()
	_save_audio_settings()

func _build_effects_settings(parent: BoxContainer) -> void:
	parent.add_child(_label("Sound effects", 19, TEXT, true))
	var mute := CheckButton.new()
	mute.text = "Mute sound effects"
	mute.button_pressed = sfx_muted
	mute.add_theme_font_override("font", body_font)
	mute.add_theme_font_size_override("font_size", 17)
	mute.add_theme_color_override("font_color", TEXT)
	mute.toggled.connect(_set_sfx_muted)
	parent.add_child(mute)
	var caption := _label("Effects volume · %d%%" % roundi(sfx_volume * 100), 17, TEXT)
	parent.add_child(caption)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = sfx_volume * 100
	slider.custom_minimum_size.y = 34
	slider.value_changed.connect(func(value: float) -> void:
		_set_sfx_volume(value / 100.0)
		caption.text = "Effects volume · %d%%" % roundi(value)
	)
	parent.add_child(slider)
	var preview := _button("Preview chime", false)
	preview.pressed.connect(func() -> void: _play_sfx("correct"))
	parent.add_child(preview)


func _setup_music() -> void:
	var settings := ConfigFile.new()
	if settings.load("user://audio_settings.cfg") == OK:
		music_volume = clampf(float(settings.get_value("music", "volume", 0.18)), 0.0, 1.0)
		music_muted = bool(settings.get_value("music", "muted", false))
	music_player = AudioStreamPlayer.new()
	music_player.name = "BackgroundMusic"
	var track: AudioStreamMP3 = preload("res://assets/audio/thinking-music.mp3").duplicate()
	track.loop = true
	music_player.stream = track
	music_player.volume_db = -50.0
	add_child(music_player)
	music_player.play()
	music_player.stream_paused = music_muted
	music_fade = create_tween()
	music_fade.tween_property(music_player, "volume_db", linear_to_db(maxf(music_volume, 0.0001)), 1.5)

func _save_audio_settings() -> void:
	var settings := ConfigFile.new()
	settings.set_value("music", "volume", music_volume)
	settings.set_value("music", "muted", music_muted)
	settings.set_value("effects", "volume", sfx_volume)
	settings.set_value("effects", "muted", sfx_muted)
	settings.save("user://audio_settings.cfg")

func _apply_music_settings() -> void:
	if music_fade != null and music_fade.is_valid():
		music_fade.kill()
	music_player.volume_db = linear_to_db(maxf(music_volume, 0.0001))
	music_player.stream_paused = music_muted or music_volume <= 0.0

func _set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_music_settings()
	_save_audio_settings()

func _set_music_muted(value: bool) -> void:
	music_muted = value
	_apply_music_settings()
	_save_audio_settings()

func _build_audio_settings(parent: BoxContainer) -> void:
	parent.add_child(_label("Music", 19, TEXT, true))
	var mute := CheckButton.new()
	mute.text = "Mute music"
	mute.button_pressed = music_muted
	mute.add_theme_font_override("font", body_font)
	mute.add_theme_font_size_override("font_size", 17)
	mute.add_theme_color_override("font_color", TEXT)
	mute.toggled.connect(_set_music_muted)
	parent.add_child(mute)
	var volume_label := _label("Music volume · %d%%" % roundi(music_volume * 100), 17, TEXT)
	parent.add_child(volume_label)
	var volume := HSlider.new()
	volume.min_value = 0
	volume.max_value = 100
	volume.step = 1
	volume.value = music_volume * 100
	volume.custom_minimum_size.y = 34
	volume.value_changed.connect(func(value: float) -> void:
		_set_music_volume(value / 100.0)
		volume_label.text = "Music volume · %d%%" % roundi(value)
	)
	parent.add_child(volume)
	parent.add_child(_paragraph("Thinking Music — Kevin MacLeod (incompetech.com)\nLicensed under Creative Commons Attribution 4.0.\nOriginal track; looped with in-game volume and fade-in.", 14, MUTED))
	var credit_links := _hbox(parent, 10)
	var source := _button("Music source ↗", false)
	source.pressed.connect(func() -> void: OS.shell_open("https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1600060"))
	credit_links.add_child(source)
	var license_link := _button("CC BY 4.0 ↗", false)
	license_link.pressed.connect(func() -> void: OS.shell_open("https://creativecommons.org/licenses/by/4.0/"))
	credit_links.add_child(license_link)


func _process(delta: float) -> void:
	if not showing_title and stage in ["select", "hint"] and _game_has_focus():
		elapsed += delta
		autosave_clock += delta
		if is_instance_valid(timer_label):
			timer_label.text = ("Time: " if stage == "select" else "") + _format_time(elapsed)
		if autosave_clock >= 5.0:
			autosave_clock = 0.0
			_save_progress()


func _game_has_focus() -> bool:
	return get_window().has_focus()


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
	var variants_raw: Array = data.get("variants", [])
	if variants_raw.is_empty():
		# Legacy JSON (pre-variants) would force the GDScript level
		# builder to run synchronously here, freezing the window for
		# several seconds. Skip it so the curated fallback renders
		# instantly; the async pool fetch will replace us shortly
		# with a modern copy that includes variants.
		return false
	var games_dict: Dictionary = data.get("games", {})
	if games_dict.is_empty():
		return false
	pool_games = games_dict
	pool_variants = variants_raw
	var pack := _board_for_variant(refresh_count)
	if pack.is_empty():
		pool_games = {}
		pool_variants = []
		return false
	catalog = games_dict
	levels = pack
	pack_index = 0
	data_source = "RAWG"
	board_id = "pool:" + day_key + ":v" + str(refresh_count)
	return true


func _board_for_variant(variant_index: int) -> Array:
	# Preferred path: use the board CI pre-composed for us. Instant
	# because it's just a list lookup; no choose_group loop at all.
	if variant_index < pool_variants.size():
		var pack = pool_variants[variant_index]
		if typeof(pack) == TYPE_ARRAY and pack.size() == 7:
			return pack
	# Fallback: compose on the client. This path is slow for large
	# pools (seconds, not milliseconds) because the GDScript Jaccard
	# loop pays for every pair-wise tag comparison. Only reached when
	# the pool JSON predates the "variants" field.
	if pool_games.is_empty():
		return []
	return LevelBuilder.build_pack(pool_games, day_key + "#" + str(variant_index))


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
	var variants_raw: Array = data.get("variants", [])
	if variants_raw.is_empty():
		return   # Server returned a legacy JSON; keep what we have
	pool_games = games_dict
	pool_variants = variants_raw
	var pack := _board_for_variant(refresh_count)
	if pack.is_empty():
		return
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
	var pack := _board_for_variant(refresh_count)
	if pack.is_empty():
		refresh_count -= 1
		return
	levels = pack
	board_id = "pool:" + day_key + ":v" + str(refresh_count)
	message = ""
	_save_progress()
	_render()


func _load_daily_progress() -> void:
	if not PERSIST_PROGRESS:
		# Fresh start every launch: wipe any stale save left behind
		# by a previous build so refresh_count, hints, guesses, and
		# streak all reset. Progress is not tracked across sessions.
		if FileAccess.file_exists(SAVE_PATH):
			var user_dir := DirAccess.open("user://")
			if user_dir != null:
				user_dir.remove(SAVE_PATH.get_file())
		return
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
	if saved.get("day", "") != day_key:
		return
	var saved_refresh := clampi(int(saved.get("refresh_count", 0)), 0, MAX_REFRESHES)
	var expected_board := "pool:" + day_key + ":v" + str(saved_refresh) if data_source == "RAWG" else board_id
	if saved.get("board_id", "") != expected_board:
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
	if data_source == "RAWG" and refresh_count > 0:
		var variant_pack := _board_for_variant(refresh_count)
		if not variant_pack.is_empty():
			levels = variant_pack
			board_id = "pool:" + day_key + ":v" + str(refresh_count)
	if stage == "hint" and not _current_ids().has(target_id):
		stage = "select"
		target_id = ""
		hints.clear()
		guesses.clear()


func _save_progress() -> void:
	if playtest_mode or not PERSIST_PROGRESS:
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
	if jev_url.is_empty() or not use_remote_jev:
		get_tree().create_timer(0.48).timeout.connect(_resolve_local_guess_for_run.bind(run_generation))
		return
	var payload := {"candidates": _candidates(), "hints": hints, "previous_guesses": previous, "level": level_index + 1}
	var error := http.request(jev_url, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		remote_failed = true
		get_tree().create_timer(0.48).timeout.connect(_resolve_local_guess_for_run.bind(run_generation))


func _show_message(value: String) -> void:
	_play_sfx("miss")
	message = value
	_render()
	call_deferred("_focus_current_hint")


func _toggle_remote_jev() -> void:
	if jev_url.is_empty() or stage == "thinking":
		return
	use_remote_jev = not use_remote_jev
	# Clear stale status flags so the chip reflects the new choice
	# cleanly instead of lingering on an old "fallback" state.
	remote_failed = false
	if not use_remote_jev:
		used_remote = false
	_render()


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


func _resolve_local_guess_for_run(generation: int) -> void:
	if generation == run_generation:
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
	_play_sfx("correct" if correct else "miss")
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
		_play_sfx("complete")
		if last_completed_day != day_key:
			streak = streak + 1 if not last_completed_day.is_empty() and _day_number(day_key) - _day_number(last_completed_day) == 1 else 1
			last_completed_day = day_key
	else:
		_play_sfx("progress")
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
	intro_open = false
	for child in get_children():
		if child != http and child != pool_http and child != music_player and child != sfx_root:
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
	if showing_title:
		_build_title()
		return
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
	_spacer(footer, true)
	if data_source == "RAWG":
		var attribution := _button("GAME DATA: RAWG ↗", false)
		attribution.custom_minimum_size.y = 25
		attribution.pressed.connect(func() -> void: OS.shell_open("https://rawg.io"))
		footer.add_child(attribution)



func _back_to_main_menu() -> void:
	if is_instance_valid(hint_edit):
		hint_draft = hint_edit.text
	_save_progress()
	showing_title = true
	_render()

func _restart_run() -> void:
	run_generation += 1
	http.cancel_request()
	level_index = 0
	stage = "select"
	target_id = ""
	hints.clear()
	guesses.clear()
	results.clear()
	hint_draft = ""
	message = ""
	elapsed = 0.0
	autosave_clock = 0.0
	used_remote = false
	remote_failed = false
	showing_title = false
	_save_progress()
	_render()

func _build_run_navigation(parent: BoxContainer) -> void:
	var back := _button("Main menu", false)
	back.pressed.connect(_back_to_main_menu)
	parent.add_child(back)
	var restart := _button("Restart run", false)
	restart.tooltip_text = "Start today's seven levels over with the same games"
	restart.pressed.connect(_restart_run)
	parent.add_child(restart)
	var sound := _button("Music off" if music_muted else "Music on", false)
	sound.tooltip_text = "Toggle background music; volume is in Settings"
	sound.pressed.connect(func() -> void:
		_set_music_muted(not music_muted)
		sound.text = "Music off" if music_muted else "Music on"
	)
	parent.add_child(sound)


func _start_game() -> void:
	showing_title = false
	_render()

func _build_title() -> void:
	var art := TextureRect.new()
	art.texture = preload("res://assets/title-background.png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	if tiny_layout:
		var wash := ColorRect.new()
		wash.color = Color(0.96, 0.94, 0.88, 0.90)
		wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(wash)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.anchor_right = 1.0 if tiny_layout else 0.50
	margin.add_theme_constant_override("margin_left", 24 if tiny_layout else 65)
	margin.add_theme_constant_override("margin_right", 24 if tiny_layout else 35)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 60)
	add_child(margin)
	var menu := _vbox(margin, 18)
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_child(_label("Guess What\nI Mean!", 42 if tiny_layout else (52 if compact_layout else 72), TEXT, true))
	menu.add_child(_paragraph("A daily game of clues & clever guesses.", 18 if tiny_layout else 22, TEXT))
	_gap(menu, 10)
	var date := Time.get_date_dict_from_system()
	menu.add_child(_label("%s %d · 7 DAILY LEVELS" % [MONTHS[date.month - 1], date.day], 13, MUTED))
	var caption := "Start today’s game →"
	if stage == "complete":
		caption = "View today’s results →"
	elif level_index > 0 or stage != "select" or elapsed > 0:
		caption = "Continue today’s game →"
	var start := _button(caption, true)
	start.custom_minimum_size.y = 64
	start.add_theme_font_override("font", heading_font)
	start.add_theme_font_size_override("font_size", 20 if tiny_layout else 25)
	start.pressed.connect(_start_game)
	menu.add_child(start)
	var rules := _button("How to play", false)
	rules.custom_minimum_size.y = 58
	rules.add_theme_font_override("font", heading_font)
	rules.add_theme_font_size_override("font_size", 22)
	rules.pressed.connect(_show_help)
	menu.add_child(rules)
	var settings := _button("Settings", false)
	settings.add_theme_stylebox_override("normal", _style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 8))
	settings.pressed.connect(_show_settings)
	menu.add_child(settings)
	var footer := _paragraph("One secret. Your clues. Jev’s best guess.", 14, TEXT)
	footer.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	footer.position = Vector2(24 if tiny_layout else 65, size.y - 44)
	footer.size.x = size.x - 48
	add_child(footer)

func _show_settings() -> void:
	_open_menu_sheet("Settings", [], true)

func _open_menu_sheet(title: String, paragraphs: Array, display_settings: bool = false) -> void:
	if has_node("MenuSheet"):
		return
	var overlay := Control.new()
	overlay.name = "MenuSheet"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.10, 0.08, 0.05, 0.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := _panel(center, PANEL, BORDER, 12, 22)
	panel.custom_minimum_size.x = minf(640, size.x - 40)
	var content := _vbox(panel, 16)
	content.add_child(_label(title, 28, TEXT, true))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = minf(360, size.y - 230)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var copy := _vbox(scroll, 16)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for text in paragraphs:
		copy.add_child(_paragraph(String(text), 17, TEXT))
	if display_settings:
		_build_effects_settings(copy)
		_build_audio_settings(copy)
		copy.add_child(_paragraph("Display", 19, TEXT))
		var fullscreen := CheckButton.new()
		fullscreen.text = "Fullscreen"
		fullscreen.add_theme_font_override("font", body_font)
		fullscreen.add_theme_font_size_override("font_size", 18)
		fullscreen.add_theme_color_override("font_color", TEXT)
		fullscreen.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		fullscreen.toggled.connect(func(enabled: bool) -> void:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)
		)
		copy.add_child(fullscreen)
	var close := _button("Back", true)
	close.pressed.connect(overlay.queue_free)
	content.add_child(close)
	close.grab_focus()


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
	var navigation: BoxContainer = _hbox(parent, 10) if compact_layout else row
	_build_run_navigation(navigation)
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
	_open_menu_sheet("How to play", [
		"1. Pick a secret game. Read Quick intros if a game is unfamiliar. Jev sees the candidates, but never your choice.",
		"2. Give a short clue about gameplay, setting, or a distinctive feature. Facts from Quick intros are allowed.",
		"3. Read Jev’s guess. If it misses, try another clue before your attempts run out.",
		"Keep title words and list positions out of your clues. Follow each level’s word limit.",
		"Complete seven daily levels. Fewer clues, fewer words, and less active time earn more points; a missed level earns zero.",
		"The timer begins after Start. Reading Quick intros, choosing a game, and writing clues all count. Jev’s thinking time and time outside the game window do not."
	])


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
	var box := _vbox(parent, 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
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
	box.add_child(_label("Pick your secret.", 30 if tiny_layout else 40, TEXT, true))
	box.add_child(_paragraph("New to these games? Read a Quick intro, then choose your secret.", 16, MUTED))
	_build_cards(box, true)
	timer_label = _label("Time: " + _format_time(elapsed), 16, MUTED)
	box.add_child(timer_label)
	box.add_child(_paragraph("Next: describe your game without using its title. %d guesses · %d words per clue." % [ATTEMPT_LIMITS[level_index], WORD_LIMITS[level_index]], 16, MUTED))
	if _can_refresh():
		var refresh := _button("Reshuffle board · %d left" % (MAX_REFRESHES - refresh_count), false)
		refresh.pressed.connect(_refresh_board)
		box.add_child(refresh)

func _card_art(game: Dictionary, width: float, height: float) -> Control:
	var name := String(game.get("name", "Game"))
	for entry in cover_catalog.values():
		if String(entry.get("name", "")).to_lower() == name.to_lower():
			var image := TextureRect.new()
			image.texture = load(String(entry["path"]))
			image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			image.custom_minimum_size = Vector2(width, height)
			image.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return image
	# Unknown titles get a clearly typographic game file, never unrelated cover art.
	var colors := [Color("#355653"), Color("#633e36"), Color("#504864"), Color("#515b34"), Color("#334f67")]
	var ink: Color = colors[posmod(name.hash(), colors.size())]
	var poster := _panel(null, ink, ink, 2, 14)
	poster.custom_minimum_size = Vector2(width, height)
	poster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var content := _vbox(poster, 12)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_label("GAME FILE", 12, PANEL))
	_spacer(content, false)
	var title := _paragraph(name, 23, PANEL)
	title.add_theme_font_override("font", heading_font)
	content.add_child(title)
	_spacer(content, false)
	content.add_child(_paragraph(String(game.get("genre", "Video game")), 14, PANEL))
	for child in content.get_children():
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return poster

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
	scroll.custom_minimum_size.y = 450 if selectable else 350
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
		var artwork := _card_art(game, width - 14, 200 if selectable else 100)
		artwork.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.add_child(artwork)
		var title := _paragraph(String(game["name"]), 18, TEXT)
		title.add_theme_font_override("font", heading_font)
		title.custom_minimum_size = Vector2(width - 14, 44)
		title.max_lines_visible = 2
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		content.add_child(title)
		var caption := _paragraph(_card_caption(game), 16, MUTED)
		caption.custom_minimum_size.y = 64 if selectable else 44
		caption.max_lines_visible = 3 if selectable else 2
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		content.add_child(caption)
		var intro := _button("Quick intro", false)
		intro.tooltip_text = "Learn about this game before writing a clue"
		intro.pressed.connect(_show_game_intro.bind(String(game["id"])))
		content.add_child(intro)
		if not selectable:
			var secret_mark := _label("✓ YOUR SECRET" if selected else " ", 13, CORAL, true)
			secret_mark.custom_minimum_size.y = 18
			content.add_child(secret_mark)
		if selectable:
			var choose := _button("%02d   Choose →" % [i + 1], false)
			choose.add_theme_font_size_override("font_size", 16)
			choose.pressed.connect(_choose_target.bind(String(game["id"])))
			content.add_child(choose)
			card.mouse_entered.connect(_highlight_card.bind(card, true))
			card.mouse_exited.connect(_highlight_card.bind(card, false))
			card.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					_play_sfx("button")
					_choose_target(String(game["id"]))
			)
			for child in content.get_children():
				if not child is Button:
					child.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			card.tooltip_text = "Keep " + String(game["name"]) + " secret from Jev"


func _intro_features(game: Dictionary) -> Array[String]:
	var useful: Array[String] = []
	for raw in game.get("features", []):
		var feature := String(raw).replace("-", " ")
		var lower := feature.to_lower()
		if "steam" in lower or "controller" in lower or "leaderboard" in lower or "workshop" in lower or "achievement" in lower or "cloud" in lower:
			continue
		var plain_words := {"voxel": "A world made of cube-shaped blocks", "roguelike": "Repeatable runs with changing challenges", "metroidvania": "Explore connected areas and unlock new abilities", "soulslike": "Demanding combat with careful timing", "fps": "See the action through your character’s eyes"}
		useful.append(String(plain_words.get(lower, feature.capitalize())))
		if useful.size() == 3:
			break
	return useful

func _close_game_intro(overlay: Control) -> void:
	intro_open = false
	overlay.queue_free()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and has_node("MenuSheet"):
		get_node("MenuSheet").queue_free()
		get_viewport().set_input_as_handled()
		return
	if intro_open and event.is_action_pressed("ui_cancel"):
		var overlay := get_node_or_null("GameIntro")
		if overlay != null:
			_close_game_intro(overlay)
		get_viewport().set_input_as_handled()

func _show_game_intro(id: String) -> void:
	if intro_open or not catalog.has(id):
		return
	intro_open = true
	var game: Dictionary = catalog[id]
	var overlay := Control.new()
	overlay.name = "GameIntro"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.12, 0.10, 0.07, 0.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := _panel(center, PANEL, BORDER, 12, 22)
	panel.custom_minimum_size = Vector2(minf(660, size.x - 40), 0)
	var content := _vbox(panel, 14)
	content.add_child(_label("Quick intro · No prior knowledge needed", 15, CORAL, true))
	content.add_child(_paragraph(String(game.get("name", "Game")), 28, TEXT))
	content.add_child(_label(String(game.get("genre", "Video game")), 16, MUTED))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = minf(330, size.y - 290)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var details := _vbox(scroll, 14)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_child(_label("What you do", 19, TEXT, true))
	var description := String(game.get("blurb", ""))
	if description.is_empty() or description.begins_with("Gameplay tags:"):
		description = "A %s game featuring %s." % [String(game.get("genre", "video")).to_lower(), ", ".join(_intro_features(game)).to_lower()]
	details.add_child(_paragraph(description, 17, TEXT))
	var features := _intro_features(game)
	if not features.is_empty():
		details.add_child(_label("Details you can use in a clue", 19, TEXT, true))
		for feature in features:
			details.add_child(_paragraph("• " + feature, 17, MUTED))
	details.add_child(_paragraph("You may use these facts in your clue. Keep the game's title secret. Jev receives the same game information.", 15, MUTED))
	var close := _button("Back to game", true)
	close.pressed.connect(_close_game_intro.bind(overlay))
	content.add_child(close)
	close.grab_focus()


func _highlight_card(card: PanelContainer, hovered: bool) -> void:
	card.add_theme_stylebox_override("panel", _style(Color("#fff9ef") if hovered else PANEL, CORAL if hovered else BORDER, 5, 2 if hovered else 1, 7))


func _build_hint(box: BoxContainer) -> void:
	box.add_child(_label("Write your clue.", 29 if tiny_layout else 36, TEXT, true))
	box.add_child(_paragraph("Your secret is %s. Help Jev find it." % _game_name(target_id), 16, MUTED))
	_build_cards(box, false)
	var composer := _panel(box, PANEL, BORDER, 5, 18)
	var compose := _vbox(composer, 9)
	compose.add_child(_label("Jev is following your clues…" if stage == "thinking" else "Clue %d · What makes it distinctive?" % (hints.size() + 1), 19, TEXT, true))
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
	count_label = _label("%d / %d words" % [JevLogic.word_count(hint_draft), WORD_LIMITS[level_index]], 16, MUTED)
	bottom.add_child(count_label)
	_spacer(bottom, true)
	if stage != "thinking":
		var submit := _button("Send clue →", true)
		submit.pressed.connect(_submit_hint)
		bottom.add_child(submit)
	var stats := _hbox(compose, 12)
	stats.add_child(_label("%d guesses left · Keep the title secret" % (ATTEMPT_LIMITS[level_index] - guesses.size()), 14, MUTED))
	_spacer(stats, true)
	timer_label = _label(_format_time(elapsed), 14, MUTED)
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
	box.alignment = BoxContainer.ALIGNMENT_CENTER
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
	portrait.custom_minimum_size.y = 180 if compact_layout else 250
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(portrait)
	if not jev_url.is_empty():
		var toggle_btn := _button("AI Jev: on" if use_remote_jev else "AI Jev: off", false)
		toggle_btn.disabled = stage == "thinking"
		toggle_btn.pressed.connect(_toggle_remote_jev)
		box.add_child(toggle_btn)
		var mode := "Online AI · clues sent to Jev" if use_remote_jev else "Offline clue matcher"
		if use_remote_jev and remote_failed:
			mode = "AI unavailable · offline fallback"
		box.add_child(_paragraph(mode, 12, MUTED))
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
		box.add_child(_paragraph("Pick a game. I’ll follow your clues.", 16, MUTED))

	_gap(box, 12)
	var divider := HSeparator.new()
	divider.add_theme_stylebox_override("separator", _style(BORDER, BORDER, 0, 0, 0))
	divider.custom_minimum_size.y = 1
	box.add_child(divider)
	_gap(box, 5)
	var score_caption := _label("TOTAL SCORE", 12, MUTED)
	score_caption.add_theme_font_override("font", heading_font)
	box.add_child(score_caption)
	box.add_child(_label(str(_total_score()), 52, TEXT, true))


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
	button.pressed.connect(_play_sfx.bind("button"))
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
