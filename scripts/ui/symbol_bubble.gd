class_name SymbolBubble
extends Control

const GLYPHS := {
	"food": "YUM",
	"play": "♪",
	"sleep": "Zz",
	"dirty": "!",
	"sick": "+",
	"heart": "♥",
	"empty_heart": "♡",
	"no": "X",
	"full": "OK",
	"pet": "<3",
	"question": "?",
	"exclamation": "!",
	"ellipsis": "...",
	"sad": "↓",
	"happy": "↑",
	"surprise": "!",
	"eye": "●"
}

var current_symbol := ""
var current_priority := -1
var remaining := 0.0
var persistent := false
var sequence: Array[String] = []
var sequence_duration := 1.0
var label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(32, 22)
	size = Vector2(32, 22)
	label = Label.new()
	label.position = Vector2(1, 0)
	label.size = Vector2(30, 17)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color("#4C4053"))
	add_child(label)
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
	current_symbol = symbol_id
	current_priority = priority
	remaining = duration
	persistent = keep
	sequence_duration = maxf(0.05, sequence_duration)
	label.text = str(GLYPHS.get(symbol_id, symbol_id))
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
	hide()


func _draw() -> void:
	if current_symbol == "":
		return
	draw_circle(Vector2(8, 9), 8, Color("#FFF8E8"))
	draw_circle(Vector2(24, 9), 8, Color("#FFF8E8"))
	draw_rect(Rect2(8, 1, 16, 16), Color("#FFF8E8"))
	draw_arc(Vector2(8, 9), 8, PI * 0.5, PI * 1.5, 10, Color("#4C4053"), 1.5)
	draw_arc(Vector2(24, 9), 8, PI * 1.5, PI * 2.5, 10, Color("#4C4053"), 1.5)
	draw_line(Vector2(8, 1), Vector2(24, 1), Color("#4C4053"), 1.5)
	draw_line(Vector2(8, 17), Vector2(24, 17), Color("#4C4053"), 1.5)
	draw_colored_polygon(PackedVector2Array([
		Vector2(13, 17), Vector2(19, 17), Vector2(16, 22)
	]), Color("#4C4053"))
