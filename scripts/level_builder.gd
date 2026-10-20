extends RefCounted
class_name LevelBuilder

# GDScript port of tools/generate_levels.py's board composer. The CI
# only fetches the daily pool from RAWG; this script picks the 7
# levels locally so the in-game refresh button never needs to touch
# the network or expose the RAWG API key.

const SIZES := [3, 4, 5, 6, 7, 7, 8]
const TARGET_SIMILARITY := [0.025, 0.045, 0.065, 0.085, 0.10, 0.115, 0.13]
const TITLES := [
	"Opening act", "Spot the mechanic", "Shared territory", "Closer calls",
	"Fine details", "Near neighbors", "The final read",
]
const NOTES := [
	"These games have little in common.",
	"Find a mechanic that sets your pick apart.",
	"Use one memorable feature.",
	"Setting and play style both help.",
	"Pick a detail the others do not share.",
	"Similar tags make every word count.",
	"Eight close options. Be exact.",
]


static func build_pack(games_dict: Dictionary, seed_text: String) -> Array:
	var pool: Array = []
	for id in games_dict.keys():
		var raw: Dictionary = games_dict[id]
		var game := {
			"id": String(id),
			"name": String(raw.get("name", id)),
			"genre": String(raw.get("genre", "")),
			"blurb": String(raw.get("blurb", "")),
			"features": raw.get("features", []),
			"_tagset": _tag_set(raw.get("features", [])),
		}
		if raw.has("rawg_url"):
			game["rawg_url"] = String(raw["rawg_url"])
		pool.append(game)
	pool.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
	if pool.size() < 40:
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(hash(seed_text))
	var used := {}
	var prev_sim := 0.0
	var levels: Array = []
	for i in range(SIZES.size()):
		var group := _choose_group(pool, int(SIZES[i]), float(TARGET_SIMILARITY[i]), prev_sim + 0.004, used, rng)
		if group.size() != int(SIZES[i]):
			return []
		prev_sim = _similarity(group)
		var ids: Array = []
		for g in group:
			ids.append(String(g["id"]))
			used[g["id"]] = true
		levels.append({"theme": TITLES[i], "note": NOTES[i], "games": ids})
	return levels


static func _tag_set(features) -> Dictionary:
	var set := {}
	for tag in features:
		var key := String(tag).to_lower()
		if key.length() > 0:
			set[key] = true
	return set


static func _jaccard(a: Dictionary, b: Dictionary) -> float:
	if a.is_empty() and b.is_empty():
		return 0.0
	var inter := 0
	for key in a.keys():
		if b.has(key):
			inter += 1
	var union_size := a.size() + b.size() - inter
	return float(inter) / float(union_size) if union_size > 0 else 0.0


static func _similarity(group: Array) -> float:
	if group.size() < 2:
		return 0.0
	var total := 0.0
	var pairs := 0
	for i in range(group.size()):
		for j in range(i + 1, group.size()):
			total += _jaccard(group[i]["_tagset"], group[j]["_tagset"])
			pairs += 1
	return total / float(pairs) if pairs > 0 else 0.0


static func _symmetric_difference(a: Dictionary, b: Dictionary) -> int:
	var diff := 0
	for key in a.keys():
		if not b.has(key):
			diff += 1
	for key in b.keys():
		if not a.has(key):
			diff += 1
	return diff


static func _distinguishable_pair(a: Dictionary, b: Dictionary) -> bool:
	if String(a["name"]).to_lower() == String(b["name"]).to_lower():
		return false
	if _symmetric_difference(a["_tagset"], b["_tagset"]) < 3:
		return false
	if _jaccard(a["_tagset"], b["_tagset"]) > 0.78:
		return false
	return true


static func _candidate_fits(group: Array, candidate: Dictionary) -> bool:
	for existing in group:
		if not _distinguishable_pair(existing, candidate):
			return false
	return true


static func _solvable(group: Array) -> bool:
	# Every candidate must have at least one feature that nobody else
	# in the level shares, so the offline Jev heuristic always has a
	# tag it can use to lock onto the player's secret.
	for i in range(group.size()):
		var mine: Dictionary = group[i]["_tagset"]
		var others := {}
		for j in range(group.size()):
			if i == j:
				continue
			for key in group[j]["_tagset"].keys():
				others[key] = true
		var has_unique := false
		for key in mine.keys():
			if not others.has(key):
				has_unique = true
				break
		if not has_unique:
			return false
	return true


static func _shuffle_sample(source: Array, size: int, rng: RandomNumberGenerator) -> Array:
	var limit: int = min(size, source.size())
	var local := source.duplicate()
	for i in range(limit):
		var j := rng.randi_range(i, local.size() - 1)
		if j != i:
			var tmp = local[i]
			local[i] = local[j]
			local[j] = tmp
	return local.slice(0, limit)


static func _choose_group(pool: Array, count: int, target: float, minimum: float, used: Dictionary, rng: RandomNumberGenerator) -> Array:
	var best: Array = []
	var best_cost := INF
	for _attempt in range(130):
		var anchor: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		var group: Array = [anchor]
		while group.size() < count:
			var choices: Array = []
			for game in pool:
				if group.has(game):
					continue
				if _candidate_fits(group, game):
					choices.append(game)
			if choices.is_empty():
				break
			var sampled := _shuffle_sample(choices, 70, rng)
			var pick: Dictionary = sampled[0]
			var pick_cost := INF
			for game in sampled:
				var trial := group.duplicate()
				trial.append(game)
				var cost: float = abs(_similarity(trial) - target)
				if used.has(game["id"]):
					cost += 0.07
				cost += rng.randf() * 0.025
				if cost < pick_cost:
					pick_cost = cost
					pick = game
			group.append(pick)
		if group.size() != count:
			continue
		if _similarity(group) < minimum:
			continue
		if not _solvable(group):
			continue
		var final_cost: float = abs(_similarity(group) - target)
		for g in group:
			if used.has(g["id"]):
				final_cost += 0.04
		if final_cost < best_cost:
			best_cost = final_cost
			best = group
	# Greedy partial groups can converge below the progression floor even
	# when valid full groups exist. Try seeded complete samples before giving up.
	if best.is_empty():
		for _attempt in range(2500):
			var group := _shuffle_sample(pool, count, rng)
			var valid := true
			for i in range(group.size()):
				for j in range(i + 1, group.size()):
					if not _distinguishable_pair(group[i], group[j]):
						valid = false
			if not valid or _similarity(group) < minimum or not _solvable(group):
				continue
			var cost: float = abs(_similarity(group) - target)
			for game in group:
				if used.has(game["id"]):
					cost += 0.04
			if cost < best_cost:
				best_cost = cost
				best = group
	return best
