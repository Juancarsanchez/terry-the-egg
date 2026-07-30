class_name SaveManager
extends RefCounted

const SAVE_PATH := "user://terry_the_egg_save.json"


func save_game(state: TerryGameState, path: String = SAVE_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("No se pudo escribir el guardado: " + path)
		return false
	file.store_string(JSON.stringify(state.to_dict(), "\t"))
	return true


func load_game(state: TerryGameState, path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Guardado corrupto")
		return false
	return state.load_dict(parsed)


func delete_save(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)
