extends SceneTree

var failures: Array[String] = []
var passes := 0


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		passes += 1
		print("PASS: ", message)
	else:
		failures.append(message)
		push_error("FAIL: " + message)


func _finish_dialogue(manager: DialogueManager, state: TerryGameState, option_index: int = 0) -> void:
	var guard := 0
	while manager.is_active() and guard < 30:
		guard += 1
		var node: Dictionary = manager.dialogues[manager.current_dialogue]["nodes"][manager.current_node]
		var options: Array = node.get("options", [])
		if options.is_empty():
			manager.continue_node(state)
		else:
			manager.choose_option(mini(option_index, options.size() - 1), state)


func _run() -> void:
	var state := TerryGameState.new()
	var definitions := CreatureDefinition.load_all()
	var director := ProgressionDirector.new()
	var needs := NeedSystem.new()
	var care_loop := CareLoopSystem.new()
	var saver := SaveManager.new()
	var dialogue_manager := DialogueManager.new()
	var prompt := RequirementPromptSystem.new()
	var drag := ItemDragController.new()

	_check(definitions.size() == 3, "se cargan tres CreatureDefinition")
	_check(state.phase == 0 and not state.all_hatched(), "la partida comienza con tres huevos")
	for creature_id in TerryGameState.CREATURE_IDS:
		state.eggs[creature_id]["care"] = TerryGameState.EGG_CARE_REQUIRED
		state.eggs[creature_id]["nutrition"] = TerryGameState.EGG_NUTRITION_REQUIRED
		state.hatch(creature_id)
	_check(state.all_hatched(), "los huevos nacen de forma independiente")
	director.evaluate(state)
	_check(state.phase == 1, "la incubación conduce a convivencia")

	state.global_counters["neglected_requests"] = 2
	for pre_talk in ["chat_01", "chat_02", "chat_03", "chat_10", "chat_11", "chat_12"]:
		state.mark_dialogue_seen(pre_talk)
	var event_box := {"event": ""}
	director.event_requested.connect(func(event_id: String) -> void: event_box.event = event_id)
	director.evaluate(state)
	_check(event_box.event == "prepare_disappearance", "los requisitos de convivencia preparan la desaparición")

	state.flags["creature_a_disappeared"] = true
	state.creatures["creature_a"]["present"] = false
	state.creatures["creature_a"]["disappeared"] = true
	director.set_phase(state, 2)
	var emitted_texts: Array[String] = []
	dialogue_manager.node_requested.connect(func(_dialogue_id: String, _node_id: String, node: Dictionary) -> void: emitted_texts.append(str(node.text)))
	_check(dialogue_manager.start("dialogue_01", state), "se inicia el diálogo 1 scripteado")
	_check(emitted_texts[-1] == "Se fue.", "la primera frase es fija")
	dialogue_manager.choose_option(0, state)
	_check(state.answers.get("dialogue_01_answer") == "who", "la opción cerrada queda recordada")
	_check(emitted_texts[-1] == "Pipo. El que siempre tenía hambre.", "la rama elegida produce su respuesta escrita")
	_finish_dialogue(dialogue_manager, state)
	_check("dialogue_01" in state.dialogues_seen, "el diálogo completado queda registrado")
	_check(dialogue_manager.start("chat_06", state), "la charla sobre hacer algo malo está disponible")
	_check(
		emitted_texts[-1] == "¿Me querrías si hiciese una cosa mala?",
		"Terry formula la pregunta acordada antes del segundo giro"
	)
	_finish_dialogue(dialogue_manager, state, 1)
	var callback_state := TerryGameState.new()
	callback_state.answers["why_return_answer"] = "love"
	_check(dialogue_manager.start("chat_10", callback_state), "la tercera charla dependiente está disponible")
	var callback_node: Dictionary = dialogue_manager.dialogues["chat_10"]["nodes"]["remember"]
	_check(
		callback_node.get("answer_ref") == "why_return_answer"
		and callback_node.get("text_by_answer", {}).get("love") == "Dijiste que volvías porque me querías.",
		"Terry recuerda la respuesta de una charla anterior"
	)
	_finish_dialogue(dialogue_manager, callback_state)

	state.capture_post_dialogue_baseline()
	director.set_phase(state, 3)
	var loop_now := int(Time.get_unix_time_from_system())
	state.creatures["creature_b"]["next_request_unix"] = loop_now - 1
	var loop_events := care_loop.update(state, definitions, loop_now)
	_check(
		loop_events.any(func(event: Dictionary) -> bool: return event.type == "request_started" and event.request == "play")
		and str(state.creatures["creature_b"]["request"]) == "play",
		"Mota inicia su ciclo pidiendo jugar"
	)
	var request := prompt.choose_prompt(state, director, "creature_b")
	_check(request.get("symbol") == "play" and bool(request.get("persistent", false)), "el aviso refleja la petición activa")
	_check(care_loop.fulfill_request(state, "creature_b", "played", loop_now), "la acción adecuada completa un ciclo de cuidado")
	_check(care_loop.begin_activity(state.creatures["creature_b"], "play", loop_now, TerryGameState.PLAY_DURATION_SECONDS), "jugar inicia un bloque real de una hora")
	loop_events = care_loop.update(state, definitions, loop_now + TerryGameState.PLAY_DURATION_SECONDS)
	_check(
		loop_events.any(func(event: Dictionary) -> bool: return event.type == "activity_finished" and event.activity == "play")
		and str(state.creatures["creature_b"]["request"]) == "food",
		"al terminar de jugar durante una hora aparece una petición de comida"
	)
	state.increment_global("care_cycles_completed", 6)
	for chat_id in ["chat_04", "chat_05", "chat_06"]:
		state.mark_dialogue_seen(chat_id)
	director.reset_event_latch(3)
	event_box.event = ""
	director.evaluate(state)
	_check(event_box.event == "start_dialogue_02", "los ciclos de cuidado post-diálogo desbloquean el diálogo 2")

	drag.arm("food")
	_check(drag.drop("creature", "creature_main", true) and drag.armed_item == "", "el objeto arrastrado se consume en un objetivo válido")
	drag.arm("clean")
	_check(not drag.drop("creature", "creature_main", false), "un objetivo inválido cancela la herramienta")

	var before := float(state.creatures["creature_main"]["needs"]["satiety"])
	needs.apply_action(state.creatures["creature_main"], "fed")
	_check(float(state.creatures["creature_main"]["needs"]["satiety"]) >= before, "NeedSystem aplica efectos de cuidado")
	state.creatures["creature_main"]["needs"]["satiety"] = 100.0
	needs.apply_offline_decay(state, definitions, 60.0 * 60.0 * 24.0 * 30.0)
	_check(float(state.creatures["creature_main"]["needs"]["satiety"]) >= 20.0, "el deterioro offline está limitado y no mata")

	var test_path := "user://terry_the_egg_test_save.json"
	_check(saver.save_game(state, test_path), "SaveManager escribe JSON")
	_check(saver.has_save(test_path), "SaveManager valida una partida continuable")
	var restored := TerryGameState.new()
	_check(saver.load_game(restored, test_path), "SaveManager recupera JSON")
	_check(bool(restored.flags["creature_a_disappeared"]), "la desaparición persiste al cargar")
	_check(restored.answers.get("dialogue_01_answer") == "who", "las respuestas persisten al cargar")
	var legacy_data := restored.to_dict()
	legacy_data["save_version"] = 1
	for creature_id in TerryGameState.CREATURE_IDS:
		legacy_data["eggs"][creature_id]["heat"] = 2.5
		legacy_data["eggs"][creature_id]["heat_required"] = 5.0
		legacy_data["eggs"][creature_id].erase("care")
		legacy_data["eggs"][creature_id].erase("care_required")
		legacy_data["eggs"][creature_id].erase("care_strokes")
		legacy_data["eggs"][creature_id].erase("next_care_unix")
		legacy_data["eggs"][creature_id].erase("meal_bites")
		legacy_data["eggs"][creature_id].erase("next_meal_unix")
		legacy_data["eggs"][creature_id]["nutrition"] = 7.5
		legacy_data["eggs"][creature_id]["nutrition_required"] = 15.0
		legacy_data["creatures"][creature_id].erase("sleep_until_unix")
		legacy_data["creatures"][creature_id].erase("meal_bites")
		legacy_data["creatures"][creature_id].erase("next_meal_unix")
		legacy_data["creatures"][creature_id].erase("poop_due_unix")
		legacy_data["creatures"][creature_id].erase("poops_waiting")
	var migrated := TerryGameState.new()
	_check(
		migrated.load_dict(legacy_data)
		and int(migrated.eggs["creature_main"]["nutrition_required"]) == TerryGameState.EGG_NUTRITION_REQUIRED
		and migrated.eggs["creature_main"].has("next_meal_unix")
		and migrated.eggs["creature_main"].has("next_care_unix")
		and int(migrated.eggs["creature_main"]["care"]) == 6
		and migrated.creatures["creature_main"].has("sleep_until_unix")
		and migrated.creatures["creature_main"].has("poop_due_unix"),
		"los guardados antiguos migran a los temporizadores nuevos"
	)
	saver.delete_save(test_path)

	await process_frame
	await _test_mouse_gestures()
	await _test_integrated_main_flow()
	await _test_story_reconstruction_helpers()
	print("RESULTADO: %d pruebas correctas, %d fallos" % [passes, failures.size()])
	if failures.is_empty():
		quit(0)
	else:
		for failure in failures:
			print(" - ", failure)
		quit(1)


func _test_mouse_gestures() -> void:
	var manager := CursorManager.new()
	root.add_child(manager)
	var egg := EggController.new()
	egg.setup("creature_main", Color("#CEC7EC"), manager)
	root.add_child(egg)
	await process_frame
	var rubs := {"count": 0}
	egg.rubbed.connect(func(_id: String) -> void: rubs.count += 1)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(10, 20)
	egg._on_gui_input(press)
	for point in [Vector2(28, 20), Vector2(8, 20), Vector2(30, 20)]:
		var motion := InputEventMouseMotion.new()
		motion.position = point
		egg._on_gui_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(30, 20)
	egg._on_gui_input(release)
	_check(rubs.count >= 1, "el huevo exige movimiento y cambios de dirección para frotar")
	_check(egg._click_flash > 0.0, "pulsar el huevo produce un destello visual")
	egg._on_mouse_entered()
	_check(manager._current_mode == "rub", "el huevo muestra el cursor artístico de frotar")
	manager.select_tool("food")
	_check(manager._current_mode == "egg_food", "alimentar un huevo usa el cursor de néctar")
	manager.cancel_tool()
	egg._on_mouse_exited()

	var creature := CreatureController.new()
	creature.setup(CreatureDefinition.load_all()["creature_main"], manager)
	root.add_child(creature)
	await process_frame
	var pets := {"count": 0}
	creature.action_requested.connect(func(_id: String, action: String) -> void:
		if action == "pet":
			pets.count += 1
	)
	creature._on_gui_input(press)
	var pet_motion := InputEventMouseMotion.new()
	pet_motion.position = Vector2(35, 20)
	creature._on_gui_input(pet_motion)
	creature._on_gui_input(release)
	_check(pets.count >= 1, "la criatura registra una caricia solo después de recorrido real")
	_check(creature._click_flash > 0.0, "pulsar la criatura produce un destello visual")
	creature._on_mouse_entered()
	_check(manager._current_mode == "pet", "la criatura muestra el cursor artístico de caricia")
	creature._on_mouse_exited()
	creature.react("first_word")
	_check(creature._eye_expression() == "pinprick", "la primera frase activa la mirada de pupila diminuta")
	creature.react("play")
	_check(creature._sprite_row() == 1, "jugar utiliza la pose con el brazo levantado")
	creature.react("eat")
	_check(creature._sprite_row() == 2, "comer utiliza la pose de mandíbula abierta")
	creature.set_sleeping(true)
	_check(creature.state_name == "sleep" and creature._eye_expression() == "normal", "dormir usa un asset completo sin ojos superpuestos")
	creature.set_sleeping(false)
	creature.react("refuse")
	_check(creature.state_name == "refuse", "la negativa activa su pose propia")
	egg.queue_free()
	creature.queue_free()
	manager.queue_free()


func _test_integrated_main_flow() -> void:
	var packed: PackedScene = load("res://scenes/main/main.tscn")
	var game = packed.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	game.save_manager.save_path = "user://terry_the_egg_integration_test_save.json"
	game.save_manager.delete_save()
	_check(game.start_backdrop.visible, "al arrancar aparece el menú de continuar o empezar de cero")
	game._show_exit_menu()
	_check(game.exit_backdrop.visible, "cerrar abre el menú con guardar y salir")
	game._cancel_exit()
	game._start_new_game()
	await process_frame
	_check(game._game_started and game.egg_nodes.size() == 3, "empezar de cero inicia siempre con tres huevos")
	var egg_food_icon: AtlasTexture = game.action_icons["food"].texture
	_check(egg_food_icon.atlas.resource_path.ends_with("action-icons.png"), "la incubación usa el icono propio de néctar")
	var labels_fit := true
	for action_id in game.action_buttons:
		var button: Button = game.action_buttons[action_id]
		var action_name: Label = button.get_node("ActionName")
		labels_fit = (
			labels_fit
			and action_name.position.y + action_name.size.y <= button.size.y
			and action_name.get_minimum_size().x <= action_name.size.x
		)
	_check(labels_fit, "los nombres quedan centrados dentro de sus botones")
	_check(game.theme.default_font.resource_path.ends_with("PixelifySans-Variable.ttf"), "todo el HUD usa la tipografía retro nueva")
	var phase_hint_visible := false
	for visible_label in game.find_children("*", "Label", true, false):
		if visible_label.is_visible_in_tree() and str(visible_label.text).begins_with("FASE"):
			phase_hint_visible = true
	_check(not phase_hint_visible, "la pantalla no revela la fase actual")
	game._on_button_press_feedback(game.action_buttons["food"])
	_check(game.action_buttons["food"].scale.x < 1.0, "los botones responden visualmente al pulsarlos")
	var feed_release := InputEventMouseButton.new()
	feed_release.button_index = MOUSE_BUTTON_LEFT
	feed_release.pressed = false
	feed_release.position = Vector2(32, 42)
	_check(game.egg_nodes["creature_main"].bubble.current_symbol == "pet_request", "el huevo comienza pidiendo mimos con el icono del cursor")
	for _care in TerryGameState.EGG_CARE_CAPACITY:
		game._on_egg_rubbed("creature_main")
	var main_egg: Dictionary = game.game_state.eggs["creature_main"]
	_check(
		int(main_egg["care"]) == 3
		and str(main_egg["visual_state"]) == "crack_25"
		and int(main_egg["next_care_unix"]) > int(Time.get_unix_time_from_system()),
		"la primera tanda de mimos crea la grieta del 25 por ciento"
	)
	var saved_session := TerryGameState.new()
	_check(
		game._save_current_game()
		and game.save_manager.load_game(saved_session)
		and int(saved_session.eggs["creature_main"]["care"]) == 3,
		"guardar y salir conserva el progreso real del huevo"
	)
	game._show_start_menu()
	_check(not game.continue_button.disabled, "una partida guardada habilita Continuar al volver a abrir el juego")
	game.start_backdrop.hide()
	var heart_texture: AtlasTexture = game.egg_nodes["creature_main"].bubble.icon.texture
	_check(heart_texture.atlas.resource_path.ends_with("reaction-symbols.png"), "los corazones usan la nueva hoja de expresiones")
	for _feeding in 2:
		game._on_action_button("food")
		game.egg_nodes["creature_main"]._on_gui_input(feed_release)
		await process_frame
	_check(
		int(game.game_state.eggs["creature_main"]["nutrition"]) == 2
		and int(game.game_state.eggs["creature_main"]["next_meal_unix"]) > int(Time.get_unix_time_from_system()),
		"el huevo acepta un máximo de dos comidas por tanda"
	)
	_check(
		"TOTAL" not in game.status_label.text
		and "/12" not in game.status_label.text
		and "2/2" not in game.status_label.text,
		"la interfaz oculta las cantidades de incubación"
	)
	game._on_action_button("food")
	game.egg_nodes["creature_main"]._on_gui_input(feed_release)
	await process_frame
	_check(
		int(game.game_state.eggs["creature_main"]["nutrition"]) == 2
		and game.egg_nodes["creature_main"].bubble.current_symbol == "no",
		"una tercera comida antes de una hora se rechaza con una X"
	)
	_check("NO TIENE MÁS HAMBRE" in game.status_label.text, "el rechazo de comida utiliza un mensaje amable")
	main_egg["next_care_unix"] = int(Time.get_unix_time_from_system()) - 1
	game.egg_nodes["creature_main"].bubble.clear()
	game._update_egg_requests(false)
	_check(game.egg_nodes["creature_main"].bubble.current_symbol == "pet_request", "tras cinco minutos vuelve a pedir mimos")
	var request_texture: AtlasTexture = game.egg_nodes["creature_main"].bubble.icon.texture
	_check(request_texture.atlas.resource_path.ends_with("action-icons.png"), "el aviso de mimos reutiliza exactamente el arte del cursor")
	for _care_round in 2:
		for _care in TerryGameState.EGG_CARE_CAPACITY:
			game._on_egg_rubbed("creature_main")
		if _care_round == 0:
			_check(str(main_egg["visual_state"]) == "crack_50", "la segunda tanda crea una grieta mayor al 50 por ciento")
		main_egg["next_care_unix"] = int(Time.get_unix_time_from_system()) - 1
		game._update_egg_requests(false)
	_check(
		int(main_egg["care"]) == 9 and str(main_egg["visual_state"]) == "crack_75",
		"la tercera tanda añade otra grieta al 75 por ciento"
	)
	main_egg["next_meal_unix"] = int(Time.get_unix_time_from_system()) - 1
	game._update_egg_requests(false)
	for _feeding in 2:
		game._on_action_button("food")
		game.egg_nodes["creature_main"]._on_gui_input(feed_release)
		await process_frame
	main_egg["next_care_unix"] = int(Time.get_unix_time_from_system()) - 1
	game._update_egg_requests(false)
	for _care in TerryGameState.EGG_CARE_CAPACITY:
		game._on_egg_rubbed("creature_main")
	await create_timer(1.0).timeout
	_check(
		bool(game.game_state.eggs["creature_main"]["hatched"])
		and game.creature_nodes.has("creature_main"),
		"el huevo eclosiona tras dos rondas de néctar y cuatro tandas de mimos"
	)
	game.game_state.reset_all()
	game._sync_from_state()

	game.debug_hatch_all()
	await process_frame
	_check(game.creature_nodes.size() == 3, "la escena sustituye huevos por tres criaturas diferentes")
	var creature_food_icon: AtlasTexture = game.action_icons["food"].texture
	_check(creature_food_icon.atlas.resource_path.ends_with("action-icons.png"), "las criaturas recuperan el icono de cuenco")
	var request_now := int(Time.get_unix_time_from_system())
	for creature_id in TerryGameState.CREATURE_IDS:
		game.game_state.creatures[creature_id]["next_request_unix"] = request_now - 1
	game._update_creature_timers()
	_check(
		game.game_state.creatures["creature_a"]["request"] == "food"
		and game.game_state.creatures["creature_b"]["request"] == "play"
		and game.game_state.creatures["creature_main"]["request"] == "affection",
		"Pipo, Mota y Terry hacen peticiones distintas acordes a su personalidad"
	)
	game.game_state.creatures["creature_a"]["needs"]["satiety"] = 30.0
	for _feeding in 2:
		game.cursor_manager.select_tool("food")
		game.item_drag.arm("food")
		game._on_creature_action("creature_a", "food")
	_check(
		int(game.game_state.creatures["creature_a"]["counters"]["fed"]) == 2
		and int(game.game_state.creatures["creature_a"]["meal_bites"]) == 2,
		"la criatura acepta un máximo de dos comidas por tanda"
	)
	_check(
		game.creature_nodes["creature_a"].bubble.current_symbol == "heart",
		"la criatura agradece la comida siempre con un corazón"
	)
	var poop_due := int(game.game_state.creatures["creature_a"]["poop_due_unix"])
	game.cursor_manager.select_tool("food")
	game.item_drag.arm("food")
	game._on_creature_action("creature_a", "food")
	_check(
		int(game.game_state.creatures["creature_a"]["counters"]["fed"]) == 2
		and game.creature_nodes["creature_a"].state_name == "refuse"
		and game.creature_nodes["creature_a"].bubble.current_symbol == "no",
		"una tercera comida se rechaza con pose y símbolo"
	)
	game.cursor_manager.select_tool("play")
	game._on_creature_action("creature_a", "play")
	_check(
		int(game.game_state.creatures["creature_a"]["poops_waiting"]) == 0
		and int(game.game_state.creatures["creature_a"]["poop_due_unix"]) == poop_due,
		"jugar no genera caca ni altera su hora"
	)
	_check(
		game.game_state.creatures["creature_a"]["activity"] == "play"
		and int(game.game_state.creatures["creature_a"]["activity_until_unix"]) - request_now >= 3599,
		"Jugar deja a la criatura ocupada durante un bloque de una hora"
	)
	_check(
		game.creature_nodes["creature_a"].bubble.current_symbol == "heart",
		"jugar no reutiliza el icono de alimento del huevo"
	)
	game._show_status("creature_a")
	_check(
		game.status_backdrop.visible
		and "ESTÁ JUGANDO" in game.status_details.text
		and "TERMINARÁ" in game.status_details.text,
		"Mirar explica el bloque de juego sin mostrar contadores técnicos"
	)
	game._close_status_window()
	game.game_state.creatures["creature_a"]["activity_until_unix"] = request_now - 1
	game._update_creature_timers()
	_check(
		game.game_state.creatures["creature_a"]["activity"] == ""
		and game.game_state.creatures["creature_a"]["request"] == "food"
		and game.creature_nodes["creature_a"].bubble.current_symbol == "creature_food",
		"al terminar la hora de juego Pipo pide comida"
	)
	game.game_state.creatures["creature_a"]["born_unix"] = request_now - TerryGameState.FIRST_DAY_SECONDS
	game.game_state.creatures["creature_a"]["favorite_care"] = 4
	game._update_creature_timers()
	_check(
		game.game_state.creatures["creature_a"]["body_state"] == "chubby"
		and game.creature_nodes["creature_a"].body_state == "chubby"
		and CreatureController.PIPO_CHUBBY.resource_path.ends_with("pipo-chubby.png"),
		"al final del primer día Pipo utiliza su sprite redondito"
	)
	game.game_state.creatures["creature_a"]["poop_due_unix"] = int(Time.get_unix_time_from_system()) - 1
	game._update_creature_timers()
	_check(game.poop_nodes.size() == 1, "la caca aparece cuando han pasado dos horas desde la comida")

	game._on_creature_action("creature_main", "pet")
	_check(bool(game.game_state.creatures["creature_main"]["ready_to_sleep"]), "la caricia prepara a Terry para dormir")
	_check("(" not in game.status_label.text, "la caricia no enseña el contador interno")
	game._try_sleep("creature_main")
	_check(
		bool(game.game_state.creatures["creature_main"]["sleeping"])
		and int(game.game_state.creatures["creature_main"]["sleep_until_unix"]) - int(Time.get_unix_time_from_system()) >= 3599,
		"Terry duerme durante una hora real después de la caricia"
	)

	game.cursor_manager.select_tool("clean")
	var poop = game.poop_nodes[0]
	game._on_clean_poop(poop)
	_check(int(game.game_state.global_counters["poops_cleaned"]) == 1, "la limpieza actúa sobre una suciedad independiente")

	game.game_state.creatures["creature_b"]["request_deadline_unix"] = int(Time.get_unix_time_from_system()) - 1
	game._update_creature_timers()
	_check(
		bool(game.game_state.flags["first_voice_triggered"])
		and game.game_state.flags["pending_talk_id"] == "chat_01"
		and game.creature_nodes["creature_main"].bubble.current_symbol == "talk",
		"el primer descuido hace que Terry quiera hablar por primera vez"
	)
	_check(
		game.creature_nodes["creature_main"].bubble.icon.texture.resource_path.ends_with("terry-talk.png")
		and game.cursor_manager.get_cursor_texture("talk") != null,
		"el aviso y el cursor de conversación utilizan el retrato específico de Terry"
	)
	game._start_pending_talk()
	_check(game.dialogue.current_dialogue == "chat_01", "el primer aviso abre la primera conversación de Terry")
	_finish_dialogue(game.dialogue, game.game_state)
	game._story_mark_dialogues(["chat_02", "chat_03", "chat_10", "chat_11", "chat_12"])
	game.game_state.global_counters["care_cycles_completed"] = int(
		game.game_state.global_counters.get("care_cycles_at_first_voice", 0)
	) + 1
	game.game_state.creatures["creature_a"]["request_deadline_unix"] = int(Time.get_unix_time_from_system()) - 1
	game._update_creature_timers()
	await process_frame
	_check(
		bool(game.game_state.flags["pending_disappearance"])
		and not bool(game.game_state.flags["creature_a_disappeared"]),
		"el segundo descuido prepara la desaparición sin mostrarla delante del jugador"
	)
	game._on_application_focus_lost()
	game._on_application_focus_returned()
	await process_frame
	_check(
		bool(game.game_state.flags["creature_a_disappeared"])
		and bool(game.game_state.flags["absence_reveal_active"])
		and game.creature_nodes["creature_b"].sleeping
		and game.creature_nodes["creature_main"].sleeping,
		"al volver, Pipo falta y los otros dos aparecen dormidos"
	)
	game._on_creature_action("creature_main", "pet")
	_check("NO RESPONDE" in game.status_label.text, "durante el hallazgo las criaturas no aceptan cuidados")
	await create_timer(4.7).timeout
	_check(
		game.game_state.flags["pending_talk_id"] == "dialogue_01"
		and game.creature_nodes["creature_main"].bubble.current_symbol == "talk"
		and not game.dialogue.is_active(),
		"Terry despierta después del silencio y muestra el aviso de conversación"
	)
	game._start_pending_talk()
	_check(game.dialogue.current_dialogue == "dialogue_01", "el aviso abre la conversación «Se fue»")
	_finish_dialogue(game.dialogue, game.game_state, 1)
	await process_frame
	_check(
		game.game_state.phase == 3
		and not bool(game.game_state.flags["absence_reveal_active"])
		and not game.creature_nodes["creature_b"].sleeping
		and game.game_state.answers.get("dialogue_01_answer") == "pipo",
		"el diálogo 1 guarda las respuestas, despierta a Mota e inicia los contadores nuevos"
	)

	game.debug_complete_post_requirements()
	await process_frame
	_check(game.dialogue.current_dialogue == "dialogue_02", "el flujo integrado desbloquea el segundo diálogo")
	_finish_dialogue(game.dialogue, game.game_state, 2)
	await process_frame
	_check(game.game_state.phase == 4 and "show_player_place" in game.game_state.unlocks, "el diálogo 2 desbloquea Enseñarle tu lado")

	game._show_player_place()
	await create_timer(6.8).timeout
	_check(game.dialogue.current_dialogue == "dialogue_03", "Enseñarle tu lado responde a la pregunta de Terry")
	_finish_dialogue(game.dialogue, game.game_state)
	await process_frame
	_check(
		bool(game.game_state.flags["player_place_shown"]) and game.game_state.phase == 5,
		"el fundido vuelve y la historia continúa después de enseñar el otro lado"
	)
	game.game_state.global_counters["care_cycles_since_talk"] = 2
	game._maybe_offer_talk()
	_check(
		game.game_state.flags["pending_talk_id"] == "chat_07"
		and game.creature_nodes["creature_main"].bubble.current_symbol == "talk",
		"cada dos ciclos de cuidado Terry puede pedir una nueva conversación"
	)
	game._start_pending_talk()
	_check(game.dialogue.current_dialogue == "chat_07", "el icono de hablar abre la pregunta pendiente")
	_finish_dialogue(game.dialogue, game.game_state)
	var persisted := TerryGameState.new()
	_check(game.save_manager.load_game(persisted) and bool(persisted.flags["creature_a_disappeared"]), "el guardado real conserva la desaparición")
	game.save_manager.delete_save()
	game.queue_free()
	await process_frame


func _test_story_reconstruction_helpers() -> void:
	var packed: PackedScene = load("res://scenes/main/main.tscn")
	var game = packed.instantiate()
	root.add_child(game)
	await process_frame
	game.save_manager.save_path = "user://terry_story_navigator_test_save.json"
	game.save_manager.delete_save()
	game._start_new_game()
	await process_frame
	var has_story_access := false
	for button in game.find_children("*", "Button", true, false):
		if str(button.tooltip_text) == "Navegar por la historia" or str(button.text) in ["»", "«"]:
			has_story_access = true
	_check(not has_story_access, "la partida del jugador no muestra accesos para saltar por la historia")
	_check(game.debug_panel == null, "el panel técnico tampoco se construye fuera del editor")
	game._jump_to_story_moment("crack_25")
	await process_frame
	_check(
		int(game.game_state.eggs["creature_main"]["care"]) == 3
		and str(game.game_state.eggs["creature_main"]["visual_state"]) == "crack_25"
		and EggController.EGG_SHEET.resource_path.ends_with("egg-stage-sprites.png"),
		"la primera grieta usa un estado rasterizado de la hoja nueva"
	)
	game._jump_to_story_moment("crack_75")
	await process_frame
	_check(str(game.game_state.eggs["creature_main"]["visual_state"]) == "crack_75", "el navegador permite revisar el huevo casi listo")
	game._jump_to_story_moment("birth")
	await create_timer(1.0).timeout
	_check(game.game_state.all_hatched(), "el hito de nacimiento reproduce la eclosión")
	game._jump_to_story_moment("coexistence")
	await process_frame
	_check(game.game_state.phase == 1 and game.creature_nodes.size() == 3, "el navegador reconstruye la convivencia")
	game._jump_to_story_moment("pipo_chubby")
	await process_frame
	_check(
		game.game_state.creatures["creature_a"]["body_state"] == "chubby"
		and game.creature_nodes["creature_a"].body_state == "chubby",
		"el navegador permite revisar la evolución corporal de Pipo"
	)
	game._jump_to_story_moment("absence")
	await process_frame
	_check(game.game_state.phase == 2 and bool(game.game_state.flags["creature_a_disappeared"]), "el navegador reconstruye la ausencia")
	game._jump_to_story_moment("dialogue_01")
	await process_frame
	_check(game.dialogue.current_dialogue == "dialogue_01", "el navegador abre la primera conversación")
	game._jump_to_story_moment("chat_04")
	await process_frame
	_check(
		game.game_state.phase == 3
		and "dialogue_01" in game.game_state.dialogues_seen
		and game.dialogue.current_dialogue == "chat_04",
		"el navegador recorre las conversaciones intermedias"
	)
	game._jump_to_story_moment("dialogue_02")
	await process_frame
	_check(game.dialogue.current_dialogue == "dialogue_02", "el navegador abre la pregunta sobre el otro lado")
	game._jump_to_story_moment("mota_absence")
	await process_frame
	_check(
		game.game_state.phase == 6
		and bool(game.game_state.flags["creature_b_disappeared"])
		and not game.creature_nodes.has("creature_b"),
		"el navegador reconstruye la desaparición de Mota"
	)
	game._jump_to_story_moment("dialogue_04")
	await process_frame
	_check(game.dialogue.current_dialogue == "dialogue_04", "el navegador abre la confesión de Terry")
	game._jump_to_story_moment("more")
	await process_frame
	_check(game.game_state.phase == 7, "el navegador prepara la petición de más comida")
	game._jump_to_story_moment("dialogue_05")
	await process_frame
	_check(game.dialogue.current_dialogue == "dialogue_05", "el navegador abre la conversación del hambre final")
	game._jump_to_story_moment("ending")
	await process_frame
	_check(
		game.game_state.phase == 8 and bool(game.game_state.flags["true_ending_seen"]),
		"el desenlace verdadero termina con la pregunta al jugador"
	)
	game.save_manager.delete_save()
	game.queue_free()
	await process_frame
