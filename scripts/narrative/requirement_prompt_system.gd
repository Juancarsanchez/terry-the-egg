class_name RequirementPromptSystem
extends RefCounted

func choose_prompt(state: TerryGameState, _director: ProgressionDirector, creature_id: String) -> Dictionary:
	if not state.creatures.has(creature_id):
		return {}
	var creature: Dictionary = state.creatures[creature_id]
	var needs: Dictionary = creature["needs"]
	if str(creature.get("activity", "")) != "":
		return {}
	var active_request := str(creature.get("request", ""))
	if active_request != "":
		return {
			"symbol": _request_to_symbol(active_request),
			"priority": 105,
			"source": "request",
			"persistent": true
		}
	if float(needs.get("health", 100.0)) < 35.0:
		return {"symbol": "sick", "priority": 100, "source": "critical"}
	if float(needs.get("satiety", 100.0)) < 18.0 and creature_id != "creature_b":
		return {"symbol": "creature_food", "priority": 95, "source": "critical"}
	if float(needs.get("satiety", 100.0)) < 45.0:
		return {"symbol": "ellipsis" if creature_id == "creature_b" else "creature_food", "priority": 50, "source": "need"}
	if float(needs.get("energy", 100.0)) < 35.0:
		return {"symbol": "sleep", "priority": 48, "source": "need"}
	if float(needs.get("fun", 100.0)) < 40.0 and creature_id == "creature_b":
		return {"symbol": "play", "priority": 30, "source": "personality"}
	return {}


func _request_to_symbol(request: String) -> String:
	match request:
		"food":
			return "creature_food"
		"play":
			return "play"
		"sleep":
			return "sleep"
		"affection":
			return "pet_request"
		"clean":
			return "dirty"
	return "question"
