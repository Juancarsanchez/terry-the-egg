class_name SymbolBubble
extends Control

const EXPRESSION_SHEET: Texture2D = preload("res://assets/ui/expression-symbols.png")
const TOOL_SHEET: Texture2D = preload("res://assets/ui/tool-cursors.png")
const EXPRESSION_CELL := Vector2(313.5, 313.5)
const TOOL_CELL := Vector2(418, 418)
const SYMBOL_CELLS := {
	"food": Vector2i(0, 0),
	"play": Vector2i(1, 0),
	"sleep": Vector2i(2, 0),
	"dirty": Vector2i(3, 0),
	"sick": Vector2i(0, 1),
	"heart": Vector2i(1, 1),
	"empty_heart": Vector2i(1, 1),
	"pet": Vector2i(1, 1),
	"no": Vector2i(2, 1),
	"full": Vector2i(3, 1),
	"question": Vector2i(0, 2),
	"exclamation": Vector2i(1, 2),
	"ellipsis": Vector2i(2, 2),
	"sad": Vector2i(3, 2),
	"happy": Vector2i(0, 3),
	"surprise": Vector2i(1, 3),
	"eye": Vector2i(2, 3),
	"hatch": Vector2i(3, 3)
}

var current_symbol := ""
var current_priority := -1
var remaining := 0.0
var persistent := false
var sequence: Array[String] = []
var sequence_duration := 1.0
var icon: TextureRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(32, 22)
	size = Vector2(32, 22)
	icon = TextureRect.new()
	icon.position = Vector2(8, 0)
	icon.size = Vector2(16, 16)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)
	hide()


func _process(delta: float) -> void:
	if current_symbol == "" or persistent:
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


func _texture_for_symbol(symbol_id: String) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	if symbol_id == "pet_request":
		atlas.atlas = TOOL_SHEET
		atlas.region = Rect2(TOOL_CELL.x, 0, TOOL_CELL.x, TOOL_CELL.y)
		return atlas
	if not SYMBOL_CELLS.has(symbol_id):
		return null
	var cell: Vector2i = SYMBOL_CELLS[symbol_id]
	atlas.atlas = EXPRESSION_SHEET
	atlas.region = Rect2(
		float(cell.x) * EXPRESSION_CELL.x,
		float(cell.y) * EXPRESSION_CELL.y,
		EXPRESSION_CELL.x,
		EXPRESSION_CELL.y
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
