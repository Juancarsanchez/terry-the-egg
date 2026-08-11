class_name EggController
extends Control

signal rubbed(creature_id: String)
signal feed_dropped(creature_id: String)
signal hover_changed(kind: String, entered: bool)

const EGG_TEXTURES := {
	"creature_a": {
		"intact": preload("res://assets/eggs/states/pipo/intact.png"),
		"crack_25": preload("res://assets/eggs/states/pipo/break-25.png"),
		"crack_50": preload("res://assets/eggs/states/pipo/break-50.png"),
		"crack_75": preload("res://assets/eggs/states/pipo/break-75.png"),
		"hatching": preload("res://assets/eggs/states/pipo/hatching.png")
	},
	"creature_b": {
		"intact": preload("res://assets/eggs/states/mota/intact.png"),
		"crack_25": preload("res://assets/eggs/states/mota/break-25.png"),
		"crack_50": preload("res://assets/eggs/states/mota/break-50.png"),
		"crack_75": preload("res://assets/eggs/states/mota/break-75.png"),
		"hatching": preload("res://assets/eggs/states/mota/hatching.png")
	},
	"creature_main": {
		"intact": preload("res://assets/eggs/states/terry/intact.png"),
		"crack_25": preload("res://assets/eggs/states/terry/break-25.png"),
		"crack_50": preload("res://assets/eggs/states/terry/break-50.png"),
		"crack_75": preload("res://assets/eggs/states/terry/break-75.png"),
		"hatching": preload("res://assets/eggs/states/terry/hatching.png")
	}
}

var creature_id := ""
var tint := Color.WHITE
var visual_state := "intact"
var enabled := true
var cursor_manager: CursorManager
var bubble: SymbolBubble
var _rubbing := false
var _hovered := false
var _last_position := Vector2.ZERO
var _last_direction := Vector2.ZERO
var _gesture_distance := 0.0
var _bob := 0.0
var _care_flash := 0.0
var _click_flash := 0.0


func setup(id: String, color: Color, manager: CursorManager) -> void:
	creature_id = id
	tint = color
	cursor_manager = manager


func _ready() -> void:
	custom_minimum_size = Vector2(64, 78)
	size = Vector2(64, 78)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	bubble = SymbolBubble.new()
	bubble.position = Vector2(18, -8)
	add_child(bubble)


func _process(delta: float) -> void:
	_bob += delta
	_care_flash = maxf(0.0, _care_flash - delta)
	_click_flash = maxf(0.0, _click_flash - delta)
	queue_redraw()


func _on_mouse_entered() -> void:
	_hovered = true
	cursor_manager.set_hover("egg")
	hover_changed.emit("egg", true)
	queue_redraw()


func _on_mouse_exited() -> void:
	_hovered = false
	_rubbing = false
	cursor_manager.set_rubbing(false)
	cursor_manager.clear_hover("egg")
	hover_changed.emit("egg", false)
	queue_redraw()


func _on_gui_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_click_flash = 0.24
			queue_redraw()
		if event.pressed and cursor_manager.selected_tool == "":
			_rubbing = true
			_last_position = event.position
			_last_direction = Vector2.ZERO
			_gesture_distance = 0.0
			cursor_manager.set_rubbing(true)
		elif not event.pressed:
			if cursor_manager.selected_tool == "food":
				feed_dropped.emit(creature_id)
			_rubbing = false
			cursor_manager.set_rubbing(false)
	elif event is InputEventMouseMotion and _rubbing:
		var movement: Vector2 = event.position - _last_position
		_last_position = event.position
		if movement.length() < 1.0:
			return
		var direction: Vector2 = movement.normalized()
		_gesture_distance += movement.length()
		var reversed: bool = _last_direction != Vector2.ZERO and direction.dot(_last_direction) < 0.2
		if reversed and _gesture_distance >= 12.0:
			_gesture_distance = 0.0
			rubbed.emit(creature_id)
		_last_direction = direction


func set_visual_state(new_state: String) -> void:
	visual_state = new_state
	if new_state == "open":
		enabled = false
	queue_redraw()


func show_care_feedback(symbol_id: String = "heart") -> void:
	_care_flash = 0.35
	bubble.show_symbol(symbol_id, 0.65, 70)
	queue_redraw()


static func texture_for_state(id: String, state: String) -> Texture2D:
	var creature_textures: Dictionary = EGG_TEXTURES.get(id, EGG_TEXTURES["creature_main"])
	return creature_textures.get(state, creature_textures["intact"]) as Texture2D


func _draw() -> void:
	var bob_y := sin(_bob * 2.0) if visual_state == "intact" else 0.0
	var center := Vector2(32, 43 + bob_y)
	_draw_ellipse_shape(center + Vector2(0, 27), Vector2(24, 5), Color(0.18, 0.24, 0.17, 0.18))
	if cursor_manager != null and cursor_manager.selected_tool == "food":
		var pulse := 1.5 + sin(_bob * 7.0) * 0.8
		draw_arc(center, 28 + pulse, 0, TAU, 32, Color("#F4C452"), 2.0)
		draw_arc(center, 31 + pulse, 0, TAU, 32, Color(1, 0.96, 0.72, 0.65), 1.0)

	if visual_state == "open":
		draw_arc(center + Vector2(0, 12), 22, 0, PI, 20, Color("#4C4053"), 3.0)
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(-21, 12), center + Vector2(-13, 24),
			center + Vector2(-3, 15), center + Vector2(7, 24),
			center + Vector2(21, 12)
		]), tint.lightened(0.1))
		return

	var egg_texture := texture_for_state(creature_id, visual_state)
	draw_texture_rect(egg_texture, Rect2(0, bob_y, 64, 78), false)
	if _care_flash > 0.0:
		_draw_warmth_sparkles(center)
	if _click_flash > 0.0:
		_draw_click_flash(center)


func _draw_ellipse_shape(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 32:
		var angle := TAU * float(i) / 32.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)


func _draw_warmth_sparkles(center: Vector2) -> void:
	var strength := clampf(_care_flash / 0.35, 0.0, 1.0)
	var glow := Color(1.0, 0.78, 0.28, strength)
	var cream := Color(1.0, 0.95, 0.78, strength)
	for data in [
		[center + Vector2(-25, -15), 4.0],
		[center + Vector2(25, -12), 3.5],
		[center + Vector2(0, -31), 3.0]
	]:
		var point: Vector2 = data[0]
		var radius: float = data[1]
		draw_colored_polygon(PackedVector2Array([
			point + Vector2(0, -radius),
			point + Vector2(radius * 0.45, -radius * 0.45),
			point + Vector2(radius, 0),
			point + Vector2(radius * 0.45, radius * 0.45),
			point + Vector2(0, radius),
			point + Vector2(-radius * 0.45, radius * 0.45),
			point + Vector2(-radius, 0),
			point + Vector2(-radius * 0.45, -radius * 0.45)
		]), glow)
		draw_circle(point, radius * 0.35, cream)


func _draw_click_flash(center: Vector2) -> void:
	var strength := clampf(_click_flash / 0.24, 0.0, 1.0)
	var radius := 27.0 + (1.0 - strength) * 5.0
	var glow := Color(1.0, 0.78, 0.28, strength)
	draw_arc(center, radius, 0, TAU, 28, glow, 2.0)
	for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(center + direction * (radius + 1.0), center + direction * (radius + 4.0), glow, 1.5)
