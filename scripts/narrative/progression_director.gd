class_name ProgressionDirector
extends RefCounted

signal phase_changed(new_phase: int)
signal event_requested(event_id: String)

var phases: Dictionary = {}
var _requested_events: Dictionary = {}


func _init(path: String = "res://data/phases/phases.json") -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("No se pudieron cargar las fases")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	for phase_data in parsed.get("phases", []):
		phases[int(phase_data.get("id", -1))] = phase_data


func evaluate(state: TerryGameState) -> void:
	if not phases.has(state.phase):
		return
	var phase_data: Dictionary = phases[state.phase]
	if not requirements_complete(state, phase_data.get("requirements", [])):
		return
	var close_event := str(phase_data.get("close_event", ""))
	if close_event != "":
		var event_key := "%d:%s" % [state.phase, close_event]
		if not _requested_events.has(event_key):
			_requested_events[event_key] = true
			event_requested.emit(close_event)
		return
	var next_phase := int(phase_data.get("next_phase", state.phase))
	if next_phase != state.phase:
		set_phase(state, next_phase)


func set_phase(state: TerryGameState, new_phase: int) -> void:
	state.phase = new_phase
	if phases.has(new_phase):
		state.unlocks.clear()
		for action in phases[new_phase].get("available_actions", []):
			state.unlocks.append(str(action))
	phase_changed.emit(new_phase)
	state.changed.emit()


func requirements_complete(state: TerryGameState, requirements: Array) -> bool:
	for requirement in requirements:
		if not requirement_complete(state, requirement):
			return false
	return true


func requirement_complete(state: TerryGameState, requirement: Dictionary) -> bool:
	var requirement_type := str(requirement.get("type", ""))
	var action := str(requirement.get("action", ""))
	var amount := int(requirement.get("amount", 1))
	match requirement_type:
		"all_hatched":
			return state.all_hatched()
		"each_action":
			for creature_id in TerryGameState.CREATURE_IDS:
				if int(state.creatures[creature_id]["counters"].get(action, 0)) < amount:
					return false
			return true
		"action":
			var target := str(requirement.get("target", ""))
			return int(state.creatures[target]["counters"].get(action, 0)) >= amount
		"global":
			return int(state.global_counters.get(action, 0)) >= amount
		"active_time":
			return float(state.global_counters.get("care_time", 0.0)) >= float(amount)
		"dialogue_seen":
			return str(requirement.get("dialogue", "")) in state.dialogues_seen
		"post_action":
			return state.get_post_count(str(requirement.get("target", "")), action) >= amount
		"post_global":
			return state.get_post_global(action) >= amount
		"flag":
			return bool(state.flags.get(str(requirement.get("flag", "")), false))
	return false


func pending_requirements(state: TerryGameState) -> Array[Dictionary]:
	var pending: Array[Dictionary] = []
	if not phases.has(state.phase):
		return pending
	for requirement in phases[state.phase].get("requirements", []):
		if not requirement_complete(state, requirement):
			pending.append((requirement as Dictionary).duplicate(true))
	return pending


func reset_event_latch(phase_id: int) -> void:
	for key in _requested_events.keys():
		if str(key).begins_with(str(phase_id) + ":"):
			_requested_events.erase(key)
