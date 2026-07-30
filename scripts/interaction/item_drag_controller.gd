class_name ItemDragController
extends RefCounted

signal item_armed(item_id: String)
signal item_cancelled(item_id: String)
signal item_dropped(item_id: String, target_kind: String, target_id: String)

var armed_item := ""


func arm(item_id: String) -> void:
	armed_item = item_id
	item_armed.emit(item_id)


func cancel() -> void:
	if armed_item != "":
		var old_item := armed_item
		armed_item = ""
		item_cancelled.emit(old_item)


func drop(target_kind: String, target_id: String, valid: bool) -> bool:
	if armed_item == "":
		return false
	if not valid:
		cancel()
		return false
	var dropped := armed_item
	armed_item = ""
	item_dropped.emit(dropped, target_kind, target_id)
	return true
