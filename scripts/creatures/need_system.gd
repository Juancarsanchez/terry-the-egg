class_name NeedSystem
extends RefCounted

const OFFLINE_CAP_SECONDS := 12.0 * 60.0 * 60.0
const OFFLINE_RATE_MULTIPLIER := 0.08


func tick_creature(creature: Dictionary, definition: CreatureDefinition, delta: float) -> void:
	if bool(creature.get("sleeping", false)):
		creature["needs"]["energy"] = minf(100.0, float(creature["needs"]["energy"]) + 4.0 * delta)
		return
	var activity := str(creature.get("activity", ""))
	if activity == "play":
		creature["needs"]["fun"] = 100.0
	for need_name in definition.decay:
		if need_name == "health":
			continue
		var rate := float(definition.decay[need_name])
		if activity == "play" and need_name == "fun":
			continue
		if activity == "play" and need_name == "satiety":
			rate *= 1.25
		creature["needs"][need_name] = maxf(0.0, float(creature["needs"][need_name]) - rate * delta)
	var critical_count := 0
	for need_name in ["satiety", "hygiene", "energy", "fun", "affection"]:
		if float(creature["needs"][need_name]) <= 0.0:
			critical_count += 1
	if critical_count > 0:
		creature["needs"]["health"] = maxf(25.0, float(creature["needs"]["health"]) - 0.01 * critical_count * delta)


func apply_offline_decay(state: TerryGameState, definitions: Dictionary, elapsed_seconds: float) -> void:
	var capped := minf(maxf(elapsed_seconds, 0.0), OFFLINE_CAP_SECONDS)
	var now := int(Time.get_unix_time_from_system())
	for creature_id in TerryGameState.CREATURE_IDS:
		var creature: Dictionary = state.creatures[creature_id]
		if not bool(creature.get("present", false)) or bool(creature.get("disappeared", false)):
			continue
		var decay_seconds := capped
		if bool(creature.get("sleeping", false)):
			var sleep_until := int(creature.get("sleep_until_unix", 0))
			creature["needs"]["energy"] = 100.0
			if sleep_until > now:
				continue
			decay_seconds = minf(capped, maxf(0.0, float(now - sleep_until)))
		var definition: CreatureDefinition = definitions[creature_id]
		for need_name in definition.decay:
			if need_name == "health":
				continue
			var loss := float(definition.decay[need_name]) * decay_seconds * OFFLINE_RATE_MULTIPLIER
			creature["needs"][need_name] = maxf(20.0, float(creature["needs"][need_name]) - loss)


func apply_action(creature: Dictionary, action: String) -> void:
	match action:
		"fed":
			creature["needs"]["satiety"] = minf(100.0, float(creature["needs"]["satiety"]) + 32.0)
		"played":
			creature["needs"]["fun"] = minf(100.0, float(creature["needs"]["fun"]) + 30.0)
			creature["needs"]["affection"] = minf(100.0, float(creature["needs"]["affection"]) + 6.0)
		"petted":
			creature["needs"]["affection"] = minf(100.0, float(creature["needs"]["affection"]) + 14.0)
		"cleaned":
			creature["needs"]["hygiene"] = minf(100.0, float(creature["needs"]["hygiene"]) + 36.0)
