class_name PoopController
extends Control

signal clean_requested(poop: PoopController)

var owner_id := ""
var cursor_manager: CursorManager
var _click_flash := 0.0


func setup(creature_id: String, manager: CursorManager) -> void:
	owner_id = creature_id
	cursor_manager = manager


func _ready() -> void:
	custom_minimum_size = Vector2(18, 18)
	size = Vector2(18, 18)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void: cursor_manager.set_hover("poop"))
	mouse_exited.connect(func() -> void: cursor_manager.clear_hover("poop"))
	gui_input.connect(_on_gui_input)


func _process(delta: float) -> void:
	_click_flash = maxf(0.0, _click_flash - delta)
	if _click_flash > 0.0:
		queue_redraw()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if cursor_manager.selected_tool == "clean":
			_click_flash = 0.18
			queue_redraw()
			await get_tree().create_timer(0.1).timeout
			if not is_inside_tree():
				return
			clean_requested.emit(self)


func _draw() -> void:
	var dark := Color("#8B756E")
	draw_circle(Vector2(9, 12), 6, dark)
	draw_circle(Vector2(8, 7), 4, dark.lightened(0.08))
	draw_circle(Vector2(9, 3), 2, dark.lightened(0.15))
	draw_rect(Rect2(5, 10, 2, 2), Color("#FFF3DE"))
	draw_rect(Rect2(11, 10, 2, 2), Color("#FFF3DE"))
	if _click_flash > 0.0:
		var strength := clampf(_click_flash / 0.18, 0.0, 1.0)
		var glow := Color(1.0, 0.78, 0.28, strength)
		draw_arc(Vector2(9, 9), 10.0 + (1.0 - strength) * 3.0, 0, TAU, 18, glow, 2.0)
