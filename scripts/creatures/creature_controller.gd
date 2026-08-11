class_name CreatureController
extends Control

signal action_requested(creature_id: String, action: String)
signal hover_changed(kind: String, entered: bool)

const CREATURE_SHEET: Texture2D = preload("res://assets/creatures/creature-sprites.png")
const REACTION_SHEET: Texture2D = preload("res://assets/creatures/creature-reactions.png")
const PIPO_CHUBBY: Texture2D = preload("res://assets/creatures/pipo-chubby.png")
const SPRITE_CELL_SIZE := 418.0
const REACTION_ROW_HEIGHT := 460.0
const INK := Color("#4C4053")
const EYE_GOLD := Color("#F4C452")

var definition: CreatureDefinition
var cursor_manager: CursorManager
var bubble: SymbolBubble
var state_name := "idle"
var sleeping := false
var activity := ""
var body_state := "normal"
var _petting := false
var _hovered := false
var _pet_distance := 0.0
var _last_position := Vector2.ZERO
var _animation_time := 0.0
var _reaction_time := 0.0
var _click_flash := 0.0


func setup(def: CreatureDefinition, manager: CursorManager) -> void:
	definition = def
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
	_animation_time += delta * definition.animation_speed
	_click_flash = maxf(0.0, _click_flash - delta)
	if _reaction_time > 0.0:
		_reaction_time -= delta
		if _reaction_time <= 0.0 and not sleeping:
			state_name = "play" if activity == "play" else "idle"
	queue_redraw()


func _on_mouse_entered() -> void:
	_hovered = true
	cursor_manager.set_hover("creature")
	hover_changed.emit("creature", true)
	queue_redraw()


func _on_mouse_exited() -> void:
	_hovered = false
	_petting = false
	cursor_manager.set_rubbing(false)
	cursor_manager.clear_hover("creature")
	hover_changed.emit("creature", false)
	queue_redraw()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_click_flash = 0.24
			queue_redraw()
		if event.pressed:
			if cursor_manager.selected_tool == "":
				_petting = true
				_last_position = event.position
				_pet_distance = 0.0
				cursor_manager.set_rubbing(true)
			elif cursor_manager.selected_tool != "food":
				action_requested.emit(definition.creature_id, cursor_manager.selected_tool)
		else:
			if cursor_manager.selected_tool == "food":
				action_requested.emit(definition.creature_id, "food")
			_petting = false
			cursor_manager.set_rubbing(false)
	elif event is InputEventMouseMotion and _petting:
		var movement: Vector2 = event.position - _last_position
		_last_position = event.position
		_pet_distance += movement.length()
		if _pet_distance >= 18.0:
			_pet_distance = 0.0
			action_requested.emit(definition.creature_id, "pet")
			bubble.show_symbol("heart", 0.45, 28)


func react(animation: String, symbol: String = "", duration: float = 0.8) -> void:
	if sleeping:
		if symbol != "":
			bubble.show_symbol(symbol, duration, 90 if animation == "refuse" else 25)
		return
	state_name = animation
	_reaction_time = duration
	if symbol != "":
		bubble.show_symbol(symbol, duration, 90 if animation == "refuse" else 25)


func set_sleeping(value: bool) -> void:
	sleeping = value
	state_name = "sleep" if value else "wake"
	_reaction_time = 0.7 if not value else 0.0
	if value:
		bubble.show_symbol("sleep", 3600.0, 35, true)
	else:
		bubble.hide_symbol("sleep")


func set_activity(value: String, until_unix: int = 0) -> void:
	activity = value
	if value == "play":
		state_name = "play"
		_reaction_time = 0.0
	elif value == "sleep":
		set_sleeping(true)
	elif not sleeping:
		state_name = "idle"
		_reaction_time = 0.0
	queue_redraw()


func set_body_state(value: String) -> void:
	body_state = value
	queue_redraw()


func _draw() -> void:
	var bob := 0.0 if sleeping else sin(_animation_time * 3.0) * 1.5
	var sprite_rect := Rect2(1, 7 + bob, 62, 62)
	if sleeping:
		sprite_rect.position.y += 5
		sprite_rect.size.y -= 3
	var center := Vector2(32, sprite_rect.end.y - 4)
	draw_body_ellipse(center, Vector2(24, 4), Color(0.18, 0.24, 0.17, 0.18))
	var texture := CREATURE_SHEET
	var source := Rect2(
		_sprite_column() * SPRITE_CELL_SIZE,
		_sprite_row() * SPRITE_CELL_SIZE,
		SPRITE_CELL_SIZE,
		SPRITE_CELL_SIZE
	)
	var uses_chubby_asset := (
		definition.creature_id == "creature_a"
		and body_state == "chubby"
		and not sleeping
		and state_name not in ["play", "eat", "refuse"]
	)
	var uses_reaction_asset := sleeping or state_name == "refuse"
	if uses_chubby_asset:
		texture = PIPO_CHUBBY
		source = Rect2(Vector2.ZERO, PIPO_CHUBBY.get_size())
	if uses_reaction_asset:
		texture = REACTION_SHEET
		var reaction_y := 125.0 if sleeping else 600.0
		source = Rect2(
			_sprite_column() * SPRITE_CELL_SIZE,
			reaction_y,
			SPRITE_CELL_SIZE,
			REACTION_ROW_HEIGHT
		)
	draw_texture_rect_region(texture, sprite_rect, source)
	if not uses_reaction_asset and not uses_chubby_asset:
		_draw_eye_expression(sprite_rect)
	if _click_flash > 0.0:
		_draw_click_flash(Vector2(32, 39 + bob))


func _sprite_column() -> int:
	match definition.creature_id:
		"creature_b":
			return 1
		"creature_main":
			return 2
	return 0


func _sprite_row() -> int:
	if state_name == "play":
		return 1
	if state_name == "eat":
		return 2
	return 0


func _draw_eye_expression(sprite_rect: Rect2) -> void:
	var expression := _eye_expression()
	if expression == "normal":
		return
	var left_eye := sprite_rect.position + Vector2(sprite_rect.size.x * 0.425, sprite_rect.size.y * 0.34)
	var right_eye := sprite_rect.position + Vector2(sprite_rect.size.x * 0.59, sprite_rect.size.y * 0.34)
	if expression == "closed":
		for eye in [left_eye, right_eye]:
			_draw_body_ellipse(eye, Vector2(4.7, 3.8), definition.color)
			draw_arc(eye + Vector2(0, 0.8), 3.2, 0.15, PI - 0.15, 8, INK, 1.5)
		return
	for eye in [left_eye, right_eye]:
		draw_circle(eye, 4.8, INK)
		draw_circle(eye, 3.5, EYE_GOLD)
		draw_circle(eye, 0.8, Color("#17111A"))


func _eye_expression() -> String:
	if sleeping:
		return "normal"
	if state_name == "blink":
		return "closed"
	if state_name in ["first_word", "look_at_player", "terrible"]:
		return "pinprick"
	if state_name == "idle" and fmod(_animation_time, 5.5) > 5.3:
		return "closed"
	return "normal"


func _draw_body_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	draw_body_ellipse(center, radius, color)


func draw_body_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 24:
		var angle := TAU * float(i) / 24.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)


func _draw_click_flash(center: Vector2) -> void:
	var strength := clampf(_click_flash / 0.24, 0.0, 1.0)
	var radius := 28.0 + (1.0 - strength) * 5.0
	var glow := Color(1.0, 0.78, 0.28, strength)
	draw_arc(center, radius, 0, TAU, 28, glow, 2.0)
	for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(center + direction * (radius + 1.0), center + direction * (radius + 4.0), glow, 1.5)
