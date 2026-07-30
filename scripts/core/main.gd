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
const ICON_SHEET := "res://assets/ui/care-icons.png"
const TOOL_CURSOR_SHEET := "res://assets/ui/tool-cursors.png"
const TOOL_CELL_SIZE := 418

var game_state := TerryGameState.new()
var definitions: Dictionary
var need_system := NeedSystem.new()
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
var phase_label: Label
var tool_label: Label
var action_buttons: Dictionary = {}
var action_icons: Dictionary = {}
var special_button: Button
var egg_nodes: Dictionary = {}
var creature_nodes: Dictionary = {}
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
var debug_target_index := 0
var _loaded_existing_save := false
var _game_started := false
var _quitting := false
var _tick_accumulator := 0.0
var _prompt_accumulator := 0.0
var _autosave_accumulator := 0.0
var _dialogue_generation := 0
var _egg_hunger_alerted: Dictionary = {}


func _ready() -> void:
	get_tree().auto_accept_quit = false
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
		_update_egg_meal_requests()
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
	if event.is_action_pressed("toggle_debug"):
		debug_panel.visible = not debug_panel.visible
		if debug_panel.visible:
			_refresh_debug()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_cancel_tool()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not _quitting:
		_show_exit_menu.call_deferred()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		if _game_started and save_manager != null and game_state != null:
			save_manager.save_game(game_state)


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

	phase_label = _make_label("", Vector2(7, 4), Vector2(148, 13), 7)
	phase_label.add_theme_color_override("font_color", INK)
	screen_surface.add_child(phase_label)
	tool_label = _make_label("ACARICIAR", Vector2(151, 4), Vector2(104, 13), 7)
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
		var slot := Panel.new()
		slot.position = ENTITY_POSITIONS[i] + Vector2(-4, 3)
		slot.size = Vector2(72, 82)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_theme_stylebox_override("panel", _stylebox(Color(1, 1, 1, 0.14), Color(0.25, 0.36, 0.23, 0.23), 1, 12))
		arena.add_child(slot)

	var actions := [
		{"id": "food", "text": "COMER"},
		{"id": "play", "text": "JUGAR"},
		{"id": "sleep", "text": "DORMIR"},
		{"id": "clean", "text": "LIMPIAR"},
		{"id": "status", "text": "ESTADO"}
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
	status_label = _make_label("LOS HUEVOS RESPONDEN AL CALOR, AL CUIDADO Y AL TIEMPO.", Vector2(8, 2), Vector2(256, 31), 7)
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
	_build_fade_overlay()
	_build_debug_panel()
	_build_session_menus()


func _build_dialogue_ui() -> void:
	dialogue_panel = Panel.new()
	dialogue_panel.position = Vector2(28, 55)
	dialogue_panel.size = Vector2(264, 105)
	dialogue_panel.z_index = 10
	dialogue_panel.add_theme_stylebox_override("panel", _stylebox(CREAM, INK, 2, 10))
	add_child(dialogue_panel)
	dialogue_speaker = _make_label("", Vector2(8, 5), Vector2(248, 14), 9)
	dialogue_speaker.add_theme_color_override("font_color", SHADOW)
	dialogue_panel.add_child(dialogue_speaker)
	dialogue_text = _make_label("", Vector2(8, 20), Vector2(248, 31), 10)
	dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_panel.add_child(dialogue_text)
	dialogue_options = HBoxContainer.new()
	dialogue_options.position = Vector2(6, 56)
	dialogue_options.size = Vector2(252, 42)
	dialogue_options.add_theme_constant_override("separation", 4)
	dialogue_panel.add_child(dialogue_options)
	dialogue_panel.hide()


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
	var save_exit_button := _make_button("GUARDAR Y SALIR", Vector2(23, 50), Vector2(184, 37), 9)
	save_exit_button.pressed.connect(_save_and_quit)
	exit_panel.add_child(save_exit_button)
	var return_button := _make_button("SEGUIR JUGANDO", Vector2(23, 97), Vector2(184, 31), 8)
	return_button.pressed.connect(_cancel_exit)
	exit_panel.add_child(return_button)
	exit_backdrop.hide()


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
	_update_egg_meal_requests()
	progression.evaluate(game_state)
	if bool(game_state.flags.get("creature_a_disappeared", false)) and "dialogue_01" not in game_state.dialogues_seen:
		_run_absence_sequence.call_deferred()
	elif (
		bool(game_state.flags.get("pending_disappearance", false))
		and not bool(game_state.flags.get("creature_a_disappeared", false))
		and _loaded_existing_save
		and not bool(game_state.creatures["creature_main"].get("sleeping", false))
	):
		_perform_disappearance.call_deferred()


func _show_exit_menu() -> void:
	if _quitting or exit_backdrop == null:
		return
	_cancel_tool()
	exit_backdrop.show()


func _cancel_exit() -> void:
	exit_backdrop.hide()


func _save_and_quit() -> void:
	if _game_started:
		save_manager.save_game(game_state)
	_quitting = true
	get_tree().quit()


func _sync_from_state() -> void:
	phase_label.text = "FASE %d · %s" % [game_state.phase, _phase_name(game_state.phase)]
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
				creature_nodes[creature_id] = creature_node
			creature_nodes[creature_id].set_sleeping(bool(creature.get("sleeping", false)))
		elif creature_nodes.has(creature_id):
			creature_nodes[creature_id].queue_free()
			creature_nodes.erase(creature_id)
	for action_id in action_buttons:
		var unlock_id: String = "feed" if action_id == "food" else str(action_id)
		action_buttons[action_id].disabled = unlock_id not in game_state.unlocks
	_update_food_tool_art()
	_sync_poops_from_state()
	_refresh_debug()


func _on_action_button(action_id: String) -> void:
	if dialogue.is_active():
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
			status_label.text = "MANTÉN PULSADO Y FROTA DE LADO A LADO ↔."
	elif kind == "creature":
		if cursor_manager.selected_tool == "":
			status_label.text = "MANTÉN PULSADO Y MUEVE LA MANO PARA ACARICIAR."
		elif cursor_manager.selected_tool == "food":
			status_label.text = "SUELTA AQUÍ EL CUENCO PARA DARLE DE COMER."


func _on_egg_rubbed(creature_id: String) -> void:
	var egg: Dictionary = game_state.eggs[creature_id]
	egg["heat"] = minf(float(egg["heat_required"]), float(egg["heat"]) + 1.0)
	if float(egg["heat"]) >= float(egg["heat_required"]) * 0.6:
		egg["visual_state"] = "cracked"
	status_label.text = "%s · EL CASCARÓN ESTÁ MÁS TIBIO." % definitions[creature_id].display_name.to_upper()
	audio_manager.play_tone("action")
	_check_hatch(creature_id)


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
			status_label.text = "%s YA NO BUSCA MÁS NÉCTAR · X" % definitions[creature_id].display_name.to_upper()
		else:
			status_label.text = "%s NO QUIERE MÁS AHORA · VUELVE MÁS TARDE · X" % definitions[creature_id].display_name.to_upper()
		audio_manager.play_tone("wrong")
		return
	if not item_drag.drop("egg", creature_id, true):
		return
	egg["nutrition"] = minf(float(egg["nutrition_required"]), float(egg["nutrition"]) + 1.0)
	egg["meal_bites"] = mini(TerryGameState.EGG_MEAL_CAPACITY, int(egg.get("meal_bites", 0)) + 1)
	if int(egg["meal_bites"]) >= TerryGameState.EGG_MEAL_CAPACITY and float(egg["nutrition"]) < float(egg["nutrition_required"]):
		egg["next_meal_unix"] = int(Time.get_unix_time_from_system()) + TerryGameState.EGG_MEAL_INTERVAL_SECONDS
	if egg_nodes.has(creature_id):
		var reaction := "full" if int(egg["meal_bites"]) >= TerryGameState.EGG_MEAL_CAPACITY else "happy"
		egg_nodes[creature_id].bubble.show_symbol(reaction, 1.0, 80)
	if int(egg["meal_bites"]) >= TerryGameState.EGG_MEAL_CAPACITY and float(egg["nutrition"]) < float(egg["nutrition_required"]):
		status_label.text = "%s PARECE SACIADA · VUELVE MÁS TARDE." % definitions[creature_id].display_name.to_upper()
	else:
		status_label.text = "%s HA ACEPTADO EL NÉCTAR." % definitions[creature_id].display_name.to_upper()
	audio_manager.play_tone("action")
	cursor_manager.cancel_tool()
	_update_egg_meal_requests(false)
	_check_hatch(creature_id)
	save_manager.save_game(game_state)


func _egg_can_accept_food(creature_id: String) -> bool:
	if not game_state.eggs.has(creature_id):
		return false
	var egg: Dictionary = game_state.eggs[creature_id]
	if bool(egg.get("hatched", false)) or float(egg.get("nutrition", 0.0)) >= float(egg.get("nutrition_required", TerryGameState.EGG_NUTRITION_REQUIRED)):
		return false
	var now := int(Time.get_unix_time_from_system())
	var next_meal := int(egg.get("next_meal_unix", 0))
	if next_meal > 0 and now >= next_meal:
		egg["meal_bites"] = 0
		egg["next_meal_unix"] = 0
		next_meal = 0
	return next_meal == 0 and int(egg.get("meal_bites", 0)) < TerryGameState.EGG_MEAL_CAPACITY


func _update_egg_meal_requests(play_sound: bool = true) -> void:
	var new_request := false
	for creature_id in TerryGameState.CREATURE_IDS:
		if not egg_nodes.has(creature_id):
			_egg_hunger_alerted.erase(creature_id)
			continue
		var hungry := _egg_can_accept_food(creature_id)
		var was_alerted := bool(_egg_hunger_alerted.get(creature_id, false))
		if hungry:
			egg_nodes[creature_id].bubble.show_symbol("food", 3600.0, 55, true)
			if not was_alerted:
				new_request = true
			_egg_hunger_alerted[creature_id] = true
		else:
			egg_nodes[creature_id].bubble.hide_symbol("food")
			_egg_hunger_alerted[creature_id] = false
	if new_request and play_sound:
		audio_manager.play_tone("talk")


func _egg_wait_text(egg: Dictionary) -> String:
	var seconds := maxi(0, int(egg.get("next_meal_unix", 0)) - int(Time.get_unix_time_from_system()))
	return _duration_text(seconds)


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
	if float(egg["heat"]) >= float(egg["heat_required"]) and float(egg["nutrition"]) >= float(egg["nutrition_required"]):
		_hatch_sequence(creature_id)


func _hatch_sequence(creature_id: String) -> void:
	var egg: Dictionary = game_state.eggs[creature_id]
	if str(egg["visual_state"]) == "hatching":
		return
	egg["visual_state"] = "hatching"
	if egg_nodes.has(creature_id):
		egg_nodes[creature_id].set_visual_state("hatching")
		egg_nodes[creature_id].bubble.show_sequence(["surprise", "happy"], 0.45, 80)
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
	var creature: Dictionary = game_state.creatures[creature_id]
	if bool(creature.get("sleeping", false)) and tool != "status":
		_refuse_creature_action(creature_id, "%s ESTÁ DURMIENDO." % definitions[creature_id].display_name.to_upper())
		return
	match tool:
		"pet":
			_apply_creature_action(creature_id, "petted")
			if creature_id == "creature_main":
				creature["ready_to_sleep"] = true
			creature_nodes[creature_id].react("pet_reaction", "heart")
		"food":
			if not _creature_can_accept_food(creature_id):
				var wait_text := _creature_meal_wait_text(creature)
				var message := "%s NO QUIERE COMER MÁS." % definitions[creature_id].display_name.to_upper()
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
				creature_nodes[creature_id].react("eat", "happy")
				cursor_manager.cancel_tool()
				status_label.text = "%s HA COMIDO." % definitions[creature_id].display_name.to_upper()
				save_manager.save_game(game_state)
		"play":
			_apply_creature_action(creature_id, "played")
			creature_nodes[creature_id].react("play", "happy", 1.1)
			cursor_manager.cancel_tool()
		"sleep":
			_try_sleep(creature_id)
			cursor_manager.cancel_tool()
		"status":
			_show_status(creature_id)
			cursor_manager.cancel_tool()
		_:
			_refuse_creature_action(creature_id, "%s NO QUIERE ESO." % definitions[creature_id].display_name.to_upper())


func _apply_creature_action(creature_id: String, action: String) -> void:
	var creature: Dictionary = game_state.creatures[creature_id]
	need_system.apply_action(creature, action)
	game_state.increment_action(creature_id, action)
	status_label.text = "%s · %s." % [definitions[creature_id].display_name, _action_display(action)]
	audio_manager.play_tone("action")
	progression.evaluate(game_state)
	_refresh_debug()


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
	creature["ready_to_sleep"] = false
	creature["sleeping"] = true
	creature["sleep_until_unix"] = int(Time.get_unix_time_from_system()) + TerryGameState.SLEEP_DURATION_SECONDS
	game_state.increment_action(creature_id, "slept")
	creature_nodes[creature_id].set_sleeping(true)
	status_label.text = "%s SE HA ACURRUCADO · DORMIRÁ 1 HORA." % definition.display_name.to_upper()
	progression.evaluate(game_state)
	save_manager.save_game(game_state)


func _update_creature_timers() -> void:
	var now := int(Time.get_unix_time_from_system())
	var state_changed := false
	for creature_id in TerryGameState.CREATURE_IDS:
		var creature: Dictionary = game_state.creatures[creature_id]
		var next_meal := int(creature.get("next_meal_unix", 0))
		if next_meal > 0 and now >= next_meal:
			creature["meal_bites"] = 0
			creature["next_meal_unix"] = 0
			state_changed = true
		var sleep_until := int(creature.get("sleep_until_unix", 0))
		if bool(creature.get("sleeping", false)) and sleep_until > 0 and now >= sleep_until:
			creature["sleeping"] = false
			creature["sleep_until_unix"] = 0
			creature["needs"]["energy"] = 100.0
			if creature_nodes.has(creature_id):
				creature_nodes[creature_id].set_sleeping(false)
			status_label.text = "%s SE HA DESPERTADO." % definitions[creature_id].display_name.to_upper()
			state_changed = true
			if creature_id == "creature_main" and bool(game_state.flags.get("pending_disappearance", false)):
				_perform_disappearance.call_deferred()
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


func _show_status(creature_id: String) -> void:
	var creature: Dictionary = game_state.creatures[creature_id]
	game_state.increment_action(creature_id, "status_checks")
	if bool(creature.get("sleeping", false)):
		status_label.text = "%s · DURMIENDO · DESPIERTA EN %s" % [
			definitions[creature_id].display_name.to_upper(),
			_duration_text(int(creature.get("sleep_until_unix", 0)) - int(Time.get_unix_time_from_system()))
		]
		return
	var needs: Dictionary = creature["needs"]
	status_label.text = "%s · sac %.0f · hig %.0f · ene %.0f · div %.0f · afe %.0f · sal %.0f" % [
		definitions[creature_id].display_name,
		needs["satiety"], needs["hygiene"], needs["energy"], needs["fun"], needs["affection"], needs["health"]
	]
	if creature_id == "creature_b" and float(needs["satiety"]) < 50.0:
		creature_nodes[creature_id].bubble.show_symbol("ellipsis", 1.5, 30)


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
		creature_nodes[creature_id].react("happy", "happy")
	status_label.text = "Suciedad de %s limpiada · total %d." % [definitions[creature_id].display_name, game_state.global_counters["poops_cleaned"]]
	audio_manager.play_tone("action")
	cursor_manager.cancel_tool()
	progression.evaluate(game_state)


func _update_prompts() -> void:
	for creature_id in creature_nodes:
		var prompt := prompt_system.choose_prompt(game_state, progression, creature_id)
		if not prompt.is_empty():
			creature_nodes[creature_id].bubble.show_symbol(str(prompt.symbol), 3.5, int(prompt.priority))
			if creature_id == "creature_main" and "dialogue_01" in game_state.dialogues_seen and str(prompt.source) == "narrative":
				var phrase := prompt_system.scripted_spoken_prompt(str(prompt.symbol))
				if phrase != "":
					status_label.text = "Terry: «%s»" % phrase


func _on_progression_event(event_id: String) -> void:
	match event_id:
		"prepare_disappearance":
			game_state.flags["pending_disappearance"] = true
			status_label.text = "Las criaturas parecen cansadas. Completa otro sueño o vuelve más tarde."
			save_manager.save_game(game_state)
		"start_dialogue_02":
			if not dialogue.is_active() and "dialogue_02" not in game_state.dialogues_seen:
				dialogue.start("dialogue_02", game_state)


func _perform_disappearance() -> void:
	if bool(game_state.flags.get("creature_a_disappeared", false)):
		if "dialogue_01" not in game_state.dialogues_seen:
			_run_absence_sequence()
		return
	game_state.flags["creature_a_disappeared"] = true
	game_state.flags["pending_disappearance"] = false
	game_state.creatures["creature_a"]["present"] = false
	game_state.creatures["creature_a"]["disappeared"] = true
	progression.set_phase(game_state, 2)
	_sync_from_state()
	save_manager.save_game(game_state)
	_run_absence_sequence()


func _run_absence_sequence() -> void:
	if dialogue.is_active() or "dialogue_01" in game_state.dialogues_seen:
		return
	status_label.text = "El espacio de Pipa está vacío."
	await get_tree().create_timer(2.0).timeout
	if creature_nodes.has("creature_main"):
		creature_nodes["creature_main"].bubble.show_symbol("ellipsis", 2.0, 90)
		creature_nodes["creature_main"].react("first_word", "ellipsis", 2.0)
	audio_manager.play_tone("talk")
	await get_tree().create_timer(1.0).timeout
	dialogue.start("dialogue_01", game_state)


func _on_dialogue_node(dialogue_id: String, _node_id: String, node: Dictionary) -> void:
	_dialogue_generation += 1
	var generation := _dialogue_generation
	dialogue_panel.show()
	dialogue_speaker.text = str(node.get("speaker", ""))
	dialogue_text.text = "…"
	for child in dialogue_options.get_children():
		child.queue_free()
	var delay := float(node.get("delay", 0.0))
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if generation != _dialogue_generation:
		return
	dialogue_text.text = "«%s»" % str(node.get("text", ""))
	audio_manager.play_tone("talk")
	var options: Array = node.get("options", [])
	if not options.is_empty():
		for i in options.size():
			var option: Dictionary = options[i]
			var button := _make_button(str(option.get("text", "")), Vector2.ZERO, Vector2(80, 39), 6)
			button.custom_minimum_size = Vector2(80, 39)
			button.pressed.connect(dialogue.choose_option.bind(i, game_state))
			dialogue_options.add_child(button)
	else:
		var button := _make_button("CONTINUAR", Vector2.ZERO, Vector2(248, 34), 7)
		button.custom_minimum_size = Vector2(248, 34)
		button.pressed.connect(dialogue.continue_node.bind(game_state))
		dialogue_options.add_child(button)


func _on_dialogue_finished(dialogue_id: String) -> void:
	dialogue_panel.hide()
	if dialogue_id == "dialogue_01":
		game_state.capture_post_dialogue_baseline()
		progression.set_phase(game_state, 3)
		status_label.text = "Terry ya habla. Sus símbolos señalan lo que falta para continuar."
	elif dialogue_id == "dialogue_02":
		progression.set_phase(game_state, 4)
		if "show_player_place" not in game_state.unlocks:
			game_state.unlocks.append("show_player_place")
		status_label.text = "Se ha desbloqueado una nueva acción."
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
	game_state.flags["player_place_shown"] = true
	special_button.hide()
	status_label.text = "Terry continúa en su sitio."
	save_manager.save_game(game_state)


func debug_hatch_all() -> void:
	for creature_id in TerryGameState.CREATURE_IDS:
		game_state.hatch(creature_id)
	progression.set_phase(game_state, 1)
	_sync_from_state()


func debug_satisfy_phase_one() -> void:
	debug_hatch_all()
	for creature_id in TerryGameState.CREATURE_IDS:
		game_state.creatures[creature_id]["counters"]["fed"] = 2
		game_state.creatures[creature_id]["counters"]["played"] = 1
	game_state.creatures["creature_main"]["counters"]["petted"] = 2
	game_state.creatures["creature_main"]["counters"]["slept"] = 1
	game_state.global_counters["poops_cleaned"] = 1
	game_state.global_counters["care_time"] = 30.0
	progression.evaluate(game_state)
	_refresh_debug()


func debug_complete_post_requirements() -> void:
	if game_state.post_baseline.is_empty():
		game_state.capture_post_dialogue_baseline()
	game_state.creatures["creature_main"]["counters"]["fed"] = int(game_state.post_baseline["creature_main"].get("fed", 0)) + 5
	game_state.creatures["creature_main"]["counters"]["played"] = int(game_state.post_baseline["creature_main"].get("played", 0)) + 5
	game_state.global_counters["poops_cleaned"] = int(game_state.post_baseline["global"].get("poops_cleaned", 0)) + 10
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
	progression.set_phase(game_state, mini(4, game_state.phase + 1))
	_sync_from_state()


func _debug_reset_phase() -> void:
	match game_state.phase:
		0:
			for creature_id in TerryGameState.CREATURE_IDS:
				game_state.eggs[creature_id]["heat"] = 0.0
				game_state.eggs[creature_id]["nutrition"] = 0.0
				game_state.eggs[creature_id]["meal_bites"] = 0
				game_state.eggs[creature_id]["next_meal_unix"] = 0
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
	icon.position = Vector2(12, 2)
	icon.size = Vector2(22, 22)
	icon.texture = _icon_texture(action_id)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	var caption_panel := Panel.new()
	caption_panel.name = "CaptionPanel"
	caption_panel.position = Vector2(3, 25)
	caption_panel.size = Vector2(40, 10)
	caption_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_panel.add_theme_stylebox_override("panel", _stylebox(Color("#FFF3DE"), Color(0.3, 0.25, 0.32, 0.45), 1, 5))
	button.add_child(caption_panel)
	var caption := _make_label(label_text, Vector2(0, -3), Vector2(40, 11), 5)
	caption.name = "Caption"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_color", INK)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_panel.add_child(caption)
	return button


func _icon_texture(action_id: String) -> AtlasTexture:
	var cells := {
		"food": Vector2i(0, 0),
		"pet": Vector2i(1, 0),
		"play": Vector2i(2, 0),
		"sleep": Vector2i(0, 1),
		"clean": Vector2i(1, 1),
		"status": Vector2i(2, 1)
	}
	var cell: Vector2i = cells.get(action_id, Vector2i.ZERO)
	var atlas := AtlasTexture.new()
	atlas.atlas = load(ICON_SHEET)
	atlas.region = Rect2(cell.x * 512, cell.y * 512, 512, 512)
	return atlas


func _tool_texture(tool_id: String) -> AtlasTexture:
	var cells := {
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
	var cell: Vector2i = cells.get(tool_id, Vector2i.ZERO)
	var atlas := AtlasTexture.new()
	atlas.atlas = load(TOOL_CURSOR_SHEET)
	atlas.region = Rect2(cell.x * TOOL_CELL_SIZE, cell.y * TOOL_CELL_SIZE, TOOL_CELL_SIZE, TOOL_CELL_SIZE)
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
			return "TU LADO"
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
