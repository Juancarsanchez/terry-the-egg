class_name RequirementPromptSystem
extends RefCounted

var last_symbol := ""
var last_switch_time := 0


func choose_prompt(state: TerryGameState, director: ProgressionDirector, creature_id: String) -> Dictionary:
	if not state.creatures.has(creature_id):
		return {}
	var creature: Dictionary = state.creatures[creature_id]
	var needs: Dictionary = creature["needs"]
	if float(needs.get("health", 100.0)) < 35.0:
		return {"symbol": "sick", "priority": 100, "source": "critical"}
	if float(needs.get("satiety", 100.0)) < 18.0 and creature_id != "creature_b":
		return {"symbol": "food", "priority": 95, "source": "critical"}
	if state.phase == 3 and creature_id == "creature_main":
		var missing: Array[Dictionary] = []
		for req in director.pending_requirements(state):
			var action := str(req.get("action", ""))
			var current := 0
			if str(req.get("type", "")) == "post_action":
				current = state.get_post_count(str(req.get("target", "")), action)
			else:
				current = state.get_post_global(action)
			var remaining := int(req.get("amount", 0)) - current
			missing.append({"action": action, "remaining": remaining})
		if not missing.is_empty():
			missing.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.remaining) < int(b.remaining))
			var preferred: Dictionary = missing[0]
			if missing.size() > 1 and str(preferred.action) == last_symbol:
				preferred = missing[1]
			var symbol := _action_to_symbol(str(preferred.action))
			last_symbol = symbol
			last_switch_time = Time.get_ticks_msec()
			return {"symbol": symbol, "priority": 80, "source": "narrative", "remaining": preferred.remaining}
	if float(needs.get("satiety", 100.0)) < 45.0:
		return {"symbol": "ellipsis" if creature_id == "creature_b" else "food", "priority": 50, "source": "need"}
	if float(needs.get("energy", 100.0)) < 35.0:
		return {"symbol": "sleep", "priority": 48, "source": "need"}
	if float(needs.get("fun", 100.0)) < 40.0 and creature_id == "creature_a":
		return {"symbol": "play", "priority": 30, "source": "personality"}
	return {}


func _action_to_symbol(action: String) -> String:
	match action:
		"fed":
			return "food"
		"played":
			return "play"
		"poops_cleaned":
			return "dirty"
	return "question"


func scripted_spoken_prompt(symbol: String) -> String:
	match symbol:
		"food":
			return "Comer."
		"play":
			return "Jugamos."
		"dirty":
			return "Eso sigue ahí."
	return ""
