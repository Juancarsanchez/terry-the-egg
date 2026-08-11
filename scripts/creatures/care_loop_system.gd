class_name CareLoopSystem
extends RefCounted


func update(state: TerryGameState, definitions: Dictionary, now: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for creature_id in TerryGameState.CREATURE_IDS:
		var creature: Dictionary = state.creatures[creature_id]
		if not bool(creature.get("present", false)) or bool(creature.get("disappeared", false)):
			continue
		_finish_activity_if_due(creature_id, creature, now, events)
		_start_request_if_due(creature_id, creature, definitions[creature_id], now, events)
		_miss_request_if_due(creature_id, creature, now, events)
		_update_first_day_body(creature_id, creature, now, events)
	return events


func begin_activity(creature: Dictionary, activity: String, now: int, duration: int) -> bool:
	if str(creature.get("activity", "")) != "":
		return false
	creature["activity"] = activity
	creature["activity_until_unix"] = now + duration
	if activity == "sleep":
		creature["sleeping"] = true
		creature["sleep_until_unix"] = now + duration
	return true


func fulfill_request(state: TerryGameState, creature_id: String, action: String, now: int) -> bool:
	if not state.creatures.has(creature_id):
		return false
	var creature: Dictionary = state.creatures[creature_id]
	var request := str(creature.get("request", ""))
	if request == "" or not _action_matches_request(action, request):
		return false
	_clear_request(creature)
	creature["next_request_unix"] = now + TerryGameState.ROUTINE_REQUEST_DELAY_SECONDS
	state.complete_care_cycle(creature_id, action)
	return true


func set_immediate_request(creature: Dictionary, request: String, now: int) -> void:
	creature["request"] = request
	creature["request_started_unix"] = now
	creature["request_deadline_unix"] = now + TerryGameState.REQUEST_GRACE_SECONDS
	creature["next_request_unix"] = 0


func request_symbol(request: String) -> String:
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


func _finish_activity_if_due(creature_id: String, creature: Dictionary, now: int, events: Array[Dictionary]) -> void:
	var activity := str(creature.get("activity", ""))
	var activity_until := int(creature.get("activity_until_unix", 0))
	if activity == "" or activity_until <= 0 or now < activity_until:
		return
	creature["activity"] = ""
	creature["activity_until_unix"] = 0
	if activity == "sleep":
		creature["sleeping"] = false
		creature["sleep_until_unix"] = 0
		creature["needs"]["energy"] = 100.0
	if activity == "play":
		creature["needs"]["fun"] = 100.0
		creature["needs"]["affection"] = minf(100.0, float(creature["needs"]["affection"]) + 12.0)
		creature["needs"]["satiety"] = minf(float(creature["needs"]["satiety"]), 42.0)
		set_immediate_request(creature, "food", now)
	else:
		creature["next_request_unix"] = now + TerryGameState.ROUTINE_REQUEST_DELAY_SECONDS
	events.append({"type": "activity_finished", "creature_id": creature_id, "activity": activity})


func _start_request_if_due(
	creature_id: String,
	creature: Dictionary,
	definition: CreatureDefinition,
	now: int,
	events: Array[Dictionary]
) -> void:
	if str(creature.get("activity", "")) != "" or str(creature.get("request", "")) != "":
		return
	var next_request := int(creature.get("next_request_unix", 0))
	if next_request <= 0:
		creature["next_request_unix"] = now + TerryGameState.ROUTINE_REQUEST_DELAY_SECONDS
		return
	if now < next_request:
		return
	var cycle: Array[String] = definition.request_cycle
	if cycle.is_empty():
		cycle = ["food", "play", "sleep", "affection"]
	var index := int(creature.get("request_cycle_index", 0)) % cycle.size()
	var request := cycle[index]
	creature["request_cycle_index"] = index + 1
	set_immediate_request(creature, request, now)
	events.append({"type": "request_started", "creature_id": creature_id, "request": request})


func _miss_request_if_due(creature_id: String, creature: Dictionary, now: int, events: Array[Dictionary]) -> void:
	var request := str(creature.get("request", ""))
	var deadline := int(creature.get("request_deadline_unix", 0))
	if request == "" or deadline <= 0 or now < deadline:
		return
	creature["missed_requests"] = int(creature.get("missed_requests", 0)) + 1
	_clear_request(creature)
	creature["next_request_unix"] = now + TerryGameState.ROUTINE_REQUEST_DELAY_SECONDS
	events.append({"type": "request_missed", "creature_id": creature_id, "request": request})


func _update_first_day_body(creature_id: String, creature: Dictionary, now: int, events: Array[Dictionary]) -> void:
	if creature_id != "creature_a" or str(creature.get("body_state", "normal")) == "chubby":
		return
	var born := int(creature.get("born_unix", 0))
	if born <= 0 or now - born < TerryGameState.FIRST_DAY_SECONDS:
		return
	if int(creature.get("favorite_care", 0)) < 4:
		return
	creature["body_state"] = "chubby"
	events.append({"type": "body_changed", "creature_id": creature_id, "body_state": "chubby"})


func _clear_request(creature: Dictionary) -> void:
	creature["request"] = ""
	creature["request_started_unix"] = 0
	creature["request_deadline_unix"] = 0


func _action_matches_request(action: String, request: String) -> bool:
	var mapping := {
		"fed": "food",
		"played": "play",
		"slept": "sleep",
		"petted": "affection",
		"cleaned": "clean"
	}
	return str(mapping.get(action, "")) == request
