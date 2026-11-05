extends RefCounted
## Device-private optional sources. Never replace the base cartridge or server saves.
const Content = preload("res://shared/content.gd")
const Rom = preload("res://scripts/rom.gd")
var directory: String

func _init(profile_directory: String) -> void:
	directory = profile_directory.path_join("content")

func import_rom(id: String, path: String) -> Dictionary:
	if id not in ["iru", "caravan"]: return {"error": "Invalid optional ROM slot."}
	var result = Rom.read(path, id)
	if result.has("error"): return result
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return {"error": "Could not create private content storage."}
	var target = _path(id)
	var file = FileAccess.open(target + ".tmp", FileAccess.WRITE)
	if file == null: return {"error": "Could not store this ROM on your device."}
	file.store_buffer(result.data)
	file.flush()
	var error = file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(target + ".tmp", target) != OK:
		DirAccess.remove_absolute(target + ".tmp")
		return {"error": "Could not finish importing this ROM."}
	return {"id": id, "imported": true, "playable": Content.ROMS[id].playable}

func status(id: String) -> Dictionary:
	if id not in ["iru", "caravan"]: return {"imported": false, "playable": false}
	var imported = FileAccess.file_exists(_path(id)) and not Rom.read(_path(id), id).has("error")
	return {"imported": imported, "playable": imported and Content.ROMS[id].playable}

func remove(id: String) -> bool:
	if id not in ["iru", "caravan"]: return false
	return not FileAccess.file_exists(_path(id)) or DirAccess.remove_absolute(_path(id)) == OK

func _path(id: String) -> String:
	return directory.path_join(id + "." + Content.ROMS[id].extension)
