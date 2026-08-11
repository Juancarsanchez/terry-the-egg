extends Control

const CREAM := Color("#FFF3DE")
const PINK := Color("#F5C6D6")
const PEACH := Color("#F6D0B1")
const SKY := Color("#BDDDF2")
const LAVENDER := Color("#CEC7EC")
const MINT := Color("#C9E7D2")
const BROWN := Color("#8B756E")
const SHADOW := Color("#71677B")
const INK := Color("#4C4053")
const CASE_CORAL := Color("#EF8F7E")
const CASE_LIGHT := Color("#FFC7A8")
const LCD := Color("#CDE6B8")
const LCD_DARK := Color("#A7CB99")
const WALLPAPER := Color("#8EC8C4")
const ENTITY_POSITIONS := [Vector2(10, 24), Vector2(94, 24), Vector2(178, 24)]
const ACTION_ICON_SHEET := "res://assets/ui/action-icons.png"
const ACTION_ICON_CELL_SIZE := 256
const GAME_FONT: FontFile = preload("res://assets/fonts/Silkscreen-Regular.ttf")
const PRE_ABSENCE_TALKS := ["chat_01", "chat_02", "chat_03", "chat_10", "chat_11", "chat_12"]

var game_state := TerryGameState.new()
var definitions: Dictionary
var need_system := NeedSystem.new()
var care_loop := CareLoopSystem.new()
var save_manager := SaveManager.new()
var progression := ProgressionDirector.new()
var prompt_system := RequirementPromptSystem.new()
var dialogue := DialogueManager.new()
var cursor_manager: CursorManager
var item_drag := ItemDragController.new()
var audio_manager: AudioManager

var arena: Control
var status_panel: Panel
var status_label: Label
var tool_label: Label
var action_buttons: Dictionary = {}
var action_icons: Dictionary = {}
var special_button: Button
var egg_nodes: Dictionary = {}
var creature_nodes: Dictionary = {}
var slot_nodes: Dictionary = {}
var empty_slot_markers: Dictionary = {}
var poop_nodes: Array[PoopController] = []
var dialogue_panel: Panel
var dialogue_speaker: Label
var dialogue_text: Label
var dialogue_options: HBoxContainer
var fade_overlay: ColorRect
var drag_preview: TextureRect
var debug_panel: Panel
var debug_text: Label
var start_backdrop: ColorRect
var start_panel: Panel
var continue_button: Button
var exit_backdrop: ColorRect
var exit_panel: Panel
var save_exit_button: Button
var status_backdrop: ColorRect
var status_window: Panel
var status_title: Label
var status_details: Label
var debug_target_index := 0
var _loaded_existing_save := false
var _game_started := false
var _quitting := false
var _tick_accumulator := 0.0
var _prompt_accumulator := 0.0
var _autosave_accumulator := 0.0
var _dialogue_generation := 0
var _absence_generation := 0
var _egg_request_alerted: Dictionary = {}


func _ready() -> void:
	get_tree().auto_accept_quit = false
	var game_theme := Theme.new()
	game_theme.default_font = GAME_FONT
	theme = game_theme
	definitions = CreatureDefinition.load_all()
	cursor_manager = CursorManager.new()
	add_child(cursor_manager)
	audio_manager = AudioManager.new()
	add_child(audio_manager)
	progression.phase_changed.connect(_on_phase_changed)
	progression.event_requested.connect(_on_progression_event)
	dialogue.node_requested.connect(_on_dialogue_node)
	dialogue.dialogue_finished.connect(_on_dialogue_finished)
	cursor_manager.tool_changed.connect(_on_tool_changed)
	_build_interface()
	_sync_from_state()
	_show_start_menu()
	queue_redraw()


func _process(delta: float) -> void:
	if not _game_started:
		return
	if drag_preview != null:
		drag_preview.visible = item_drag.armed_item in ["food", "nutrient"]
		if drag_preview.visible:
			drag_preview.position = get_local_mouse_position() - Vector2(18, 18)
	if not bool(game_state.flags.get("dialogue_active", false)):
		game_state.global_counters["care_time"] = float(game_state.global_counters.get("care_time", 0.0)) + delta
	for creature_id in TerryGameState.CREATURE_IDS:
		var creature: Dictionary = game_state.creatures[creature_id]
		if bool(creature.get("present", false)) and not bool(creature.get("disappeared", false)):
			need_system.tick_creature(creature, definitions[creature_id], delta)
	_tick_accumulator += delta
	_prompt_accumulator += delta
	_autosave_accumulator += delta
	if _tick_accumulator >= 1.0:
		_tick_accumulator = 0.0
		_update_egg_requests()
		_update_creature_timers()
		progression.evaluate(game_state)
		_refresh_debug()
	if _prompt_accumulator >= 5.0:
		_prompt_accumulator = 0.0
		_update_prompts()
	if _autosave_accumulator >= 15.0:
		_autosave_accumulator = 0.0
		save_manager.save_game(game_state)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_cancel_tool()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not _quitting:
		_show_exit_menu.call_deferred()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		if _game_started and save_manager != null and game_state != null:
			save_manager.save_game(game_state)
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_on_application_focus_lost()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_on_application_focus_returned()


func _on_application_focus_lost() -> void:
	if not _game_started or not bool(game_state.flags.get("pending_disappearance", false)):
		return
	game_state.flags["absence_return_ready"] = true
	save_manager.save_game(game_state)


func _on_application_focus_returned() -> void:
	if (
		not _game_started
		or not bool(game_state.flags.get("pending_disappearance", false))
		or not bool(game_state.flags.get("absence_return_ready", false))
		or dialogue.is_active()
	):
		return
	_perform_disappearance.call_deferred()


func _draw() -> void:
	draw_rect(Rect2(0, 0, size.x, size.y), WALLPAPER)
	for y in range(8, 288, 16):
		for x in range(8 + int(y / 16) % 2 * 8, 320, 16):
			draw_circle(Vector2(x, y), 1.0, Color(1, 1, 1, 0.16))
	draw_style_box(_stylebox(Color(0.18, 0.16, 0.22, 0.26), Color.TRANSPARENT, 0, 24), Rect2(9, 10, 302, 273))
	draw_style_box(_stylebox(CASE_CORAL, INK, 3, 24), Rect2(7, 5, 302, 273))
	draw_style_box(_stylebox(CASE_LIGHT, Color(1, 1, 1, 0.2), 2, 18), Rect2(14, 12, 288, 256))
	for screw in [Vector2(19, 27), Vector2(301, 27), Vector2(19, 255), Vector2(301, 255)]:
		draw_circle(screw, 4, INK)
		draw_circle(screw, 2, PEACH)
		draw_line(screw + Vector2(-1.5, 0), screw + Vector2(1.5, 0), INK, 1.0)
	for x in [148.0, 156.0, 164.0, 172.0]:
		draw_circle(Vector2(x, 273), 2.0, Color("#B95F5D"))


func _build_interface() -> void:
	var screen_frame := Panel.new()
	screen_frame.position = Vector2(24, 18)
	screen_frame.size = Vector2(272, 159)
	screen_frame.add_theme_stylebox_override("panel", _stylebox(INK, Color("#342E39"), 2, 11))
	add_child(screen_frame)

	var screen_surface := Panel.new()
	screen_surface.position = Vector2(5, 5)
	screen_surface.size = Vector2(262, 149)
	screen_surface.add_theme_stylebox_override("panel", _stylebox(LCD, LCD_DARK, 2, 7))
	screen_frame.add_child(screen_surface)

	tool_label = _make_label("ACARICIAR", Vector2(7, 4), Vector2(248, 13), 7)
	tool_label.name = "ToolLabel"
	tool_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tool_label.add_theme_color_override("font_color", INK)
	screen_surface.add_child(tool_label)

	var arena_panel := Panel.new()
	arena_panel.position = Vector2(5, 19)
	arena_panel.size = Vector2(252, 111)
	arena_panel.add_theme_stylebox_override("panel", _stylebox(Color(0.83, 0.93, 0.72, 0.35), Color("#76956B"), 1, 5))
	screen_surface.add_child(arena_panel)
	arena = Control.new()
	arena.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arena.mouse_filter = Control.MOUSE_FILTER_PASS
	arena_panel.add_child(arena)

	for i in TerryGameState.CREATURE_IDS.size():
		var creature_id: String = TerryGameState.CREATURE_IDS[i]
		var slot := Panel.new()
		slot.position = ENTITY_POSITIONS[i] + Vector2(-4, 3)
		slot.size = Vector2(72, 82)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.add_theme_stylebox_override("panel", _stylebox(Color(1, 1, 1, 0.14), Color(0.25, 0.36, 0.23, 0.23), 1, 12))
		slot.gui_input.connect(_on_slot_input.bind(creature_id))
		arena.add_child(slot)
		slot_nodes[creature_id] = slot
		var empty_marker := Panel.new()
		empty_marker.position = Vector2(13, 58)
		empty_marker.size = Vector2(46, 9)
		empty_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty_marker.add_theme_stylebox_override(
			"panel",
			_stylebox(Color(0.30, 0.38, 0.27, 0.20), Color(0.43, 0.54, 0.38, 0.35), 1, 8)
		)
		empty_marker.hide()
		slot.add_child(empty_marker)
		empty_slot_markers[creature_id] = empty_marker

	var actions := [
		{"id": "food", "text": "YUM"},
		{"id": "play", "text": "JUEGO"},
		{"id": "sleep", "text": "SIESTA"},
		{"id": "clean", "text": "ASEO"},
		{"id": "status", "text": "MIRAR"}
	]
	var controls_tray := Panel.new()
	controls_tray.position = Vector2(30, 219)
	controls_tray.size = Vector2(260, 48)
	controls_tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls_tray.add_theme_stylebox_override("panel", _stylebox(Color("#E9897D"), INK, 2, 15))
	add_child(controls_tray)
	for i in actions.size():
		var action: Dictionary = actions[i]
		var button := _make_action_button(str(action.id), str(action.text), Vector2(34 + i * 51, 222))
		button.pressed.connect(_on_action_button.bind(str(action.id)))
		add_child(button)
		action_buttons[str(action.id)] = button
		action_icons[str(action.id)] = button.get_node("Icon")

	status_panel = Panel.new()
	status_panel.position = Vector2(24, 181)
	status_panel.size = Vector2(272, 36)
	status_panel.add_theme_stylebox_override("panel", _stylebox(CREAM, INK, 2, 10))
	add_child(status_panel)
	status_label = _make_label("ACÉRCATE DESPACIO. LOS HUEVOS TE HARÁN SABER QUÉ NECESITAN.", Vector2(8, 2), Vector2(256, 31), 7)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", INK)
	status_panel.add_child(status_label)

	special_button = _make_button("ENSEÑARLE TU LADO", Vector2(83, 183), Vector2(154, 37), 8)
	special_button.z_index = 5
	special_button.pressed.connect(_show_player_place)
	special_button.hide()
	add_child(special_button)

	drag_preview = TextureRect.new()
	drag_preview.size = Vector2(36, 36)
	drag_preview.texture = _tool_texture("egg_food")
	drag_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	drag_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	drag_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_preview.z_index = 25
	drag_preview.hide()
	add_child(drag_preview)
	_build_dialogue_ui()
	_build_status_window()
	_build_fade_overlay()
	_build_session_menus()


func _build_dialogue_ui() -> void:
	dialogue_panel = Panel.new()
	dialogue_panel.position = Vector2(22, 39)
	dialogue_panel.size = Vector2(276, 136)
	dialogue_panel.z_index = 36
	dialogue_panel.add_theme_stylebox_override("panel", _stylebox(CREAM, INK, 2, 10))
	add_child(dialogue_panel)
	dialogue_speaker = _make_label("", Vector2(10, 6), Vector2(256, 14), 9)
	dialogue_speaker.add_theme_color_override("font_color", SHADOW)
	dialogue_panel.add_child(dialogue_speaker)
	dialogue_text = _make_label("", Vector2(10, 21), Vector2(256, 50), 9)
	dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dialogue_panel.add_child(dialogue_text)
	dialogue_options = HBoxContainer.new()
	dialogue_options.position = Vector2(7, 79)
	dialogue_options.size = Vector2(262, 49)
	dialogue_options.add_theme_constant_override("separation", 4)
	dialogue_panel.add_child(dialogue_options)
	dialogue_panel.hide()


func _build_status_window() -> void:
	status_backdrop = ColorRect.new()
	status_backdrop.color = Color(0.15, 0.13, 0.18, 0.58)
	status_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	status_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	status_backdrop.z_index = 34
	add_child(status_backdrop)
	status_window = Panel.new()
	status_window.position = Vector2(49, 48)
	status_window.size = Vector2(222, 184)
	status_window.add_theme_stylebox_override("panel", _stylebox(CREAM, INK, 3, 16))
	status_backdrop.add_child(status_window)
	status_title = _make_label("", Vector2(13, 11), Vector2(158, 22), 11)
	status_title.add_theme_color_override("font_color", INK)
	status_window.add_child(status_title)
	var close_button := _make_button("X", Vector2(181, 9), Vector2(29, 24), 8)
	close_button.pressed.connect(_close_status_window)
	status_window.add_child(close_button)
	status_details = _make_label("", Vector2(14, 44), Vector2(194, 124), 8)
	status_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_details.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_details.add_theme_color_override("font_color", INK)
	status_window.add_child(status_details)
	status_backdrop.hide()


func _close_status_window() -> void:
	status_backdrop.hide()


func _build_fade_overlay() -> void:
	fade_overlay = ColorRect.new()
	fade_overlay.color = Color(0, 0, 0, 0)
	fade_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	fade_overlay.z_index = 50
	fade_overlay.hide()
	add_child(fade_overlay)


func _build_debug_panel() -> void:
	debug_panel = Panel.new()
	debug_panel.position = Vector2(14, 16)
	debug_panel.size = Vector2(292, 258)
	debug_panel.z_index = 30
	debug_panel.add_theme_stylebox_override("panel", _stylebox(Color("#FFF3DE"), INK, 2, 12))
	add_child(debug_panel)
	var title := _make_label("PANEL DE DEPURACIÓN — cambios explícitos", Vector2(8, 5), Vector2(276, 14), 9)
	debug_panel.add_child(title)
	var commands := [
		["CAMBIAR OBJETIVO", _debug_cycle_target],
		["NECESIDADES = 10", _debug_needs_low],
		["NECESIDADES = 100", _debug_needs_full],
		["+ COMIDA", _debug_add_feed],
		["+ JUEGO", _debug_add_play],
		["+ CARICIA", _debug_add_pet],
		["+ SUEÑO", _debug_add_sleep],
		["+ LIMPIEZA GLOBAL", _debug_add_clean],
		["ABRIR 3 HUEVOS", debug_hatch_all],
		["CUMPLIR CONVIVENCIA", debug_satisfy_phase_one],
		["FORZAR DESAPARICIÓN", _perform_disappearance],
		["COMPLETAR REQ. POST", debug_complete_post_requirements],
		["AVANZAR FASE", _debug_advance_phase],
		["REINICIAR FASE", _debug_reset_phase],
		["GUARDAR", _debug_save],
		["CARGAR", _debug_load],
		["BORRAR GUARDADO", _debug_delete_save]
	]
	for i in commands.size():
		var entry: Array = commands[i]
		var col := i % 3
		var row := i / 3
		var button := _make_button(str(entry[0]), Vector2(7 + col * 93, 23 + row * 22), Vector2(89, 19), 6)
		button.pressed.connect(entry[1])
		debug_panel.add_child(button)
	debug_text = _make_label("", Vector2(8, 159), Vector2(276, 92), 7)
	debug_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	debug_text.add_theme_color_override("font_color", SHADOW)
	debug_panel.add_child(debug_text)
	debug_panel.hide()


func _build_session_menus() -> void:
	start_backdrop = ColorRect.new()
	start_backdrop.color = Color(0.15, 0.13, 0.18, 0.72)
	start_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	start_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	start_backdrop.z_index = 60
	add_child(start_backdrop)

	start_panel = Panel.new()
	start_panel.position = Vector2(48, 55)
	start_panel.size = Vector2(224, 170)
	start_panel.add_theme_stylebox_override("panel", _stylebox(CREAM, INK, 3, 18))
	start_backdrop.add_child(start_panel)
	var start_heading := _make_label("¿CÓMO QUIERES EMPEZAR?", Vector2(12, 14), Vector2(200, 26), 10)
	start_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start_heading.add_theme_color_override("font_color", INK)
	start_panel.add_child(start_heading)
	continue_button = _make_button("CONTINUAR PARTIDA", Vector2(22, 55), Vector2(180, 38), 9)
	continue_button.pressed.connect(_continue_game)
	start_panel.add_child(continue_button)
	var new_game_button := _make_button("EMPEZAR DE CERO", Vector2(22, 105), Vector2(180, 38), 9)
	new_game_button.pressed.connect(_start_new_game)
	start_panel.add_child(new_game_button)

	exit_backdrop = ColorRect.new()
	exit_backdrop.color = Color(0.15, 0.13, 0.18, 0.72)
	exit_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	exit_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	exit_backdrop.z_index = 70
	add_child(exit_backdrop)
	exit_panel = Panel.new()
	exit_panel.position = Vector2(45, 69)
	exit_panel.size = Vector2(230, 145)
	exit_panel.add_theme_stylebox_override("panel", _stylebox(CREAM, INK, 3, 18))
	exit_backdrop.add_child(exit_panel)
	var exit_heading := _make_label("¿QUIERES SALIR?", Vector2(12, 13), Vector2(206, 23), 11)
	exit_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	exit_heading.add_theme_color_override("font_color", INK)
	exit_panel.add_child(exit_heading)
	save_exit_button = _make_button("GUARDAR Y SALIR", Vector2(23, 50), Vector2(184, 37), 9)
	save_exit_button.pressed.connect(_save_and_quit)
	exit_panel.add_child(save_exit_button)
	var return_button := _make_button("SEGUIR JUGANDO", Vector2(23, 97), Vector2(184, 31), 8)
	return_button.pressed.connect(_cancel_exit)
	exit_panel.add_child(return_button)
	exit_backdrop.hide()


func _jump_to_story_moment(moment_id: String) -> void:
	_dialogue_generation += 1
	dialogue.current_dialogue = ""
	dialogue.current_node = ""
	dialogue_panel.hide()
	status_backdrop.hide()
	fade_overlay.color = Color.TRANSPARENT
	fade_overlay.hide()
	_clear_poop_nodes()
	_egg_request_alerted.clear()
	game_state.reset_all()
	_game_started = true
	_loaded_existing_save = true
	start_backdrop.hide()
	exit_backdrop.hide()
	for phase_id in range(9):
		progression.reset_event_latch(phase_id)

	var start_birth_sequence := false
	var start_dialogue_id := ""
	match moment_id:
		"start":
			pass
		"crack_25":
			_story_set_egg_progress(3, 0)
		"first_meal":
			_story_set_egg_progress(3, 2)
		"crack_50":
			_story_set_egg_progress(6, 2)
		"crack_75":
			_story_set_egg_progress(9, 2)
		"second_meal":
			_story_set_egg_progress(9, 4)
		"birth":
			_story_set_egg_progress(12, 4)
			start_birth_sequence = true
		"coexistence":
			_story_prepare_coexistence()
		"pipo_chubby":
			_story_prepare_coexistence()
			game_state.creatures["creature_a"]["born_unix"] = int(Time.get_unix_time_from_system()) - TerryGameState.FIRST_DAY_SECONDS
			game_state.creatures["creature_a"]["favorite_care"] = 4
			game_state.creatures["creature_a"]["body_state"] = "chubby"
		"chat_01":
			_story_prepare_coexistence()
			game_state.global_counters["neglected_requests"] = 1
			game_state.flags["first_voice_triggered"] = true
			game_state.flags["first_neglected_creature"] = "creature_b"
			start_dialogue_id = "chat_01"
		"chat_02":
			_story_prepare_coexistence()
			_story_mark_dialogues(["chat_01"])
			start_dialogue_id = "chat_02"
		"chat_03":
			_story_prepare_coexistence()
			_story_mark_dialogues(["chat_01", "chat_02"])
			start_dialogue_id = "chat_03"
		"chat_10":
			_story_prepare_coexistence()
			_story_mark_dialogues(["chat_01", "chat_02", "chat_03"])
			game_state.answers["why_return_answer"] = "love"
			start_dialogue_id = "chat_10"
		"chat_11":
			_story_prepare_coexistence()
			_story_mark_dialogues(["chat_01", "chat_02", "chat_03", "chat_10"])
			game_state.answers["why_return_answer"] = "love"
			start_dialogue_id = "chat_11"
		"chat_12":
			_story_prepare_coexistence()
			_story_mark_dialogues(["chat_01", "chat_02", "chat_03", "chat_10", "chat_11"])
			game_state.answers["why_return_answer"] = "love"
			start_dialogue_id = "chat_12"
		"before_absence":
			_story_prepare_coexistence()
			_story_complete_coexistence()
			_story_mark_dialogues(PRE_ABSENCE_TALKS)
			game_state.flags["pending_disappearance"] = true
		"absence":
			_story_prepare_absence()
		"dialogue_01":
			_story_prepare_absence()
			start_dialogue_id = "dialogue_01"
		"chat_04":
			_story_prepare_after_words()
			start_dialogue_id = "chat_04"
		"chat_05":
			_story_prepare_after_words()
			_story_mark_dialogues(["chat_04"])
			start_dialogue_id = "chat_05"
		"chat_06":
			_story_prepare_after_words()
			_story_mark_dialogues(["chat_04", "chat_05"])
			start_dialogue_id = "chat_06"
		"dialogue_02":
			_story_prepare_after_words()
			_story_complete_post_dialogue()
			_story_mark_dialogues(["chat_04", "chat_05", "chat_06"])
			start_dialogue_id = "dialogue_02"
		"show_side":
			_story_prepare_after_side()
		"chat_09":
			_story_prepare_after_side()
			_story_mark_dialogues(["chat_07", "chat_08"])
			start_dialogue_id = "chat_09"
		"mota_absence":
			_story_prepare_mota_absence()
		"dialogue_04":
			_story_prepare_mota_absence()
			start_dialogue_id = "dialogue_04"
		"more":
			_story_prepare_final_hunger()
		"dialogue_05":
			_story_prepare_final_hunger()
			game_state.global_counters["final_feed_count"] = 3
			start_dialogue_id = "dialogue_05"
		"ending":
			_story_prepare_final_hunger()
			_story_mark_dialogues(["dialogue_05"])
			game_state.flags["true_ending_seen"] = true
			_story_set_phase(8)

	_sync_from_state()
	_update_egg_requests(false)
	status_label.text = _story_moment_message(moment_id)
	save_manager.save_game(game_state)
	if start_birth_sequence:
		for creature_id in TerryGameState.CREATURE_IDS:
			_hatch_sequence(creature_id)
	elif start_dialogue_id != "":
		dialogue.start(start_dialogue_id, game_state)


func _story_set_phase(phase_id: int) -> void:
	game_state.phase = phase_id
	game_state.unlocks.clear()
	if progression.phases.has(phase_id):
		for action in progression.phases[phase_id].get("available_actions", []):
			game_state.unlocks.append(str(action))


func _story_set_egg_progress(care: int, nutrition: int) -> void:
	var now := int(Time.get_unix_time_from_system())
	for creature_id in TerryGameState.CREATURE_IDS:
		var egg: Dictionary = game_state.eggs[creature_id]
		egg["care"] = care
		egg["nutrition"] = nutrition
		egg["care_strokes"] = care % TerryGameState.EGG_CARE_CAPACITY
		egg["meal_bites"] = nutrition % TerryGameState.EGG_MEAL_CAPACITY
		egg["next_care_unix"] = 0
		egg["next_meal_unix"] = now + TerryGameState.EGG_MEAL_INTERVAL_SECONDS if nutrition == 2 else 0
		_update_egg_visual_state(egg)


func _story_prepare_coexistence() -> void:
	for creature_id in TerryGameState.CREATURE_IDS:
		var egg: Dictionary = game_state.eggs[creature_id]
		egg["care"] = TerryGameState.EGG_CARE_REQUIRED
		egg["nutrition"] = TerryGameState.EGG_NUTRITION_REQUIRED
		game_state.hatch(creature_id)
	_story_set_phase(1)


func _story_complete_coexistence() -> void:
	game_state.global_counters["neglected_requests"] = 2
	game_state.flags["first_voice_triggered"] = true
	game_state.flags["first_neglected_creature"] = "creature_b"


func _story_prepare_absence() -> void:
	_story_prepare_coexistence()
	_story_complete_coexistence()
	_story_mark_dialogues(PRE_ABSENCE_TALKS)
	game_state.flags["pending_disappearance"] = false
	game_state.flags["creature_a_disappeared"] = true
	game_state.flags["first_absence_sequence_played"] = true
	game_state.flags["absence_reveal_active"] = true
	game_state.creatures["creature_a"]["present"] = false
	game_state.creatures["creature_a"]["disappeared"] = true
	_story_set_phase(2)


func _story_prepare_after_words() -> void:
	_story_prepare_absence()
	game_state.flags["absence_reveal_active"] = false
	if "dialogue_01" not in game_state.dialogues_seen:
		game_state.dialogues_seen.append("dialogue_01")
	game_state.answers["dialogue_01_answer"] = "where"
	game_state.flags["dialogue_active"] = false
	_story_set_phase(3)
	game_state.capture_post_dialogue_baseline()


func _story_complete_post_dialogue() -> void:
	var baseline_global: Dictionary = game_state.post_baseline.get("global", {})
	game_state.global_counters["care_cycles_completed"] = int(
		baseline_global.get("care_cycles_completed", 0)
	) + 6


func _story_mark_dialogues(dialogue_ids: Array) -> void:
	for dialogue_id in dialogue_ids:
		var id := str(dialogue_id)
		if id not in game_state.dialogues_seen:
			game_state.dialogues_seen.append(id)


func _story_prepare_after_side() -> void:
	_story_prepare_after_words()
	_story_complete_post_dialogue()
	_story_mark_dialogues(["chat_04", "chat_05", "chat_06", "dialogue_02", "dialogue_03"])
	game_state.flags["player_place_shown"] = true
	_story_set_phase(5)


func _story_prepare_mota_absence() -> void:
	_story_prepare_after_side()
	_story_mark_dialogues(["chat_07", "chat_08", "chat_09"])
	game_state.flags["pending_mota_disappearance"] = false
	game_state.flags["creature_b_disappeared"] = true
	game_state.creatures["creature_b"]["present"] = false
	game_state.creatures["creature_b"]["disappeared"] = true
	_story_set_phase(6)


func _story_prepare_final_hunger() -> void:
	_story_prepare_mota_absence()
	_story_mark_dialogues(["dialogue_04"])
	game_state.global_counters["final_feed_count"] = 0
	_story_set_phase(7)


func _story_moment_message(moment_id: String) -> String:
	var messages := {
		"start": "INICIO · LOS HUEVOS ACABAN DE LLEGAR.",
		"crack_25": "PRIMERA GRIETA · LOS MIMOS EMPIEZAN A HACER EFECTO.",
		"first_meal": "PRIMER NÉCTAR · EL HUEVO ESTÁ SATISFECHO.",
		"crack_50": "GRIETA MEDIA · ALGO SE MUEVE DENTRO.",
		"crack_75": "CASI LISTO · SOLO FALTA EL ÚLTIMO EMPUJÓN.",
		"second_meal": "SEGUNDO NÉCTAR · EL NACIMIENTO ESTÁ MUY CERCA.",
		"birth": "NACIMIENTO · OBSERVA CÓMO SE ABREN LOS HUEVOS.",
		"coexistence": "LOS TRES HERMANOS · TODOS ESTÁN EN CASA.",
		"pipo_chubby": "FINAL DEL PRIMER DÍA · PIPO VIVE PARA COMER Y DORMIR.",
		"chat_01": "PRIMER DESCUIDO · TERRY HABLA POR PRIMERA VEZ.",
		"chat_02": "TERRY TE PREGUNTA POR QUÉ SIEMPRE VUELVES.",
		"chat_03": "TERRY QUIERE SABER SI PIENSAS EN ÉL CUANDO NO ESTÁS.",
		"chat_10": "TERRY RECUERDA EXACTAMENTE POR QUÉ DIJISTE QUE VOLVÍAS.",
		"chat_11": "TERRY QUIERE LLAMARTE AUNQUE NO NECESITE NADA.",
		"chat_12": "TERRY QUIERE SABER SI VENDRÍAS A BUSCARLO.",
		"before_absence": "ALGO VA A CAMBIAR · PIPO SIGUE AQUÍ.",
		"absence": "EL ESPACIO DE PIPO ESTÁ VACÍO.",
		"dialogue_01": "TERRY DICE POR PRIMERA VEZ: «SE FUE».",
		"chat_04": "TERRY HABLA SOBRE ECHAR DE MENOS.",
		"chat_05": "TERRY PREGUNTA SI LOS DEMÁS DEBEN COMPARTIR.",
		"chat_06": "TERRY PREGUNTA SI LO QUERRÍAS TRAS HACER ALGO MALO.",
		"dialogue_02": "TERRY QUIERE SABER QUÉ HAY AL OTRO LADO.",
		"show_side": "TERRY YA HA VISTO TU LADO DE LA PANTALLA.",
		"chat_09": "EL HAMBRE DE TERRY EMPIEZA A CAMBIAR.",
		"mota_absence": "EL ESPACIO DE MOTA TAMBIÉN ESTÁ VACÍO.",
		"dialogue_04": "TERRY INSISTE EN QUE SIGUE SIENDO TERRY.",
		"more": "TERRY PIDE COMIDA OTRA VEZ.",
		"dialogue_05": "TERRY QUIERE SABER QUÉ COMES TÚ.",
		"ending": "DESENLACE · TERRY PREGUNTA: «¿ME ABRES?»"
	}
	return str(messages.get(moment_id, "ESTADO DE PRUEBA PREPARADO."))


func _show_start_menu() -> void:
	continue_button.disabled = not save_manager.has_save()
	continue_button.text = "CONTINUAR PARTIDA" if not continue_button.disabled else "SIN PARTIDA GUARDADA"
	start_backdrop.show()


func _start_new_game() -> void:
	_clear_poop_nodes()
	game_state.reset_all()
	_loaded_existing_save = false
	save_manager.save_game(game_state)
	_begin_session()


func _continue_game() -> void:
	if not save_manager.load_game(game_state):
		continue_button.disabled = true
		continue_button.text = "NO SE PUDO CARGAR"
		return
	_loaded_existing_save = true
	var elapsed := float(Time.get_unix_time_from_system() - game_state.last_session_unix)
	need_system.apply_offline_decay(game_state, definitions, elapsed)
	_begin_session()


func _begin_session() -> void:
	_game_started = true
	start_backdrop.hide()
	game_state.increment_global("sessions_started")
	_sync_from_state()
	_update_creature_timers()
	_sync_poops_from_state()
	_update_egg_requests()
	progression.evaluate(game_state)
	if bool(game_state.flags.get("creature_a_disappeared", false)) and "dialogue_01" not in game_state.dialogues_seen:
		_run_absence_sequence.call_deferred()
	elif (
		bool(game_state.flags.get("pending_disappearance", false))
		and not bool(game_state.flags.get("creature_a_disappeared", false))
		and _loaded_existing_save
		and "chat_01" in game_state.dialogues_seen
	):
		game_state.flags["absence_return_ready"] = true
		_perform_disappearance.call_deferred()


func _show_exit_menu() -> void:
	if _quitting or exit_backdrop == null:
		return
	_cancel_tool()
	save_exit_button.text = "GUARDAR Y SALIR"
	exit_backdrop.show()


func _cancel_exit() -> void:
	exit_backdrop.hide()


func _save_and_quit() -> void:
	if not _save_current_game():
		save_exit_button.text = "NO SE PUDO GUARDAR"
		return
	_quitting = true
	get_tree().quit()


func _save_current_game() -> bool:
	return not _game_started or save_manager.save_game(game_state)


func _sync_from_state() -> void:
	special_button.visible = "show_player_place" in game_state.unlocks and not bool(game_state.flags.get("player_place_shown", false))
	for creature_id in TerryGameState.CREATURE_IDS:
		var index := TerryGameState.CREATURE_IDS.find(creature_id)
		var entity_position: Vector2 = ENTITY_POSITIONS[index]
		var egg: Dictionary = game_state.eggs[creature_id]
		var creature: Dictionary = game_state.creatures[creature_id]
		if not bool(egg.get("hatched", false)):
			if not egg_nodes.has(creature_id):
				var egg_node := EggController.new()
				egg_node.setup(creature_id, definitions[creature_id].color, cursor_manager)
				egg_node.position = entity_position
				egg_node.rubbed.connect(_on_egg_rubbed)
				egg_node.feed_dropped.connect(_on_egg_feed)
				egg_node.hover_changed.connect(_on_target_hover)
				arena.add_child(egg_node)
				egg_nodes[creature_id] = egg_node
			egg_nodes[creature_id].set_visual_state(str(egg.get("visual_state", "intact")))
		elif egg_nodes.has(creature_id):
			egg_nodes[creature_id].queue_free()
			egg_nodes.erase(creature_id)
		if bool(creature.get("present", false)) and not bool(creature.get("disappeared", false)):
			if not creature_nodes.has(creature_id):
				var creature_node := CreatureController.new()
				creature_node.setup(definitions[creature_id], cursor_manager)
				creature_node.position = entity_position
				creature_node.action_requested.connect(_on_creature_action)
				creature_node.hover_changed.connect(_on_target_hover)
				arena.add_child(creature_node)
				creature_node.bubble.symbol_pressed.connect(_on_symbol_pressed.bind(creature_id))
				creature_node.bubble.mouse_entered.connect(_on_talk_bubble_hover.bind(creature_node.bubble, true))
				creature_node.bubble.mouse_exited.connect(_on_talk_bubble_hover.bind(creature_node.bubble, false))
				creature_nodes[creature_id] = creature_node
			creature_nodes[creature_id].set_body_state(str(creature.get("body_state", "normal")))
			var stored_activity := str(creature.get("activity", "sleep" if bool(creature.get("sleeping", false)) else ""))
			if stored_activity != "sleep" and not bool(creature.get("sleeping", false)) and creature_nodes[creature_id].sleeping:
				creature_nodes[creature_id].set_sleeping(false)
			creature_nodes[creature_id].set_activity(
				stored_activity,
				int(creature.get("activity_until_unix", 0))
			)
		elif creature_nodes.has(creature_id):
			creature_nodes[creature_id].queue_free()
			creature_nodes.erase(creature_id)
		if empty_slot_markers.has(creature_id):
			empty_slot_markers[creature_id].visible = bool(creature.get("disappeared", false))
	if bool(game_state.flags.get("absence_reveal_active", false)):
		for sleeping_id in ["creature_b", "creature_main"]:
			if creature_nodes.has(sleeping_id):
				creature_nodes[sleeping_id].set_sleeping(true)
	for action_id in action_buttons:
		var unlock_id: String = "feed" if action_id == "food" else str(action_id)
		action_buttons[action_id].disabled = unlock_id not in game_state.unlocks
	_update_food_tool_art()
	_refresh_talk_request()
	_sync_poops_from_state()
	_refresh_debug()


func _on_action_button(action_id: String) -> void:
	if dialogue.is_active():
		return
	if bool(game_state.flags.get("absence_reveal_active", false)):
		_cancel_tool()
		status_label.text = "NINGUNO DE LOS DOS RESPONDE. SIGUEN DORMIDOS."
		return
	if cursor_manager.selected_tool == action_id:
		_cancel_tool()
		return
	cursor_manager.select_tool(action_id)
	if action_id == "food":
		item_drag.arm("food")
		drag_preview.texture = _food_texture_for_context()
		if _has_unhatched_eggs():
			status_label.text = "OFRECE EL NÉCTAR A UNO DE LOS HUEVOS."
		else:
			status_label.text = "OFRECE EL CUENCO A UNA CRIATURA."
	elif action_id == "clean":
		item_drag.arm("clean")
		status_label.text = "SELECCIONA UNA SUCIEDAD PARA LIMPIARLA."
	else:
		status_label.text = "SELECCIONA UNA CRIATURA PARA USAR: %s." % action_id.to_upper()


func _cancel_tool() -> void:
	item_drag.cancel()
	cursor_manager.cancel_tool()
	status_label.text = "Acción cancelada."


func _on_slot_input(event: InputEvent, creature_id: String) -> void:
	if (
		creature_id != "creature_a"
		or not bool(game_state.flags.get("creature_a_disappeared", false))
		or not (event is InputEventMouseButton)
		or event.button_index != MOUSE_BUTTON_LEFT
		or not event.pressed
	):
		return
	_cancel_tool()
	status_label.text = "EL SITIO DE PIPO ESTÁ FRÍO. SOLO QUEDA LA HUELLA DONDE DORMÍA."
	audio_manager.play_tone("wrong")


func _on_talk_bubble_hover(bubble: SymbolBubble, entered: bool) -> void:
	if entered and bubble.current_symbol == "talk":
		cursor_manager.set_mode("talk")
	else:
		cursor_manager.refresh()


func _on_tool_changed(tool_id: String) -> void:
	var food_name := "NÉCTAR" if _has_unhatched_eggs() else "COMIDA"
	var tool_names := {
		"": "ACARICIAR",
		"food": food_name,
		"play": "JUEGO",
		"sleep": "SUEÑO",
		"clean": "CEPILLO",
		"status": "ESTADO"
	}
	tool_label.text = str(tool_names.get(tool_id, tool_id.to_upper()))
	for action_id in action_buttons:
		action_buttons[action_id].button_pressed = action_id == tool_id


func _on_target_hover(kind: String, entered: bool) -> void:
	if cursor_manager.selected_tool == "food":
		drag_preview.texture = _food_texture_for_context(kind if entered else "")
	if not entered or dialogue.is_active():
		return
	if kind == "egg":
		if cursor_manager.selected_tool == "food":
			status_label.text = "SUELTA AQUÍ EL FRASCO DE NÉCTAR."
		else:
			status_label.text = "MANTÉN PULSADO Y ACARICIA EL CASCARÓN."
	elif kind == "creature":
		if cursor_manager.selected_tool == "":
			status_label.text = "MANTÉN PULSADO Y MUEVE LA MANO PARA ACARICIAR."
		elif cursor_manager.selected_tool == "food":
			status_label.text = "SUELTA AQUÍ EL CUENCO PARA DARLE DE COMER."


func _on_egg_rubbed(creature_id: String) -> void:
	var egg: Dictionary = game_state.eggs[creature_id]
	var display_name: String = str(definitions[creature_id].display_name).to_upper()
	if not _egg_can_accept_care(creature_id):
		var waiting_for_nectar := (
			float(egg["care"]) >= float(_egg_care_gate(egg))
			and float(egg["care"]) < float(egg["care_required"])
			and _egg_can_accept_food(creature_id)
		)
		if egg_nodes.has(creature_id):
			egg_nodes[creature_id].bubble.show_symbol(
				"egg_food" if waiting_for_nectar else "ellipsis",
				1.0,
				80
			)
		if waiting_for_nectar:
			status_label.text = "%s QUIERE UN POQUITO DE NÉCTAR ANTES DE SEGUIR CON LOS MIMOS." % display_name
		elif float(egg["care"]) >= float(_egg_care_gate(egg)) and float(egg["care"]) < float(egg["care_required"]):
			status_label.text = "%s TODAVÍA ESTÁ SATISFECHO. QUIERE DESCANSAR UN POQUITO ANTES DE SEGUIR." % display_name
		else:
			status_label.text = "%s ESTÁ DESCANSANDO DE TANTOS MIMOS." % display_name
		return
	egg["care"] = minf(float(egg["care_required"]), float(egg["care"]) + 1.0)
	egg["care_strokes"] = mini(TerryGameState.EGG_CARE_CAPACITY, int(egg.get("care_strokes", 0)) + 1)
	if int(egg["care_strokes"]) >= TerryGameState.EGG_CARE_CAPACITY and float(egg["care"]) < float(egg["care_required"]):
		egg["next_care_unix"] = int(Time.get_unix_time_from_system()) + TerryGameState.EGG_CARE_INTERVAL_SECONDS
	_update_egg_visual_state(egg)
	if egg_nodes.has(creature_id):
		egg_nodes[creature_id].set_visual_state(str(egg["visual_state"]))
		egg_nodes[creature_id].show_care_feedback("heart")
	if int(egg["care_strokes"]) >= TerryGameState.EGG_CARE_CAPACITY:
		status_label.text = "%s ESTÁ MUY A GUSTO. AHORA QUIERE DESCANSAR UN POQUITO." % display_name
	else:
		status_label.text = "%s SE ACOMODA BAJO TU MANO." % display_name
	audio_manager.play_tone("action")
	_update_egg_requests(false)
	_check_hatch(creature_id)
	save_manager.save_game(game_state)


func _on_egg_feed(creature_id: String) -> void:
	var valid := cursor_manager.selected_tool == "food" and not bool(game_state.eggs[creature_id]["hatched"])
	if not valid:
		item_drag.cancel()
		cursor_manager.cancel_tool()
		return
	var egg: Dictionary = game_state.eggs[creature_id]
	if not _egg_can_accept_food(creature_id):
		item_drag.cancel()
		cursor_manager.cancel_tool()
		if egg_nodes.has(creature_id):
			egg_nodes[creature_id].bubble.show_symbol("no", 1.25, 90)
		if float(egg["nutrition"]) >= float(egg["nutrition_required"]):
			status_label.text = "%s YA ESTÁ BIEN ALIMENTADA." % definitions[creature_id].display_name.to_upper()
		elif int(egg.get("meal_bites", 0)) >= TerryGameState.EGG_MEAL_CAPACITY or int(egg.get("next_meal_unix", 0)) > int(Time.get_unix_time_from_system()):
			status_label.text = "%s NO TIENE MÁS HAMBRE. PODRÁS OFRECERLE NÉCTAR MÁS TARDE." % definitions[creature_id].display_name.to_upper()
		elif float(egg["care"]) < float(_care_required_for_next_meal(egg)):
			status_label.text = "%s PREFIERE UNOS MIMOS ANTES DE TOMAR NÉCTAR." % definitions[creature_id].display_name.to_upper()
		else:
			status_label.text = "%s NO TIENE MÁS HAMBRE. PODRÁS OFRECERLE NÉCTAR MÁS TARDE." % definitions[creature_id].display_name.to_upper()
		audio_manager.play_tone("wrong")
		return
	if not item_drag.drop("egg", creature_id, true):
		return
	egg["nutrition"] = minf(float(egg["nutrition_required"]), float(egg["nutrition"]) + 1.0)
	egg["meal_bites"] = mini(TerryGameState.EGG_MEAL_CAPACITY, int(egg.get("meal_bites", 0)) + 1)
	if int(egg["meal_bites"]) >= TerryGameState.EGG_MEAL_CAPACITY and float(egg["nutrition"]) < float(egg["nutrition_required"]):
		egg["next_meal_unix"] = int(Time.get_unix_time_from_system()) + TerryGameState.EGG_MEAL_INTERVAL_SECONDS
	if egg_nodes.has(creature_id):
		egg_nodes[creature_id].bubble.show_symbol("heart", 1.0, 80)
	if int(egg["meal_bites"]) >= TerryGameState.EGG_MEAL_CAPACITY and float(egg["nutrition"]) < float(egg["nutrition_required"]):
		status_label.text = "%s YA ESTÁ SATISFECHA. AHORA LE VENDRÁN BIEN UNOS MIMOS." % definitions[creature_id].display_name.to_upper()
	else:
		status_label.text = "%s TOMA EL NÉCTAR CON GUSTO." % definitions[creature_id].display_name.to_upper()
	audio_manager.play_tone("action")
	cursor_manager.cancel_tool()
	_update_egg_requests(false)
	_check_hatch(creature_id)
	save_manager.save_game(game_state)


func _egg_can_accept_food(creature_id: String) -> bool:
	if not game_state.eggs.has(creature_id):
		return false
	var egg: Dictionary = game_state.eggs[creature_id]
	if bool(egg.get("hatched", false)) or float(egg.get("nutrition", 0.0)) >= float(egg.get("nutrition_required", TerryGameState.EGG_NUTRITION_REQUIRED)):
		return false
	if float(egg.get("care", 0.0)) < float(_care_required_for_next_meal(egg)):
		return false
	var now := int(Time.get_unix_time_from_system())
	var next_meal := int(egg.get("next_meal_unix", 0))
	if next_meal > 0 and now >= next_meal:
		egg["meal_bites"] = 0
		egg["next_meal_unix"] = 0
		next_meal = 0
	return next_meal == 0 and int(egg.get("meal_bites", 0)) < TerryGameState.EGG_MEAL_CAPACITY


func _egg_can_accept_care(creature_id: String) -> bool:
	if not game_state.eggs.has(creature_id):
		return false
	var egg: Dictionary = game_state.eggs[creature_id]
	if bool(egg.get("hatched", false)) or float(egg.get("care", 0.0)) >= float(egg.get("care_required", TerryGameState.EGG_CARE_REQUIRED)):
		return false
	var now := int(Time.get_unix_time_from_system())
	var next_care := int(egg.get("next_care_unix", 0))
	if next_care > 0 and now >= next_care:
		egg["care_strokes"] = 0
		egg["next_care_unix"] = 0
		next_care = 0
	return (
		next_care == 0
		and int(egg.get("care_strokes", 0)) < TerryGameState.EGG_CARE_CAPACITY
		and float(egg.get("care", 0.0)) < float(_egg_care_gate(egg))
	)


func _egg_care_gate(egg: Dictionary) -> int:
	var nutrition := int(egg.get("nutrition", 0))
	if nutrition >= TerryGameState.EGG_NUTRITION_REQUIRED:
		return TerryGameState.EGG_CARE_REQUIRED
	if nutrition >= TerryGameState.EGG_MEAL_CAPACITY:
		return int(round(float(TerryGameState.EGG_CARE_REQUIRED) * 0.75))
	return int(round(float(TerryGameState.EGG_CARE_REQUIRED) * 0.25))


func _care_required_for_next_meal(egg: Dictionary) -> int:
	if int(egg.get("nutrition", 0)) >= TerryGameState.EGG_MEAL_CAPACITY:
		return int(round(float(TerryGameState.EGG_CARE_REQUIRED) * 0.75))
	return int(round(float(TerryGameState.EGG_CARE_REQUIRED) * 0.25))


func _update_egg_visual_state(egg: Dictionary) -> void:
	var ratio := float(egg.get("care", 0.0)) / float(TerryGameState.EGG_CARE_REQUIRED)
	if ratio >= 0.75:
		egg["visual_state"] = "crack_75"
	elif ratio >= 0.5:
		egg["visual_state"] = "crack_50"
	elif ratio >= 0.25:
		egg["visual_state"] = "crack_25"
	else:
		egg["visual_state"] = "intact"


func _update_egg_requests(play_sound: bool = true) -> void:
	var new_request := false
	for creature_id in TerryGameState.CREATURE_IDS:
		if not egg_nodes.has(creature_id):
			_egg_request_alerted.erase(creature_id)
			continue
		var desired_symbol := ""
		if _egg_can_accept_care(creature_id):
			desired_symbol = "pet_request"
		elif _egg_can_accept_food(creature_id):
			desired_symbol = "egg_food"
		var previous_symbol := str(_egg_request_alerted.get(creature_id, ""))
		var bubble: SymbolBubble = egg_nodes[creature_id].bubble
		if desired_symbol != "":
			if bubble.current_symbol != desired_symbol:
				bubble.show_symbol(desired_symbol, 3600.0, 55, true)
			if previous_symbol != desired_symbol:
				new_request = true
			_egg_request_alerted[creature_id] = desired_symbol
		else:
			if bubble.current_symbol in ["egg_food", "pet_request"]:
				bubble.clear()
			_egg_request_alerted[creature_id] = ""
	if new_request and play_sound:
		audio_manager.play_tone("talk")


func _duration_text(seconds: int) -> String:
	if seconds <= 0:
		return "AHORA"
	if seconds >= 3600:
		return "1 H"
	return "%d MIN" % maxi(1, int(ceil(float(seconds) / 60.0)))


func _check_hatch(creature_id: String) -> void:
	var egg: Dictionary = game_state.eggs[creature_id]
	if bool(egg["hatched"]):
		return
	if float(egg["care"]) >= float(egg["care_required"]) and float(egg["nutrition"]) >= float(egg["nutrition_required"]):
		_hatch_sequence(creature_id)


func _hatch_sequence(creature_id: String) -> void:
	var egg: Dictionary = game_state.eggs[creature_id]
	if str(egg["visual_state"]) == "hatching":
		return
	egg["visual_state"] = "hatching"
	if egg_nodes.has(creature_id):
		egg_nodes[creature_id].set_visual_state("hatching")
		egg_nodes[creature_id].bubble.show_sequence(["hatch", "heart"], 0.45, 80)
	audio_manager.play_tone("hatch")
	await get_tree().create_timer(0.8).timeout
	game_state.hatch(creature_id)
	_sync_from_state()
	status_label.text = "Ha nacido %s." % definitions[creature_id].display_name
	progression.evaluate(game_state)
	save_manager.save_game(game_state)


func _on_creature_action(creature_id: String, tool: String) -> void:
	if dialogue.is_active():
		return
	if bool(game_state.flags.get("absence_reveal_active", false)):
		_cancel_tool()
		status_label.text = "NO RESPONDE. EL SUEÑO PARECE DEMASIADO PROFUNDO."
		return
	var creature: Dictionary = game_state.creatures[creature_id]
	if str(creature.get("activity", "")) != "" and tool != "status":
		var activity_name := "JUGANDO" if str(creature.get("activity", "")) == "play" else "DURMIENDO"
		_refuse_creature_action(creature_id, "%s SIGUE %s." % [definitions[creature_id].display_name.to_upper(), activity_name])
		return
	if bool(creature.get("sleeping", false)) and tool != "status":
		_refuse_creature_action(creature_id, "%s ESTÁ DURMIENDO." % definitions[creature_id].display_name.to_upper())
		return
	var tool_actions := {"pet": "petted", "food": "fed", "play": "played", "sleep": "slept"}
	if tool_actions.has(tool) and not (game_state.phase == 7 and creature_id == "creature_main"):
		if not _request_allows_action(creature_id, str(tool_actions[tool])):
			_refuse_creature_action(creature_id, "%s TE ESTÁ PIDIENDO OTRA COSA." % definitions[creature_id].display_name.to_upper())
			return
	match tool:
		"pet":
			_apply_creature_action(creature_id, "petted")
			_complete_request_if_matching(creature_id, "petted")
			if creature_id == "creature_main":
				creature["ready_to_sleep"] = true
			creature_nodes[creature_id].react("pet_reaction", "heart")
		"food":
			if game_state.phase == 7 and creature_id == "creature_main":
				_feed_final_hunger()
				return
			if not _creature_can_accept_food(creature_id):
				var wait_text := _creature_meal_wait_text(creature)
				var message := "%s NO TIENE MÁS HAMBRE." % definitions[creature_id].display_name.to_upper()
				if wait_text != "AHORA":
					message += " VUELVE EN %s." % wait_text
				_refuse_creature_action(creature_id, message)
				return
			if item_drag.drop("creature", creature_id, true):
				creature["meal_bites"] = mini(
					TerryGameState.CREATURE_MEAL_CAPACITY,
					int(creature.get("meal_bites", 0)) + 1
				)
				if int(creature["meal_bites"]) >= TerryGameState.CREATURE_MEAL_CAPACITY:
					creature["next_meal_unix"] = int(Time.get_unix_time_from_system()) + TerryGameState.CREATURE_MEAL_INTERVAL_SECONDS
				if int(creature.get("poop_due_unix", 0)) <= 0:
					creature["poop_due_unix"] = int(Time.get_unix_time_from_system()) + TerryGameState.POOP_DELAY_SECONDS
				_apply_creature_action(creature_id, "fed")
				_complete_request_if_matching(creature_id, "fed")
				creature_nodes[creature_id].react("eat", "heart")
				cursor_manager.cancel_tool()
				status_label.text = "%s HA COMIDO." % definitions[creature_id].display_name.to_upper()
				save_manager.save_game(game_state)
		"play":
			if not _request_allows_action(creature_id, "played"):
				_refuse_creature_action(creature_id, "%s TE ESTÁ PIDIENDO OTRA COSA." % definitions[creature_id].display_name.to_upper())
				return
			var now := int(Time.get_unix_time_from_system())
			if not care_loop.begin_activity(creature, "play", now, TerryGameState.PLAY_DURATION_SECONDS):
				_refuse_creature_action(creature_id, "%s YA ESTÁ OCUPADA." % definitions[creature_id].display_name.to_upper())
				return
			_apply_creature_action(creature_id, "played")
			_complete_request_if_matching(creature_id, "played")
			creature_nodes[creature_id].set_activity("play", int(creature["activity_until_unix"]))
			creature_nodes[creature_id].bubble.clear()
			creature_nodes[creature_id].bubble.show_symbol("heart", 1.0, 75)
			status_label.text = "%s JUGARÁ DURANTE 1 HORA. PUEDES VOLVER A TU BLOQUE DE TRABAJO." % definitions[creature_id].display_name.to_upper()
			save_manager.save_game(game_state)
			cursor_manager.cancel_tool()
		"sleep":
			_try_sleep(creature_id)
			cursor_manager.cancel_tool()
		"status":
			_show_status(creature_id)
			cursor_manager.cancel_tool()
		_:
			_refuse_creature_action(creature_id, "%s PREFIERE HACER OTRA COSA AHORA." % definitions[creature_id].display_name.to_upper())


func _feed_final_hunger() -> void:
	if not creature_nodes.has("creature_main"):
		return
	var count := int(game_state.global_counters.get("final_feed_count", 0))
	if count >= 3:
		_refuse_creature_action("creature_main", "TERRY YA NO ESTÁ MIRANDO LA COMIDA.")
		return
	if not item_drag.drop("creature", "creature_main", true):
		return
	game_state.global_counters["final_feed_count"] = count + 1
	game_state.increment_action("creature_main", "fed")
	creature_nodes["creature_main"].react("eat", "heart", 1.1)
	cursor_manager.cancel_tool()
	audio_manager.play_tone("action")
	if count == 0:
		status_label.text = "TERRY: «GRACIAS.»"
	elif count == 1:
		status_label.text = "TERRY: «GRACIAS OTRA VEZ.»"
	else:
		status_label.text = "TERRY: «MÁS.»"
	progression.evaluate(game_state)
	save_manager.save_game(game_state)


func _apply_creature_action(creature_id: String, action: String) -> void:
	var creature: Dictionary = game_state.creatures[creature_id]
	need_system.apply_action(creature, action)
	game_state.increment_action(creature_id, action)
	status_label.text = "%s · %s." % [definitions[creature_id].display_name, _action_display(action)]
	audio_manager.play_tone("action")
	progression.evaluate(game_state)
	_refresh_debug()


func _complete_request_if_matching(creature_id: String, action: String) -> bool:
	var completed := care_loop.fulfill_request(
		game_state,
		creature_id,
		action,
		int(Time.get_unix_time_from_system())
	)
	if completed:
		if creature_nodes.has(creature_id):
			creature_nodes[creature_id].bubble.clear()
		progression.evaluate(game_state)
		_maybe_offer_talk()
	return completed


func _request_allows_action(creature_id: String, action: String) -> bool:
	var request := str(game_state.creatures[creature_id].get("request", ""))
	if request == "":
		return true
	var mapping := {
		"fed": "food",
		"played": "play",
		"slept": "sleep",
		"petted": "affection"
	}
	return str(mapping.get(action, "")) == request


func _creature_can_accept_food(creature_id: String) -> bool:
	var creature: Dictionary = game_state.creatures[creature_id]
	var now := int(Time.get_unix_time_from_system())
	var next_meal := int(creature.get("next_meal_unix", 0))
	if next_meal > 0 and now >= next_meal:
		creature["meal_bites"] = 0
		creature["next_meal_unix"] = 0
		next_meal = 0
	return (
		not bool(creature.get("sleeping", false))
		and float(creature["needs"]["satiety"]) < 98.0
		and next_meal == 0
		and int(creature.get("meal_bites", 0)) < TerryGameState.CREATURE_MEAL_CAPACITY
	)


func _creature_meal_wait_text(creature: Dictionary) -> String:
	var seconds := maxi(0, int(creature.get("next_meal_unix", 0)) - int(Time.get_unix_time_from_system()))
	if seconds <= 0:
		return "AHORA"
	if seconds >= 3600:
		return "1 H"
	return "%d MIN" % maxi(1, int(ceil(float(seconds) / 60.0)))


func _refuse_creature_action(creature_id: String, message: String) -> void:
	if creature_nodes.has(creature_id):
		creature_nodes[creature_id].react("refuse", "no", 1.4)
	status_label.text = message
	audio_manager.play_tone("wrong")
	item_drag.cancel()
	cursor_manager.cancel_tool()


func _try_sleep(creature_id: String) -> void:
	var creature: Dictionary = game_state.creatures[creature_id]
	var definition: CreatureDefinition = definitions[creature_id]
	if bool(definition.needs_pet_to_sleep) and not bool(creature.get("ready_to_sleep", false)):
		_refuse_creature_action(creature_id, "%s NECESITA UNA CARICIA ANTES DE DORMIR." % definition.display_name.to_upper())
		return
	if bool(creature.get("sleeping", false)):
		_refuse_creature_action(creature_id, "%s YA ESTÁ DURMIENDO." % definition.display_name.to_upper())
		return
	if not _request_allows_action(creature_id, "slept"):
		_refuse_creature_action(creature_id, "%s TE ESTÁ PIDIENDO OTRA COSA." % definition.display_name.to_upper())
		return
	creature["ready_to_sleep"] = false
	var now := int(Time.get_unix_time_from_system())
	if not care_loop.begin_activity(creature, "sleep", now, TerryGameState.SLEEP_DURATION_SECONDS):
		_refuse_creature_action(creature_id, "%s YA ESTÁ OCUPADA." % definition.display_name.to_upper())
		return
	game_state.increment_action(creature_id, "slept")
	_complete_request_if_matching(creature_id, "slept")
	creature_nodes[creature_id].set_activity("sleep", int(creature["sleep_until_unix"]))
	status_label.text = "%s SE HA ACURRUCADO · DORMIRÁ 1 HORA." % definition.display_name.to_upper()
	progression.evaluate(game_state)
	save_manager.save_game(game_state)


func _update_creature_timers() -> void:
	if bool(game_state.flags.get("absence_reveal_active", false)):
		return
	var now := int(Time.get_unix_time_from_system())
	var state_changed := false
	var care_events := care_loop.update(game_state, definitions, now)
	var story_neglect_registered := false
	for event in care_events:
		if str(event.get("type", "")) == "request_missed":
			event["counts_for_story"] = not story_neglect_registered
			story_neglect_registered = true
		_handle_care_loop_event(event)
		state_changed = true
	for creature_id in TerryGameState.CREATURE_IDS:
		var creature: Dictionary = game_state.creatures[creature_id]
		var next_meal := int(creature.get("next_meal_unix", 0))
		if next_meal > 0 and now >= next_meal:
			creature["meal_bites"] = 0
			creature["next_meal_unix"] = 0
			state_changed = true
		var poop_due := int(creature.get("poop_due_unix", 0))
		if (
			poop_due > 0
			and now >= poop_due
			and bool(creature.get("present", false))
			and not bool(creature.get("disappeared", false))
		):
			creature["poop_due_unix"] = 0
			_spawn_poop(creature_id)
			state_changed = true
	if state_changed:
		save_manager.save_game(game_state)


func _handle_care_loop_event(event: Dictionary) -> void:
	var creature_id := str(event.get("creature_id", ""))
	if not definitions.has(creature_id):
		return
	var display_name := str(definitions[creature_id].display_name).to_upper()
	match str(event.get("type", "")):
		"request_started":
			var request := str(event.get("request", ""))
			if creature_nodes.has(creature_id):
				creature_nodes[creature_id].bubble.show_symbol(care_loop.request_symbol(request), 3600.0, 105, true)
			status_label.text = _request_message(creature_id, request)
			audio_manager.play_tone("talk")
		"request_missed":
			if creature_nodes.has(creature_id):
				creature_nodes[creature_id].bubble.clear()
			if bool(event.get("counts_for_story", true)):
				_register_neglect(creature_id, str(event.get("request", "")))
		"activity_finished":
			var activity := str(event.get("activity", ""))
			if creature_nodes.has(creature_id):
				if activity == "sleep":
					creature_nodes[creature_id].set_sleeping(false)
				else:
					creature_nodes[creature_id].set_activity("")
			if activity == "play":
				status_label.text = "%s HA TERMINADO DE JUGAR Y AHORA TIENE HAMBRE." % display_name
				if creature_nodes.has(creature_id):
					creature_nodes[creature_id].bubble.show_symbol("creature_food", 3600.0, 105, true)
			else:
				status_label.text = "%s SE HA DESPERTADO." % display_name
			if creature_id == "creature_main":
				game_state.global_counters["sleep_cycles_since_talk"] = int(
					game_state.global_counters.get("sleep_cycles_since_talk", 0)
				) + 1
			_maybe_offer_talk.call_deferred()
		"body_changed":
			if creature_nodes.has(creature_id):
				creature_nodes[creature_id].set_body_state(str(event.get("body_state", "normal")))
			status_label.text = "PIPO ESTÁ MÁS REDONDITO. ESTÁ CLARO QUE VIVE PARA COMER Y DORMIR."
			audio_manager.play_tone("hatch")


func _request_message(creature_id: String, request: String) -> String:
	var display_name := str(definitions[creature_id].display_name).to_upper()
	match request:
		"food":
			return "%s TIENE HAMBRE." % display_name
		"play":
			return "%s QUIERE JUGAR. PUEDES DEJARLA JUGANDO DURANTE TU PRÓXIMA HORA." % display_name
		"sleep":
			return "%s QUIERE ACURRUCARSE Y DORMIR UNA HORA." % display_name
		"affection":
			return "%s QUIERE UN POCO DE CARIÑO." % display_name
	return "%s NECESITA ALGO DE TI." % display_name


func _register_neglect(creature_id: String, request: String) -> void:
	var total := int(game_state.global_counters.get("neglected_requests", 0))
	if total == 0 and "chat_01" not in game_state.dialogues_seen:
		game_state.global_counters["neglected_requests"] = 1
		game_state.flags["first_voice_triggered"] = true
		game_state.flags["first_neglected_creature"] = creature_id
		game_state.flags["pending_talk_id"] = "chat_01"
		game_state.global_counters["care_cycles_at_first_voice"] = int(
			game_state.global_counters.get("care_cycles_completed", 0)
		)
		_refresh_talk_request()
		status_label.text = "TERRY TE ESTÁ MIRANDO. POR PRIMERA VEZ, PARECE QUE QUIERE DECIR ALGO."
		audio_manager.play_tone("talk")
	elif total == 1:
		var first_voice_cycles := int(game_state.global_counters.get("care_cycles_at_first_voice", 0))
		var has_new_care := int(game_state.global_counters.get("care_cycles_completed", 0)) > first_voice_cycles
		if not _all_dialogues_seen(PRE_ABSENCE_TALKS) or not has_new_care:
			status_label.text = "%s SE QUEDA ESPERANDO. TERRY LO HA VISTO." % definitions[creature_id].display_name.to_upper()
			return
		game_state.global_counters["neglected_requests"] = 2
		game_state.flags["pending_disappearance"] = true
		game_state.flags["absence_waiting_for_return"] = true
		game_state.flags["absence_return_ready"] = false
		status_label.text = "TERRY NO APARTA LOS OJOS DEL LUGAR DE PIPO."
		save_manager.save_game(game_state)
	progression.evaluate(game_state)
	_refresh_debug()


func _all_dialogues_seen(dialogue_ids: Array) -> bool:
	for dialogue_id in dialogue_ids:
		if str(dialogue_id) not in game_state.dialogues_seen:
			return false
	return true


func _show_status(creature_id: String) -> void:
	var creature: Dictionary = game_state.creatures[creature_id]
	game_state.increment_action(creature_id, "status_checks")
	status_title.text = definitions[creature_id].display_name.to_upper()
	var activity := str(creature.get("activity", ""))
	if activity == "play":
		status_details.text = "ESTÁ JUGANDO.\n\nTERMINARÁ EN %s.\n\nDESPUÉS SEGURAMENTE TENDRÁ HAMBRE." % [
			_duration_text(int(creature.get("activity_until_unix", 0)) - int(Time.get_unix_time_from_system()))
		]
		status_backdrop.show()
		return
	if bool(creature.get("sleeping", false)):
		status_details.text = "ESTÁ DURMIENDO.\n\nDESPERTARÁ EN %s." % [
			_duration_text(int(creature.get("sleep_until_unix", 0)) - int(Time.get_unix_time_from_system()))
		]
		status_backdrop.show()
		return
	var needs: Dictionary = creature["needs"]
	status_details.text = "HAMBRE      %s\nHIGIENE     %s\nENERGÍA     %s\nDIVERSIÓN   %s\nCARIÑO      %s\nSALUD       %s\n\nPREFIERE: %s" % [
		_need_description(float(needs["satiety"])),
		_need_description(float(needs["hygiene"])),
		_need_description(float(needs["energy"])),
		_need_description(float(needs["fun"])),
		_need_description(float(needs["affection"])),
		_need_description(float(needs["health"])),
		_preference_text(creature_id)
	]
	status_backdrop.show()
	if creature_id == "creature_b" and float(needs["satiety"]) < 50.0:
		creature_nodes[creature_id].bubble.show_symbol("ellipsis", 1.5, 30)


func _need_description(value: float) -> String:
	if value >= 80.0:
		return "MUY BIEN"
	if value >= 55.0:
		return "BIEN"
	if value >= 30.0:
		return "REGULAR"
	return "NECESITA ATENCIÓN"


func _preference_text(creature_id: String) -> String:
	match creature_id:
		"creature_a":
			return "COMER Y DORMIR"
		"creature_b":
			return "JUGAR"
	return "CARIÑO Y COMPAÑÍA"


func _spawn_poop(creature_id: String) -> void:
	var total_waiting := 0
	for id in TerryGameState.CREATURE_IDS:
		total_waiting += int(game_state.creatures[id].get("poops_waiting", 0))
	if total_waiting >= 12 or not creature_nodes.has(creature_id):
		return
	var creature: Dictionary = game_state.creatures[creature_id]
	creature["poops_waiting"] = int(creature.get("poops_waiting", 0)) + 1
	_spawn_poop_node(creature_id)
	game_state.increment_action(creature_id, "poops_generated")
	game_state.increment_global("poops_generated")
	creature["needs"]["hygiene"] = maxf(0.0, float(creature["needs"]["hygiene"]) - 16.0)
	if creature_nodes.has(creature_id):
		creature_nodes[creature_id].bubble.show_symbol("dirty", 2.0, 42)


func _spawn_poop_node(creature_id: String) -> void:
	if not creature_nodes.has(creature_id):
		return
	var poop := PoopController.new()
	poop.setup(creature_id, cursor_manager)
	var base: Vector2 = creature_nodes[creature_id].position
	var owner_count := 0
	for existing in poop_nodes:
		if existing.owner_id == creature_id:
			owner_count += 1
	poop.position = Vector2(clampf(base.x + 46 + (owner_count % 3) * 7, 4, 240), 91 - (owner_count % 2) * 15)
	poop.clean_requested.connect(_on_clean_poop)
	arena.add_child(poop)
	poop_nodes.append(poop)


func _sync_poops_from_state() -> void:
	if arena == null:
		return
	for creature_id in TerryGameState.CREATURE_IDS:
		var desired := int(game_state.creatures[creature_id].get("poops_waiting", 0))
		var owner_nodes: Array[PoopController] = []
		for poop in poop_nodes:
			if is_instance_valid(poop) and poop.owner_id == creature_id:
				owner_nodes.append(poop)
		while owner_nodes.size() > desired:
			var extra: PoopController = owner_nodes.pop_back()
			poop_nodes.erase(extra)
			extra.queue_free()
		while owner_nodes.size() < desired and creature_nodes.has(creature_id):
			_spawn_poop_node(creature_id)
			owner_nodes.append(poop_nodes[-1])


func _clear_poop_nodes() -> void:
	for poop in poop_nodes:
		if is_instance_valid(poop):
			poop.queue_free()
	poop_nodes.clear()


func _on_clean_poop(poop: PoopController) -> void:
	if poop not in poop_nodes:
		return
	var creature_id := poop.owner_id
	poop_nodes.erase(poop)
	poop.queue_free()
	game_state.creatures[creature_id]["poops_waiting"] = maxi(
		0,
		int(game_state.creatures[creature_id].get("poops_waiting", 0)) - 1
	)
	game_state.increment_action(creature_id, "poops_cleaned")
	game_state.increment_global("poops_cleaned")
	need_system.apply_action(game_state.creatures[creature_id], "cleaned")
	if creature_nodes.has(creature_id):
		creature_nodes[creature_id].react("happy", "heart")
	status_label.text = "Suciedad de %s limpiada · total %d." % [definitions[creature_id].display_name, game_state.global_counters["poops_cleaned"]]
	audio_manager.play_tone("action")
	cursor_manager.cancel_tool()
	progression.evaluate(game_state)


func _update_prompts() -> void:
	if bool(game_state.flags.get("absence_reveal_active", false)):
		return
	for creature_id in creature_nodes:
		if creature_id == "creature_main" and str(game_state.flags.get("pending_talk_id", "")) != "":
			creature_nodes[creature_id].bubble.show_symbol("talk", 3600.0, 110, true)
			continue
		var prompt := prompt_system.choose_prompt(game_state, progression, creature_id)
		if not prompt.is_empty():
			var duration := 3600.0 if bool(prompt.get("persistent", false)) else 3.5
			creature_nodes[creature_id].bubble.show_symbol(
				str(prompt.symbol),
				duration,
				int(prompt.priority),
				bool(prompt.get("persistent", false))
			)


func _on_symbol_pressed(symbol_id: String, creature_id: String) -> void:
	if symbol_id != "talk" or creature_id != "creature_main":
		return
	_start_pending_talk()


func _conversation_candidates() -> Array[String]:
	var candidates: Array[String] = []
	match game_state.phase:
		1:
			if "chat_01" in game_state.dialogues_seen:
				candidates = ["chat_02", "chat_03", "chat_10", "chat_11", "chat_12"]
		3:
			candidates = ["chat_02", "chat_03", "chat_04", "chat_05", "chat_06"]
		5:
			candidates = ["chat_07", "chat_08", "chat_09"]
	return candidates


func _maybe_offer_talk(force: bool = false) -> void:
	if dialogue.is_active() or not creature_nodes.has("creature_main"):
		return
	if str(game_state.flags.get("pending_talk_id", "")) != "":
		_refresh_talk_request()
		return
	if not force and int(game_state.global_counters.get("care_cycles_since_talk", 0)) < 2:
		return
	for dialogue_id in _conversation_candidates():
		if dialogue_id not in game_state.dialogues_seen:
			game_state.flags["pending_talk_id"] = dialogue_id
			game_state.global_counters["sleep_cycles_since_talk"] = 0
			game_state.global_counters["care_cycles_since_talk"] = 0
			_refresh_talk_request()
			status_label.text = "TERRY QUIERE HABLAR CONTIGO."
			audio_manager.play_tone("talk")
			save_manager.save_game(game_state)
			return


func _refresh_talk_request() -> void:
	if not creature_nodes.has("creature_main"):
		return
	var pending_id := str(game_state.flags.get("pending_talk_id", ""))
	var bubble: SymbolBubble = creature_nodes["creature_main"].bubble
	if pending_id != "" and not dialogue.is_active():
		bubble.show_symbol("talk", 3600.0, 110, true)
	elif bubble.current_symbol == "talk":
		bubble.clear()


func _start_pending_talk() -> void:
	if dialogue.is_active():
		return
	var pending_id := str(game_state.flags.get("pending_talk_id", ""))
	if pending_id == "":
		return
	if creature_nodes.has("creature_main"):
		creature_nodes["creature_main"].bubble.clear()
	dialogue.start(pending_id, game_state)


func _on_progression_event(event_id: String) -> void:
	match event_id:
		"prepare_disappearance":
			game_state.flags["pending_disappearance"] = true
			game_state.flags["absence_waiting_for_return"] = true
			status_label.text = "TERRY NO APARTA LOS OJOS DEL LUGAR DE PIPO."
			save_manager.save_game(game_state)
		"start_dialogue_02":
			if not dialogue.is_active() and "dialogue_02" not in game_state.dialogues_seen:
				dialogue.start("dialogue_02", game_state)
		"prepare_second_disappearance":
			game_state.flags["pending_mota_disappearance"] = true
			status_label.text = "MOTA SE MANTIENE MUY CERCA DE TERRY. QUIZÁ TODOS NECESITEN DESCANSAR."
			save_manager.save_game(game_state)
		"start_final_dialogue":
			if not dialogue.is_active() and "dialogue_05" not in game_state.dialogues_seen:
				dialogue.start("dialogue_05", game_state)


func _perform_disappearance() -> void:
	if bool(game_state.flags.get("creature_a_disappeared", false)):
		if "dialogue_01" not in game_state.dialogues_seen:
			_run_absence_sequence()
		return
	game_state.flags["creature_a_disappeared"] = true
	game_state.flags["pending_disappearance"] = false
	game_state.flags["absence_waiting_for_return"] = false
	game_state.flags["absence_return_ready"] = false
	game_state.flags["absence_reveal_active"] = true
	game_state.flags["first_absence_sequence_played"] = true
	game_state.flags["pending_talk_id"] = ""
	game_state.creatures["creature_a"]["present"] = false
	game_state.creatures["creature_a"]["disappeared"] = true
	progression.set_phase(game_state, 2)
	_sync_from_state()
	save_manager.save_game(game_state)
	_run_absence_sequence()


func _run_absence_sequence() -> void:
	if dialogue.is_active() or "dialogue_01" in game_state.dialogues_seen:
		return
	_absence_generation += 1
	var generation := _absence_generation
	game_state.flags["absence_reveal_active"] = true
	game_state.flags["pending_talk_id"] = ""
	_sync_from_state()
	for sleeping_id in ["creature_b", "creature_main"]:
		if creature_nodes.has(sleeping_id):
			creature_nodes[sleeping_id].bubble.clear()
			creature_nodes[sleeping_id].set_sleeping(true)
	status_label.text = "..."
	save_manager.save_game(game_state)
	await get_tree().create_timer(4.5).timeout
	if generation != _absence_generation or dialogue.is_active() or "dialogue_01" in game_state.dialogues_seen:
		return
	if creature_nodes.has("creature_main"):
		creature_nodes["creature_main"].set_sleeping(false)
		creature_nodes["creature_main"].react("first_word", "", 3600.0)
	game_state.flags["pending_talk_id"] = "dialogue_01"
	_refresh_talk_request()
	status_label.text = "TERRY HA ABIERTO LOS OJOS. PARECE QUE QUIERE HABLAR."
	audio_manager.play_tone("talk")
	save_manager.save_game(game_state)


func _perform_second_disappearance() -> void:
	if bool(game_state.flags.get("creature_b_disappeared", false)):
		if "dialogue_04" not in game_state.dialogues_seen:
			_run_second_absence_sequence()
		return
	game_state.flags["pending_mota_disappearance"] = false
	game_state.flags["creature_b_disappeared"] = true
	game_state.creatures["creature_b"]["present"] = false
	game_state.creatures["creature_b"]["disappeared"] = true
	progression.set_phase(game_state, 6)
	_sync_from_state()
	save_manager.save_game(game_state)
	_run_second_absence_sequence()


func _run_second_absence_sequence() -> void:
	if dialogue.is_active() or "dialogue_04" in game_state.dialogues_seen:
		return
	status_label.text = "EL ESPACIO DE MOTA ESTÁ VACÍO."
	await get_tree().create_timer(1.6).timeout
	if creature_nodes.has("creature_main"):
		creature_nodes["creature_main"].react("terrible", "heart", 2.0)
	audio_manager.play_tone("talk")
	await get_tree().create_timer(0.8).timeout
	dialogue.start("dialogue_04", game_state)


func _on_dialogue_node(dialogue_id: String, _node_id: String, node: Dictionary) -> void:
	_dialogue_generation += 1
	var generation := _dialogue_generation
	status_backdrop.hide()
	dialogue_panel.show()
	dialogue_speaker.text = str(node.get("speaker", ""))
	dialogue_text.text = "…"
	var node_symbol := str(node.get("symbol", ""))
	if node_symbol != "" and creature_nodes.has("creature_main"):
		creature_nodes["creature_main"].bubble.show_symbol(node_symbol, 2.5, 95)
	for child in dialogue_options.get_children():
		child.queue_free()
	var delay := float(node.get("delay", 0.0))
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if generation != _dialogue_generation:
		return
	dialogue_text.text = "«%s»" % _dialogue_node_text(node)
	audio_manager.play_tone("talk")
	var options: Array = node.get("options", [])
	if not options.is_empty():
		for i in options.size():
			var option: Dictionary = options[i]
			var button := _make_button(str(option.get("text", "")), Vector2.ZERO, Vector2(84, 44), 6)
			button.custom_minimum_size = Vector2(84, 44)
			button.pressed.connect(dialogue.choose_option.bind(i, game_state))
			dialogue_options.add_child(button)
	else:
		var button := _make_button("CONTINUAR", Vector2.ZERO, Vector2(248, 34), 7)
		button.custom_minimum_size = Vector2(248, 34)
		button.pressed.connect(dialogue.continue_node.bind(game_state))
		dialogue_options.add_child(button)


func _dialogue_node_text(node: Dictionary) -> String:
	var resolved_text := str(node.get("text", ""))
	var neglected_id := str(game_state.flags.get("first_neglected_creature", ""))
	var neglected_name := "ALGUIEN"
	if definitions.has(neglected_id):
		neglected_name = str(definitions[neglected_id].display_name)
	resolved_text = resolved_text.replace("{neglected_name}", neglected_name)
	var answer_ref := str(node.get("answer_ref", ""))
	if answer_ref != "":
		var variants: Dictionary = node.get("text_by_answer", {})
		var answer := str(game_state.answers.get(answer_ref, ""))
		if variants.has(answer):
			return str(variants[answer])
	return resolved_text


func _on_dialogue_finished(dialogue_id: String) -> void:
	dialogue_panel.hide()
	if dialogue_id.begins_with("chat_"):
		game_state.flags["pending_talk_id"] = ""
		game_state.global_counters["sleep_cycles_since_talk"] = 0
		game_state.global_counters["care_cycles_since_talk"] = 0
		if creature_nodes.has("creature_main"):
			creature_nodes["creature_main"].bubble.clear()
		status_label.text = "TERRY SE QUEDA PENSANDO EN TU RESPUESTA."
		progression.evaluate(game_state)
	if dialogue_id == "dialogue_01":
		_absence_generation += 1
		game_state.flags["pending_talk_id"] = ""
		game_state.flags["absence_reveal_active"] = false
		game_state.capture_post_dialogue_baseline()
		progression.set_phase(game_state, 3)
		status_label.text = "MOTA SE DESPIERTA. TERRY SIGUE MIRANDO EL HUECO DE PIPO."
	elif dialogue_id == "dialogue_02":
		progression.set_phase(game_state, 4)
		if "show_player_place" not in game_state.unlocks:
			game_state.unlocks.append("show_player_place")
		status_label.text = "TERRY ESPERA QUE LE ENSEÑES TU LADO."
	elif dialogue_id == "dialogue_03":
		game_state.flags["player_place_shown"] = true
		progression.set_phase(game_state, 5)
		status_label.text = "TERRY YA SABE QUE EXISTE ALGO AL OTRO LADO."
	elif dialogue_id == "dialogue_04":
		progression.set_phase(game_state, 7)
		game_state.global_counters["final_feed_count"] = 0
		status_label.text = "TERRY TODAVÍA TIENE HAMBRE."
	elif dialogue_id == "dialogue_05":
		game_state.flags["true_ending_seen"] = true
		progression.set_phase(game_state, 8)
		status_label.text = "ALGO HA GOLPEADO EL OTRO LADO DEL CRISTAL."
	_sync_from_state()
	save_manager.save_game(game_state)


func _show_player_place() -> void:
	if bool(game_state.flags.get("player_place_shown", false)) or dialogue.is_active():
		return
	if creature_nodes.has("creature_main"):
		creature_nodes["creature_main"].react("look_at_player", "eye", 5.0)
	fade_overlay.show()
	var tween_in := create_tween()
	tween_in.tween_property(fade_overlay, "color", Color.BLACK, 2.0)
	await tween_in.finished
	audio_manager.play_tone("talk")
	await get_tree().create_timer(2.5).timeout
	var tween_out := create_tween()
	tween_out.tween_property(fade_overlay, "color", Color(0, 0, 0, 0), 2.0)
	await tween_out.finished
	fade_overlay.hide()
	special_button.hide()
	status_label.text = "TERRY TE ESTÁ MIRANDO."
	dialogue.start("dialogue_03", game_state)
	save_manager.save_game(game_state)


func debug_hatch_all() -> void:
	for creature_id in TerryGameState.CREATURE_IDS:
		game_state.hatch(creature_id)
	progression.set_phase(game_state, 1)
	_sync_from_state()


func debug_satisfy_phase_one() -> void:
	debug_hatch_all()
	game_state.global_counters["neglected_requests"] = 2
	game_state.flags["first_voice_triggered"] = true
	game_state.flags["first_neglected_creature"] = "creature_b"
	_story_mark_dialogues(PRE_ABSENCE_TALKS)
	progression.evaluate(game_state)
	_refresh_debug()


func debug_complete_post_requirements() -> void:
	if game_state.post_baseline.is_empty():
		game_state.capture_post_dialogue_baseline()
	game_state.global_counters["care_cycles_completed"] = int(
		game_state.post_baseline["global"].get("care_cycles_completed", 0)
	) + 6
	_story_mark_dialogues(["chat_04", "chat_05", "chat_06"])
	if game_state.phase < 3:
		progression.set_phase(game_state, 3)
	progression.reset_event_latch(3)
	progression.evaluate(game_state)
	_refresh_debug()


func _debug_cycle_target() -> void:
	debug_target_index = (debug_target_index + 1) % TerryGameState.CREATURE_IDS.size()
	_refresh_debug()


func _debug_needs_low() -> void:
	var creature_id: String = TerryGameState.CREATURE_IDS[debug_target_index]
	for need_name in TerryGameState.NEED_NAMES:
		game_state.creatures[creature_id]["needs"][need_name] = 10.0
	_refresh_debug()


func _debug_needs_full() -> void:
	var creature_id: String = TerryGameState.CREATURE_IDS[debug_target_index]
	for need_name in TerryGameState.NEED_NAMES:
		game_state.creatures[creature_id]["needs"][need_name] = 100.0
	_refresh_debug()


func _debug_add_feed() -> void:
	_debug_increment("fed")


func _debug_add_play() -> void:
	_debug_increment("played")


func _debug_add_pet() -> void:
	_debug_increment("petted")


func _debug_add_sleep() -> void:
	_debug_increment("slept")


func _debug_increment(action: String) -> void:
	var creature_id: String = TerryGameState.CREATURE_IDS[debug_target_index]
	game_state.increment_action(creature_id, action)
	progression.evaluate(game_state)
	_refresh_debug()


func _debug_add_clean() -> void:
	game_state.increment_global("poops_cleaned")
	progression.evaluate(game_state)
	_refresh_debug()


func _debug_advance_phase() -> void:
	progression.set_phase(game_state, mini(8, game_state.phase + 1))
	_sync_from_state()


func _debug_reset_phase() -> void:
	match game_state.phase:
		0:
			for creature_id in TerryGameState.CREATURE_IDS:
				game_state.eggs[creature_id]["care"] = 0.0
				game_state.eggs[creature_id]["care_strokes"] = 0
				game_state.eggs[creature_id]["next_care_unix"] = 0
				game_state.eggs[creature_id]["nutrition"] = 0.0
				game_state.eggs[creature_id]["meal_bites"] = 0
				game_state.eggs[creature_id]["next_meal_unix"] = 0
				game_state.eggs[creature_id]["visual_state"] = "intact"
		1:
			for creature_id in TerryGameState.CREATURE_IDS:
				for action in ["fed", "played", "petted", "slept"]:
					game_state.creatures[creature_id]["counters"][action] = 0
			game_state.global_counters["poops_cleaned"] = 0
			game_state.global_counters["care_time"] = 0.0
		3:
			game_state.capture_post_dialogue_baseline()
	progression.reset_event_latch(game_state.phase)
	_refresh_debug()


func _debug_save() -> void:
	status_label.text = "Guardado correcto." if save_manager.save_game(game_state) else "Error al guardar."


func _debug_load() -> void:
	if save_manager.load_game(game_state):
		_sync_from_state()
		status_label.text = "Partida cargada."
	else:
		status_label.text = "No hay guardado válido."


func _debug_delete_save() -> void:
	status_label.text = "Guardado del prototipo borrado." if save_manager.delete_save() else "No se pudo borrar."


func _refresh_debug() -> void:
	if debug_text == null:
		return
	var target: String = TerryGameState.CREATURE_IDS[debug_target_index]
	var pending := progression.pending_requirements(game_state)
	var creature: Dictionary = game_state.creatures[target]
	debug_text.text = "OBJETIVO: %s | FASE: %d | PRESENTE: %s\nNECESIDADES: %s\nCONTADORES: %s\nPENDIENTES: %s\nFLAGS: %s\nRESPUESTAS: %s" % [
		target, game_state.phase, creature.get("present", false),
		str(creature.get("needs", {})), str(creature.get("counters", {})),
		str(pending), str(game_state.flags), str(game_state.answers)
	]


func _on_phase_changed(_new_phase: int) -> void:
	_sync_from_state()


func _make_label(text_value: String, at: Vector2, dimensions: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = at
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", BROWN)
	return label


func _make_action_button(action_id: String, label_text: String, at: Vector2) -> Button:
	var button := _make_button("", at, Vector2(46, 39), 6)
	button.toggle_mode = true
	button.tooltip_text = label_text.capitalize()
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.position = Vector2(10, 1)
	icon.size = Vector2(26, 26)
	icon.texture = _icon_texture(action_id)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	var action_name := _make_label(label_text, Vector2.ZERO, Vector2.ZERO, 7)
	action_name.name = "ActionName"
	action_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	action_name.add_theme_color_override("font_color", INK)
	action_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(action_name)
	action_name.anchor_left = 0.0
	action_name.anchor_top = 1.0
	action_name.anchor_right = 1.0
	action_name.anchor_bottom = 1.0
	action_name.offset_left = 1.0
	action_name.offset_top = -15.0
	action_name.offset_right = -1.0
	action_name.offset_bottom = -2.0
	return button


func _icon_texture(action_id: String) -> AtlasTexture:
	return _tool_texture(action_id)


func _tool_texture(tool_id: String) -> AtlasTexture:
	var cells := {
		"pet": Vector2i(0, 0),
		"rub": Vector2i(1, 0),
		"egg_food": Vector2i(2, 0),
		"food": Vector2i(3, 0),
		"play": Vector2i(4, 0),
		"sleep": Vector2i(5, 0),
		"clean": Vector2i(6, 0),
		"status": Vector2i(7, 0)
	}
	var cell: Vector2i = cells.get(tool_id, Vector2i.ZERO)
	var atlas := AtlasTexture.new()
	atlas.atlas = load(ACTION_ICON_SHEET)
	atlas.region = Rect2(
		cell.x * ACTION_ICON_CELL_SIZE,
		cell.y * ACTION_ICON_CELL_SIZE,
		ACTION_ICON_CELL_SIZE,
		ACTION_ICON_CELL_SIZE
	)
	atlas.filter_clip = true
	return atlas


func _has_unhatched_eggs() -> bool:
	for creature_id in TerryGameState.CREATURE_IDS:
		if not bool(game_state.eggs[creature_id].get("hatched", false)):
			return true
	return false


func _food_texture_for_context(target_kind: String = "") -> Texture2D:
	if target_kind == "egg":
		return _tool_texture("egg_food")
	if target_kind == "creature":
		return _icon_texture("food")
	return _tool_texture("egg_food") if _has_unhatched_eggs() else _icon_texture("food")


func _update_food_tool_art() -> void:
	if action_icons.has("food"):
		var food_icon: TextureRect = action_icons["food"]
		food_icon.texture = _food_texture_for_context()
	if drag_preview != null and cursor_manager.selected_tool != "food":
		drag_preview.texture = _food_texture_for_context()


func _make_button(text_value: String, at: Vector2, dimensions: Vector2, font_size: int) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = at
	button.size = dimensions
	button.toggle_mode = false
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_stylebox_override("normal", _stylebox(PEACH, INK, 2, 10))
	button.add_theme_stylebox_override("hover", _stylebox(SKY, INK, 2, 12))
	button.add_theme_stylebox_override("pressed", _stylebox(LAVENDER, INK, 3, 12))
	button.add_theme_stylebox_override("hover_pressed", _stylebox(LAVENDER.lightened(0.08), INK, 3, 12))
	button.add_theme_stylebox_override("disabled", _stylebox(Color(0.75, 0.72, 0.68, 0.55), Color(0.3, 0.28, 0.3, 0.55), 1, 10))
	button.pivot_offset = dimensions * 0.5
	button.button_down.connect(_on_button_press_feedback.bind(button))
	return button


func _on_button_press_feedback(button: Button) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	button.scale = Vector2(0.93, 0.93)
	button.modulate = Color("#FFE5B8")
	var tween := button.create_tween().set_parallel(true)
	tween.tween_property(button, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "modulate", Color.WHITE, 0.18)


func _stylebox(fill: Color, border: Color, width: int, radius: int = 7) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


func _phase_name(phase_id: int) -> String:
	match phase_id:
		0:
			return "INCUBACIÓN"
		1:
			return "CONVIVENCIA"
		2:
			return "LA AUSENCIA"
		3:
			return "DESPUÉS DE LAS PALABRAS"
		4:
			return "LA PREGUNTA"
		5:
			return "TRAS EL CRISTAL"
		6:
			return "LA AUSENCIA DE MOTA"
		7:
			return "MÁS"
		8:
			return "EL OTRO LADO"
	return "DESCONOCIDA"


func _action_display(action: String) -> String:
	match action:
		"fed":
			return "ha comido"
		"played":
			return "ha jugado"
		"petted":
			return "ha recibido una caricia"
	return action
