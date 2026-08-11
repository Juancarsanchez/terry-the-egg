class_name SymbolBubble
extends Control

signal symbol_pressed(symbol_id: String)

const REACTION_SHEET: Texture2D = preload("res://assets/ui/reaction-symbols.png")
const ACTION_SHEET: Texture2D = preload("res://assets/ui/action-icons.png")
const TALK_ICON: Texture2D = preload("res://assets/ui/terry-talk.png")
const REACTION_CELL := Vector2(320, 320)
const ACTION_CELL := Vector2(256, 256)
const SYMBOL_CELLS := {
	"heart": Vector2i(0, 0),
	"no": Vector2i(1, 0),
	"question": Vector2i(2, 0),
	"ellipsis": Vector2i(3, 0),
	"exclamation": Vector2i(0, 1),
	"eye": Vector2i(1, 1),
	"sad": Vector2i(2, 1),
	"hatch": Vector2i(3, 1)
}
const TOOL_SYMBOL_CELLS := {
	"pet_request": Vector2i(1, 0),
	"egg_food": Vector2i(2, 0),
	"creature_food": Vector2i(3, 0),
	"play": Vector2i(4, 0),
	"sleep": Vector2i(5, 0),
	"dirty": Vector2i(6, 0),
	"sick": Vector2i(7, 0)
}

var current_symbol := ""
var current_priority := -1
var remaining := 0.0
var persistent := false
var sequence: Array[String] = []
var sequence_duration := 1.0
var icon: TextureRect
var _pulse_time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(32, 22)
	size = Vector2(32, 22)
	gui_input.connect(_on_gui_input)
	icon = TextureRect.new()
	icon.position = Vector2(8, 0)
	icon.size = Vector2(16, 16)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.pivot_offset = Vector2(8, 8)
	add_child(icon)
	hide()


func _on_gui_input(event: InputEvent) -> void:
	if (
		current_symbol == "talk"
		and event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	):
		accept_event()
		symbol_pressed.emit(current_symbol)


func _process(delta: float) -> void:
	if current_symbol == "":
		return
	if current_symbol == "talk":
		_pulse_time += delta
		var pulse := 1.0 + sin(_pulse_time * 3.2) * 0.06
		icon.scale = Vector2.ONE * pulse
		queue_redraw()
	else:
		icon.scale = Vector2.ONE
	if persistent:
		return
	remaining -= delta
	if remaining <= 0.0:
		if not sequence.is_empty():
			show_symbol(sequence.pop_front(), sequence_duration, current_priority)
		else:
			clear()


func show_symbol(symbol_id: String, duration: float = 2.0, priority: int = 10, keep: bool = false) -> bool:
	if current_symbol != "" and priority < current_priority:
		return false
	var symbol_texture := _texture_for_symbol(symbol_id)
	if symbol_texture == null:
		return false
	current_symbol = symbol_id
	current_priority = priority
	remaining = duration
	persistent = keep
	sequence_duration = maxf(0.05, sequence_duration)
	if symbol_id == "talk":
		icon.position = Vector2(6, -2)
		icon.size = Vector2(20, 20)
		icon.pivot_offset = Vector2(10, 10)
	else:
		icon.position = Vector2(8, 0)
		icon.size = Vector2(16, 16)
		icon.pivot_offset = Vector2(8, 8)
		icon.scale = Vector2.ONE
	icon.texture = symbol_texture
	show()
	queue_redraw()
	return true


func show_sequence(symbols: Array, duration_each: float = 0.7, priority: int = 20) -> void:
	if symbols.is_empty() or priority < current_priority:
		return
	sequence.clear()
	for symbol in symbols:
		sequence.append(str(symbol))
	sequence_duration = duration_each
	show_symbol(sequence.pop_front(), duration_each, priority)


func hide_symbol(symbol_id: String) -> void:
	if current_symbol == symbol_id:
		clear()


func clear() -> void:
	current_symbol = ""
	current_priority = -1
	persistent = false
	sequence.clear()
	if icon != null:
		icon.texture = null
	hide()


func _texture_for_symbol(symbol_id: String) -> Texture2D:
	if symbol_id == "talk":
		return TALK_ICON
	var atlas := AtlasTexture.new()
	atlas.filter_clip = true
	if TOOL_SYMBOL_CELLS.has(symbol_id):
		var tool_cell: Vector2i = TOOL_SYMBOL_CELLS[symbol_id]
		atlas.atlas = ACTION_SHEET
		atlas.region = Rect2(
			float(tool_cell.x) * ACTION_CELL.x,
			float(tool_cell.y) * ACTION_CELL.y,
			ACTION_CELL.x,
			ACTION_CELL.y
		)
		return atlas
	if not SYMBOL_CELLS.has(symbol_id):
		return null
	var cell: Vector2i = SYMBOL_CELLS[symbol_id]
	atlas.atlas = REACTION_SHEET
	atlas.region = Rect2(
		float(cell.x) * REACTION_CELL.x,
		float(cell.y) * REACTION_CELL.y,
		REACTION_CELL.x,
		REACTION_CELL.y
	)
	return atlas


func _draw() -> void:
	if current_symbol == "":
		return
	var fill := Color("#FFF8E8")
	var ink := Color("#4C4053")
	draw_circle(Vector2(8, 9), 8, fill)
	draw_circle(Vector2(24, 9), 8, fill)
	draw_rect(Rect2(8, 1, 16, 16), fill)
	draw_arc(Vector2(8, 9), 8, PI * 0.5, PI * 1.5, 10, ink, 1.5)
	draw_arc(Vector2(24, 9), 8, PI * 1.5, PI * 2.5, 10, ink, 1.5)
	draw_line(Vector2(8, 1), Vector2(24, 1), ink, 1.5)
	draw_line(Vector2(8, 17), Vector2(24, 17), ink, 1.5)
	draw_colored_polygon(PackedVector2Array([
		Vector2(13, 17), Vector2(19, 17), Vector2(16, 22)
	]), ink)
