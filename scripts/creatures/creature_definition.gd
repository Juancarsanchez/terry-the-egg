class_name CreatureDefinition
extends Resource

@export var creature_id: String
@export var display_name: String
@export var personality: String
@export var color: Color
@export var accent: Color
@export var shape: String
@export var decay: Dictionary
@export var request_symbols: Array[String]
@export var request_cycle: Array[String]
@export var favorite_actions: Array[String]
@export var silent_hunger: bool
@export var needs_pet_to_sleep: bool
@export var animation_speed: float = 1.0


static func load_all(path: String = "res://data/creatures/creatures.json") -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("No se pudo abrir " + path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("JSON de criaturas inválido")
		return {}
	var result := {}
	for creature_key in parsed:
		var raw: Dictionary = parsed[creature_key]
		var definition := CreatureDefinition.new()
		definition.creature_id = creature_key
		definition.display_name = str(raw.get("display_name", creature_key))
		definition.personality = str(raw.get("personality", ""))
		definition.color = Color.from_string(str(raw.get("color", "#FFFFFF")), Color.WHITE)
		definition.accent = Color.from_string(str(raw.get("accent", "#71677B")), Color("#71677B"))
		definition.shape = str(raw.get("shape", "round"))
		definition.decay = (raw.get("decay", {}) as Dictionary).duplicate(true)
		for symbol in raw.get("request_symbols", []):
			definition.request_symbols.append(str(symbol))
		for request_name in raw.get("request_cycle", []):
			definition.request_cycle.append(str(request_name))
		for action_name in raw.get("favorite_actions", []):
			definition.favorite_actions.append(str(action_name))
		definition.silent_hunger = bool(raw.get("silent_hunger", false))
		definition.needs_pet_to_sleep = bool(raw.get("needs_pet_to_sleep", false))
		definition.animation_speed = float(raw.get("animation_speed", 1.0))
		result[creature_key] = definition
	return result
