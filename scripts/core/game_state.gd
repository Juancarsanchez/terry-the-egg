class_name TerryGameState
extends RefCounted

signal changed

const CREATURE_IDS := ["creature_a", "creature_b", "creature_main"]
const NEED_NAMES := ["satiety", "hygiene", "energy", "fun", "affection", "health"]
const EGG_NUTRITION_REQUIRED := 15
const EGG_MEAL_CAPACITY := 2
const EGG_MEAL_INTERVAL_SECONDS := 60 * 60
const CREATURE_MEAL_CAPACITY := 2
const CREATURE_MEAL_INTERVAL_SECONDS := 60 * 60
const SLEEP_DURATION_SECONDS := 60 * 60
const POOP_DELAY_SECONDS := 2 * 60 * 60

var phase: int = 0
var eggs: Dictionary = {}
var creatures: Dictionary = {}
var global_counters: Dictionary = {}
var dialogues_seen: Array[String] = []
var answers: Dictionary = {}
var unlocks: Array[String] = []
var flags: Dictionary = {}
var post_baseline: Dictionary = {}
var last_session_unix: int = 0


func _init() -> void:
	reset_all()


func reset_all() -> void:
	phase = 0
	eggs.clear()
	creatures.clear()
	for creature_id in CREATURE_IDS:
		eggs[creature_id] = {
			"heat": 0.0,
			"nutrition": 0.0,
			"heat_required": 5.0,
			"nutrition_required": float(EGG_NUTRITION_REQUIRED),
			"meal_bites": 0,
			"next_meal_unix": 0,
			"visual_state": "intact",
			"hatched": false
		}
		var counters := {
			"fed": 0,
			"played": 0,
			"petted": 0,
			"slept": 0,
			"poops_generated": 0,
			"poops_cleaned": 0,
			"status_checks": 0
		}
		var needs := {}
		for need_name in NEED_NAMES:
			needs[need_name] = 100.0
		creatures[creature_id] = {
			"present": false,
			"disappeared": false,
			"sleeping": false,
			"sleep_until_unix": 0,
			"ready_to_sleep": false,
			"meal_bites": 0,
			"next_meal_unix": 0,
			"poop_due_unix": 0,
			"poops_waiting": 0,
			"needs": needs,
			"counters": counters
		}
	global_counters = {
		"sessions_started": 0,
		"care_time": 0.0,
		"poops_generated": 0,
		"poops_cleaned": 0,
		"dialogues_seen": 0,
		"answers_chosen": 0
	}
	dialogues_seen.clear()
	answers.clear()
	unlocks = ["feed", "status"]
	flags = {
		"pending_disappearance": false,
		"creature_a_disappeared": false,
		"dialogue_active": false,
		"player_place_shown": false,
		"first_absence_sequence_played": false
	}
	post_baseline.clear()
	last_session_unix = int(Time.get_unix_time_from_system())
	changed.emit()


func increment_action(creature_id: String, action: String, amount: int = 1) -> void:
	if not creatures.has(creature_id):
		return
	var counters: Dictionary = creatures[creature_id]["counters"]
	counters[action] = int(counters.get(action, 0)) + amount
	creatures[creature_id]["counters"] = counters
	changed.emit()


func increment_global(action: String, amount: int = 1) -> void:
	global_counters[action] = int(global_counters.get(action, 0)) + amount
	changed.emit()


func all_hatched() -> bool:
	for creature_id in CREATURE_IDS:
		if not bool(eggs[creature_id]["hatched"]):
			return false
	return true


func hatch(creature_id: String) -> void:
	if not eggs.has(creature_id):
		return
	eggs[creature_id]["hatched"] = true
	eggs[creature_id]["visual_state"] = "open"
	creatures[creature_id]["present"] = true
	changed.emit()


func capture_post_dialogue_baseline() -> void:
	post_baseline = {
		"creature_main": (creatures["creature_main"]["counters"] as Dictionary).duplicate(true),
		"global": global_counters.duplicate(true)
	}
	changed.emit()


func get_post_count(creature_id: String, action: String) -> int:
	var now := int((creatures[creature_id]["counters"] as Dictionary).get(action, 0))
	var before := 0
	if post_baseline.has(creature_id):
		before = int((post_baseline[creature_id] as Dictionary).get(action, 0))
	return maxi(0, now - before)


func get_post_global(action: String) -> int:
	var now := int(global_counters.get(action, 0))
	var before := 0
	if post_baseline.has("global"):
		before = int((post_baseline["global"] as Dictionary).get(action, 0))
	return maxi(0, now - before)


func mark_dialogue_seen(dialogue_id: String) -> void:
	if dialogue_id not in dialogues_seen:
		dialogues_seen.append(dialogue_id)
		increment_global("dialogues_seen")


func set_answer(key: String, value: String) -> void:
	answers[key] = value
	increment_global("answers_chosen")


func to_dict() -> Dictionary:
	return {
		"save_version": 1,
		"phase": phase,
		"eggs": eggs,
		"creatures": creatures,
		"global_counters": global_counters,
		"dialogues_seen": dialogues_seen,
		"answers": answers,
		"unlocks": unlocks,
		"flags": flags,
		"post_baseline": post_baseline,
		"last_session_unix": int(Time.get_unix_time_from_system())
	}


func load_dict(data: Dictionary) -> bool:
	if int(data.get("save_version", 0)) != 1:
		return false
	phase = int(data.get("phase", 0))
	eggs = (data.get("eggs", {}) as Dictionary).duplicate(true)
	creatures = (data.get("creatures", {}) as Dictionary).duplicate(true)
	global_counters = (data.get("global_counters", {}) as Dictionary).duplicate(true)
	dialogues_seen.clear()
	for item in data.get("dialogues_seen", []):
		dialogues_seen.append(str(item))
	answers = (data.get("answers", {}) as Dictionary).duplicate(true)
	unlocks.clear()
	for item in data.get("unlocks", []):
		unlocks.append(str(item))
	flags = (data.get("flags", {}) as Dictionary).duplicate(true)
	post_baseline = (data.get("post_baseline", {}) as Dictionary).duplicate(true)
	last_session_unix = int(data.get("last_session_unix", Time.get_unix_time_from_system()))
	_repair_missing_fields()
	changed.emit()
	return true


func _repair_missing_fields() -> void:
	for creature_id in CREATURE_IDS:
		if not eggs.has(creature_id) or not creatures.has(creature_id):
			reset_all()
			return
		var egg: Dictionary = eggs[creature_id]
		egg["nutrition"] = clampf(float(egg.get("nutrition", 0.0)), 0.0, float(EGG_NUTRITION_REQUIRED))
		egg["nutrition_required"] = float(EGG_NUTRITION_REQUIRED)
		if not egg.has("meal_bites"):
			egg["meal_bites"] = 0
		else:
			egg["meal_bites"] = clampi(int(egg["meal_bites"]), 0, EGG_MEAL_CAPACITY)
		if not egg.has("next_meal_unix"):
			egg["next_meal_unix"] = 0
		else:
			egg["next_meal_unix"] = maxi(0, int(egg["next_meal_unix"]))
		eggs[creature_id] = egg
		var creature: Dictionary = creatures[creature_id]
		creature["sleeping"] = bool(creature.get("sleeping", false))
		creature["sleep_until_unix"] = maxi(0, int(creature.get("sleep_until_unix", 0)))
		if bool(creature["sleeping"]) and int(creature["sleep_until_unix"]) == 0:
			creature["sleep_until_unix"] = int(Time.get_unix_time_from_system()) + SLEEP_DURATION_SECONDS
		creature["ready_to_sleep"] = bool(creature.get("ready_to_sleep", false))
		creature["meal_bites"] = clampi(int(creature.get("meal_bites", 0)), 0, CREATURE_MEAL_CAPACITY)
		creature["next_meal_unix"] = maxi(0, int(creature.get("next_meal_unix", 0)))
		creature["poop_due_unix"] = maxi(0, int(creature.get("poop_due_unix", 0)))
		creature["poops_waiting"] = maxi(0, int(creature.get("poops_waiting", 0)))
		creature.erase("care_actions_since_poop")
		creatures[creature_id] = creature
	for key in ["pending_disappearance", "creature_a_disappeared", "dialogue_active", "player_place_shown", "first_absence_sequence_played"]:
		if not flags.has(key):
			flags[key] = false
