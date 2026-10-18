extends RefCounted
class_name JevLogic

const STOP_WORDS := ["a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "has", "in", "is", "it", "its", "of", "on", "or", "the", "their", "there", "this", "to", "with", "you", "your", "game", "play", "player", "one", "two", "three", "very", "can", "do", "where", "into", "through", "about"]
const TITLE_COMMON := ["the", "and", "of", "a", "an", "to", "in", "at", "for", "with", "new", "old", "little", "big", "short", "friends", "story", "stories", "game", "games", "dark", "forest", "island", "town", "world", "life", "animal", "time", "super", "country", "return", "case", "shadow", "shadows", "quietus", "deluxe", "ultimate", "party", "pack", "one", "two", "three", "ii", "iii", "vi", "v", "2", "3", "4", "5", "6", "8", "10"]

static func normalized(value: String) -> String:
	var regex := RegEx.new()
	regex.compile("[^a-z0-9]+")
	return regex.sub(value.to_lower(), " ", true).strip_edges()


static func terms(value: String) -> Array[String]:
	var result: Array[String] = []
	for raw in normalized(value).split(" ", false):
		var word := String(raw)
		if word.length() < 3 or STOP_WORDS.has(word):
			continue
		if word.ends_with("ies") and word.length() > 5:
			word = word.substr(0, word.length() - 3) + "y"
		elif word.ends_with("ing") and word.length() > 6:
			word = word.substr(0, word.length() - 3)
		elif word.ends_with("s") and word.length() > 4 and not word.ends_with("ss"):
			word = word.substr(0, word.length() - 1)
		if not result.has(word):
			result.append(word)
	return result


static func word_count(value: String) -> int:
	return normalized(value).split(" ", false).size()


static func reveals_title(hint: String, title: String) -> bool:
	var clean_hint := " " + normalized(hint) + " "
	var clean_title := normalized(title)
	if clean_title.length() >= 4 and clean_hint.contains(" " + clean_title + " "):
		return true
	var initials := ""
	for word in clean_title.split(" ", false):
		if word.length() >= 4 and not TITLE_COMMON.has(word) and clean_hint.contains(" " + word + " "):
			return true
		if word.length() > 1 and not TITLE_COMMON.has(word):
			initials += word.substr(0, 1)
	if initials.length() >= 2 and clean_hint.contains(" " + initials + " "):
		return true
	return false


static func reveals_shortcut(hint: String) -> bool:
	var clean_hint := " " + normalized(hint) + " "
	for position in ["top left", "top right", "bottom left", "bottom right", "leftmost", "rightmost"]:
		if clean_hint.contains(" " + position + " "):
			return true
	var regex := RegEx.new()
	regex.compile("\\b(option|choice|candidate|game|pick|number|slot|row|column) (one|two|three|four|five|six|seven|eight|nine|ten|[0-9]+)\\b|\\b(first|second|third|fourth|fifth|sixth|seventh|eighth|last) (option|choice|candidate|game|one)\\b")
	return regex.search(normalized(hint)) != null


static func guess(candidates: Array, hints: Array, previous_guesses: Array) -> Dictionary:
	var all_hints := " ".join(hints)
	var clue_terms := terms(all_hints)
	var frequency := {}
	for game in candidates:
		var unique_terms := {}
		for feature in game.get("features", []):
			for term in terms(feature):
				unique_terms[term] = true
		for term in unique_terms:
			frequency[term] = int(frequency.get(term, 0)) + 1

	var best := {}
	var best_score := -100000.0
	var best_match := ""
	for game in candidates:
		var game_id := String(game.get("id", ""))
		if previous_guesses.has(game_id):
			continue
		var score := 0.0
		var matched := ""
		for feature in game.get("features", []):
			var feature_terms := terms(feature)
			var overlap := 0
			for term in feature_terms:
				if clue_terms.has(term):
					overlap += 1
					score += 2.2 + 2.4 * (1.0 - float(frequency.get(term, 1) - 1) / max(1.0, float(candidates.size() - 1)))
			if overlap > 0 and matched.is_empty():
				matched = String(feature)
			if normalized(all_hints).contains(normalized(String(feature))):
				score += 3.5
		for term in terms(String(game.get("blurb", ""))):
			if clue_terms.has(term):
				score += 0.75
		if score > best_score:
			best_score = score
			best = game
			best_match = matched
	if best.is_empty():
		return {"id": "", "reason": "I ran out of options.", "confidence": 0.0}
	var reason := "I am making my best read from the clues so far."
	if not best_match.is_empty():
		reason = "The clue about %s pointed me here." % best_match
	return {"id": String(best.get("id", "")), "reason": reason, "confidence": clampf(best_score / 14.0, 0.05, 0.98)}
