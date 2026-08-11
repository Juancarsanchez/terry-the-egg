class_name CursorManager
extends Node

signal tool_changed(tool_id: String)

const CURSOR_SHEET: Texture2D = preload("res://assets/ui/tool-cursors.png")
const TALK_ICON: Texture2D = preload("res://assets/ui/terry-talk.png")
const CELL_SIZE := 418
const CURSOR_SIZE := 32
const CURSOR_CELLS := {
	"pet": Vector2i(0, 0),
	"rub": Vector2i(1, 0),
	"egg_food": Vector2i(2, 0),
	"food": Vector2i(0, 1),
	"play": Vector2i(1, 1),
	"sleep": Vector2i(2, 1),
	"clean": Vector2i(0, 2),
	"status": Vector2i(1, 2),
	"forbidden": Vector2i(2, 2)
}

var selected_tool := ""
var hover_kind := ""
var _textures: Dictionary = {}
var _current_mode := ""


func _ready() -> void:
	var sheet_image := CURSOR_SHEET.get_image()
	for mode in CURSOR_CELLS:
		_textures[mode] = _extract_cursor(sheet_image, CURSOR_CELLS[mode])
	var talk_image := TALK_ICON.get_image()
	talk_image.resize(CURSOR_SIZE, CURSOR_SIZE, Image.INTERPOLATE_LANCZOS)
	_textures["talk"] = ImageTexture.create_from_image(talk_image)
	set_mode("arrow")


func select_tool(tool_id: String) -> void:
	selected_tool = tool_id
	refresh()
	tool_changed.emit(tool_id)


func cancel_tool() -> void:
	select_tool("")


func set_hover(kind: String) -> void:
	hover_kind = kind
	refresh()


func clear_hover(kind: String = "") -> void:
	if kind == "" or hover_kind == kind:
		hover_kind = ""
	refresh()


func set_rubbing(active: bool) -> void:
	if active:
		set_mode("rub")
	else:
		refresh()


func refresh() -> void:
	if selected_tool != "":
		if not is_valid_target(selected_tool, hover_kind) and hover_kind != "":
			set_mode("forbidden")
		elif selected_tool == "food" and hover_kind == "egg":
			set_mode("egg_food")
		else:
			set_mode(selected_tool)
	elif hover_kind == "creature":
		set_mode("pet")
	elif hover_kind == "egg":
		set_mode("rub")
	else:
		set_mode("arrow")


func is_valid_target(tool: String, target_kind: String) -> bool:
	match tool:
		"food":
			return target_kind in ["egg", "creature"]
		"clean":
			return target_kind == "poop"
		"play", "sleep", "status":
			return target_kind == "creature"
	return true


func set_mode(mode: String) -> void:
	if mode == _current_mode:
		return
	_current_mode = mode
	if mode == "arrow":
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
		return
	if not _textures.has(mode):
		return
	var hotspot := Vector2(16, 16)
	match mode:
		"pet":
			hotspot = Vector2(11, 18)
		"rub":
			hotspot = Vector2(16, 17)
		"egg_food":
			hotspot = Vector2(27, 24)
		"food":
			hotspot = Vector2(16, 23)
		"clean":
			hotspot = Vector2(14, 22)
		"status":
			hotspot = Vector2(22, 20)
		"talk":
			hotspot = Vector2(16, 16)
	Input.set_custom_mouse_cursor(_textures[mode], Input.CURSOR_ARROW, hotspot)


func get_cursor_texture(mode: String) -> Texture2D:
	return _textures.get(mode)


func _extract_cursor(sheet_image: Image, cell: Vector2i) -> ImageTexture:
	var region := Rect2i(cell.x * CELL_SIZE, cell.y * CELL_SIZE, CELL_SIZE, CELL_SIZE)
	var image := sheet_image.get_region(region)
	image.resize(CURSOR_SIZE, CURSOR_SIZE, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)
