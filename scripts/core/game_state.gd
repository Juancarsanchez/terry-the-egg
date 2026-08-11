class_name TerryGameState
extends RefCounted

signal changed

const CREATURE_IDS := ["creature_a", "creature_b", "creature_main"]
const NEED_NAMES := ["satiety", "hygiene", "energy", "fun", "affection", "health"]
const SAVE_VERSION := 5
const EGG_CARE_REQUIRED := 12
const EGG_CARE_CAPACITY := 3
const EGG_CARE_INTERVAL_SECONDS := 5 * 60
const EGG_NUTRITION_REQUIRED := 4
const EGG_MEAL_CAPACITY := 2
const EGG_MEAL_INTERVAL_SECONDS := 60 * 60
const CREATURE_MEAL_CAPACITY := 2
const CREATURE_MEAL_INTERVAL_SECONDS := 60 * 60
const SLEEP_DURATION_SECONDS := 60 * 60
const PLAY_DURATION_SECONDS := 60 * 60
const POOP_DELAY_SECONDS := 2 * 60 * 60
const NEWBORN_REQUEST_DELAY_SECONDS := 15 * 60
const ROUTINE_REQUEST_DELAY_SECONDS := 60 * 60
const REQUEST_GRACE_SECONDS := 30 * 60
const FIRST_DAY_SECONDS := 8 * 60 * 60

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
			"care": 0.0,
			"care_required": float(EGG_CARE_REQUIRED),
			"care_strokes": 0,
			"next_care_unix": 0,
			"nutrition": 0.0,
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
			"born_unix": 0,
			"sleeping": false,
			"sleep_until_unix": 0,
			"activity": "",
			"activity_until_unix": 0,
			"ready_to_sleep": false,
			"request": "",
			"request_started_unix": 0,
			"request_deadline_unix": 0,
			"next_request_unix": 0,
			"request_cycle_index": 0,
			"care_cycles": 0,
			"missed_requests": 0,
			"favorite_care": 0,
			"body_state": "normal",
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
		"answers_chosen": 0,
		"sleep_cycles_since_talk": 0,
		"care_cycles_since_talk": 0,
		"care_cycles_completed": 0,
		"neglected_requests": 0,
		"care_cycles_at_first_voice": 0,
		"final_feed_count": 0
	}
	dialogues_seen.clear()
	answers.clear()
	unlocks = ["feed", "status"]
	flags = {
		"pending_disappearance": false,
		"absence_waiting_for_return": false,
		"absence_return_ready": false,
		"absence_reveal_active": false,
		"creature_a_disappeared": false,
		"creature_b_disappeared": false,
		"dialogue_active": false,
		"player_place_shown": false,
		"first_absence_sequence_played": false,
		"pending_mota_disappearance": false,
		"pending_talk_id": "",
		"first_voice_triggered": false,
		"first_neglected_creature": "",
		"true_ending_seen": false
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
	var now := int(Time.get_unix_time_from_system())
	creatures[creature_id]["born_unix"] = now
	creatures[creature_id]["next_request_unix"] = now + NEWBORN_REQUEST_DELAY_SECONDS
	changed.emit()


func complete_care_cycle(creature_id: String, action: String) -> void:
	if not creatures.has(creature_id):
		return
	var creature: Dictionary = creatures[creature_id]
	creature["care_cycles"] = int(creature.get("care_cycles", 0)) + 1
	global_counters["care_cycles_completed"] = int(global_counters.get("care_cycles_completed", 0)) + 1
	global_counters["care_cycles_since_talk"] = int(global_counters.get("care_cycles_since_talk", 0)) + 1
	if action in ["fed", "slept"] and creature_id == "creature_a":
		creature["favorite_care"] = int(creature.get("favorite_care", 0)) + 1
	elif action == "played" and creature_id == "creature_b":
		creature["favorite_care"] = int(creature.get("favorite_care", 0)) + 1
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
		"save_version": SAVE_VERSION,
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
	var version := int(data.get("save_version", 0))
	if version < 1 or version > SAVE_VERSION:
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
	for counter_name in [
		"sleep_cycles_since_talk",
		"care_cycles_since_talk",
		"care_cycles_completed",
		"neglected_requests",
		"care_cycles_at_first_voice",
		"final_feed_count"
	]:
		if not global_counters.has(counter_name):
			global_counters[counter_name] = 0
	for creature_id in CREATURE_IDS:
		if not eggs.has(creature_id) or not creatures.has(creature_id):
			reset_all()
			return
		var egg: Dictionary = eggs[creature_id]
		if not egg.has("care"):
			var old_heat := float(egg.get("heat", 0.0))
			var old_heat_required := maxf(1.0, float(egg.get("heat_required", 5.0)))
			egg["care"] = roundf((old_heat / old_heat_required) * float(EGG_CARE_REQUIRED))
		egg["care"] = clampf(float(egg.get("care", 0.0)), 0.0, float(EGG_CARE_REQUIRED))
		egg["care_required"] = float(EGG_CARE_REQUIRED)
		egg["care_strokes"] = clampi(int(egg.get("care_strokes", 0)), 0, EGG_CARE_CAPACITY)
		egg["next_care_unix"] = maxi(0, int(egg.get("next_care_unix", 0)))
		egg.erase("heat")
		egg.erase("heat_required")
		var old_nutrition := float(egg.get("nutrition", 0.0))
		var old_nutrition_required := maxf(1.0, float(egg.get("nutrition_required", EGG_NUTRITION_REQUIRED)))
		if old_nutrition_required > float(EGG_NUTRITION_REQUIRED):
			old_nutrition = roundf((old_nutrition / old_nutrition_required) * float(EGG_NUTRITION_REQUIRED))
		egg["nutrition"] = clampf(old_nutrition, 0.0, float(EGG_NUTRITION_REQUIRED))
		egg["nutrition_required"] = float(EGG_NUTRITION_REQUIRED)
		if not egg.has("meal_bites"):
			egg["meal_bites"] = 0
		else:
			egg["meal_bites"] = clampi(int(egg["meal_bites"]), 0, EGG_MEAL_CAPACITY)
		if not egg.has("next_meal_unix"):
			egg["next_meal_unix"] = 0
		else:
			egg["next_meal_unix"] = maxi(0, int(egg["next_meal_unix"]))
		if not bool(egg.get("hatched", false)):
			var care_ratio := float(egg["care"]) / float(EGG_CARE_REQUIRED)
			if care_ratio >= 0.75:
				egg["visual_state"] = "crack_75"
			elif care_ratio >= 0.5:
				egg["visual_state"] = "crack_50"
			elif care_ratio >= 0.25:
				egg["visual_state"] = "crack_25"
			else:
				egg["visual_state"] = "intact"
		eggs[creature_id] = egg
		var creature: Dictionary = creatures[creature_id]
		creature["born_unix"] = maxi(0, int(creature.get("born_unix", 0)))
		if bool(creature.get("present", false)) and int(creature["born_unix"]) == 0:
			creature["born_unix"] = int(Time.get_unix_time_from_system())
		creature["sleeping"] = bool(creature.get("sleeping", false))
		creature["sleep_until_unix"] = maxi(0, int(creature.get("sleep_until_unix", 0)))
		if bool(creature["sleeping"]) and int(creature["sleep_until_unix"]) == 0:
			creature["sleep_until_unix"] = int(Time.get_unix_time_from_system()) + SLEEP_DURATION_SECONDS
		creature["ready_to_sleep"] = bool(creature.get("ready_to_sleep", false))
		creature["activity"] = str(creature.get("activity", ""))
		creature["activity_until_unix"] = maxi(0, int(creature.get("activity_until_unix", 0)))
		if bool(creature["sleeping"]):
			creature["activity"] = "sleep"
			creature["activity_until_unix"] = int(creature["sleep_until_unix"])
		creature["request"] = str(creature.get("request", ""))
		creature["request_started_unix"] = maxi(0, int(creature.get("request_started_unix", 0)))
		creature["request_deadline_unix"] = maxi(0, int(creature.get("request_deadline_unix", 0)))
		creature["next_request_unix"] = maxi(0, int(creature.get("next_request_unix", 0)))
		if (
			bool(creature.get("present", false))
			and str(creature["request"]) == ""
			and str(creature["activity"]) == ""
			and int(creature["next_request_unix"]) == 0
		):
			creature["next_request_unix"] = int(Time.get_unix_time_from_system()) + ROUTINE_REQUEST_DELAY_SECONDS
		creature["request_cycle_index"] = maxi(0, int(creature.get("request_cycle_index", 0)))
		creature["care_cycles"] = maxi(0, int(creature.get("care_cycles", 0)))
		creature["missed_requests"] = maxi(0, int(creature.get("missed_requests", 0)))
		creature["favorite_care"] = maxi(0, int(creature.get("favorite_care", 0)))
		creature["body_state"] = str(creature.get("body_state", "normal"))
		creature["meal_bites"] = clampi(int(creature.get("meal_bites", 0)), 0, CREATURE_MEAL_CAPACITY)
		creature["next_meal_unix"] = maxi(0, int(creature.get("next_meal_unix", 0)))
		creature["poop_due_unix"] = maxi(0, int(creature.get("poop_due_unix", 0)))
		creature["poops_waiting"] = maxi(0, int(creature.get("poops_waiting", 0)))
		creature.erase("care_actions_since_poop")
		creatures[creature_id] = creature
	for key in [
		"pending_disappearance",
		"absence_waiting_for_return",
		"absence_return_ready",
		"absence_reveal_active",
		"creature_a_disappeared",
		"creature_b_disappeared",
		"dialogue_active",
		"player_place_shown",
		"first_absence_sequence_played",
		"pending_mota_disappearance",
		"first_voice_triggered",
		"true_ending_seen"
	]:
		if not flags.has(key):
			flags[key] = false
	if not flags.has("pending_talk_id"):
		flags["pending_talk_id"] = ""
	if not flags.has("first_neglected_creature"):
		flags["first_neglected_creature"] = ""
