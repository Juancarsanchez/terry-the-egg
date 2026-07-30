class_name SaveManager
extends RefCounted

const SAVE_PATH := "user://terry_the_egg_save.json"
const BACKUP_SUFFIX := ".backup"
const TEMP_SUFFIX := ".writing"

var save_path := SAVE_PATH

func save_game(state: TerryGameState, path: String = "") -> bool:
	path = save_path if path.is_empty() else path
	var absolute_path := ProjectSettings.globalize_path(path)
	var temporary_path := absolute_path + TEMP_SUFFIX
	var backup_path := absolute_path + BACKUP_SUFFIX
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error("No se pudo preparar la carpeta del guardado: " + absolute_path.get_base_dir())
		return false
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		push_error("No se pudo escribir el guardado temporal: " + temporary_path)
		return false
	file.store_string(JSON.stringify(state.to_dict(), "\t"))
	file.flush()
	file.close()
	if not _is_valid_save_file(temporary_path):
		DirAccess.remove_absolute(temporary_path)
		push_error("El guardado temporal no superó la validación")
		return false
	DirAccess.remove_absolute(backup_path)
	if FileAccess.file_exists(absolute_path):
		if DirAccess.rename_absolute(absolute_path, backup_path) != OK:
			DirAccess.remove_absolute(temporary_path)
			push_error("No se pudo crear la copia de seguridad del guardado")
			return false
	if DirAccess.rename_absolute(temporary_path, absolute_path) != OK:
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(backup_path, absolute_path)
		push_error("No se pudo completar el guardado")
		return false
	DirAccess.remove_absolute(backup_path)
	return _is_valid_save_file(absolute_path)


func load_game(state: TerryGameState, path: String = "") -> bool:
	path = save_path if path.is_empty() else path
	var absolute_path := ProjectSettings.globalize_path(path)
	if _load_from_path(state, absolute_path):
		return true
	return _load_from_path(state, absolute_path + BACKUP_SUFFIX)


func _load_from_path(state: TerryGameState, absolute_path: String) -> bool:
	if not FileAccess.file_exists(absolute_path):
		return false
	var file := FileAccess.open(absolute_path, FileAccess.READ)
	if file == null:
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Guardado corrupto")
		return false
	return state.load_dict(parsed)


func delete_save(path: String = "") -> bool:
	path = save_path if path.is_empty() else path
	var absolute_path := ProjectSettings.globalize_path(path)
	var success := true
	for candidate in [absolute_path, absolute_path + BACKUP_SUFFIX, absolute_path + TEMP_SUFFIX]:
		if FileAccess.file_exists(candidate):
			success = DirAccess.remove_absolute(candidate) == OK and success
	return success


func has_save(path: String = "") -> bool:
	path = save_path if path.is_empty() else path
	var absolute_path := ProjectSettings.globalize_path(path)
	return _is_valid_save_file(absolute_path) or _is_valid_save_file(absolute_path + BACKUP_SUFFIX)


func _is_valid_save_file(absolute_path: String) -> bool:
	if not FileAccess.file_exists(absolute_path):
		return false
	var file := FileAccess.open(absolute_path, FileAccess.READ)
	if file == null:
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return false
	var version := int(parsed.get("save_version", 0))
	return version >= 1 and version <= TerryGameState.SAVE_VERSION
