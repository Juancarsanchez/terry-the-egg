class_name DialogueManager
extends RefCounted

signal node_requested(dialogue_id: String, node_id: String, node: Dictionary)
signal dialogue_finished(dialogue_id: String)

var dialogues: Dictionary = {}
var current_dialogue := ""
var current_node := ""


func _init(path: String = "res://data/dialogues/dialogues.json") -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("No se pudieron cargar los diálogos")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		dialogues = parsed


func start(dialogue_id: String, state: TerryGameState) -> bool:
	if not dialogues.has(dialogue_id):
		return false
	var dialogue: Dictionary = dialogues[dialogue_id]
	if bool(dialogue.get("once", false)) and dialogue_id in state.dialogues_seen:
		return false
	current_dialogue = dialogue_id
	current_node = str(dialogue.get("start", ""))
	state.flags["dialogue_active"] = true
	emit_current()
	return true


func choose_option(index: int, state: TerryGameState) -> void:
	if current_dialogue == "":
		return
	var node: Dictionary = dialogues[current_dialogue]["nodes"][current_node]
	var options: Array = node.get("options", [])
	if index < 0 or index >= options.size():
		return
	var option: Dictionary = options[index]
	var answer_key := str(node.get("answer_key", ""))
	if answer_key != "":
		state.set_answer(answer_key, str(option.get("value", "")))
	current_node = str(option.get("next", ""))
	emit_current()


func continue_node(state: TerryGameState) -> void:
	if current_dialogue == "":
		return
	var node: Dictionary = dialogues[current_dialogue]["nodes"][current_node]
	current_node = str(node.get("next", ""))
	if current_node == "":
		finish(state)
	else:
		emit_current()


func emit_current() -> void:
	if current_dialogue == "" or current_node == "":
		return
	var node: Dictionary = dialogues[current_dialogue]["nodes"][current_node]
	node_requested.emit(current_dialogue, current_node, node)


func finish(state: TerryGameState) -> void:
	var finished_id := current_dialogue
	state.mark_dialogue_seen(finished_id)
	state.flags["dialogue_active"] = false
	current_dialogue = ""
	current_node = ""
	dialogue_finished.emit(finished_id)


func is_active() -> bool:
	return current_dialogue != ""
