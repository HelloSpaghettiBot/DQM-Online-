extends RefCounted
const COBI_SHA = "8e38a7420ef5239c7196aa4fd4b1499e65db2823e875bbf8241bb2199e766d4e"
const MAX_SIZE = 8388608
const Content = preload("res://shared/content.gd")

static func read(path: String, expected_id: String = "cobi") -> Dictionary:
	var data = PackedByteArray()
	var source = FileAccess.open(path, FileAccess.READ)
	if source == null: return {"error": "Could not read this file. Select your ROM again."}
	var is_zip = source.get_length() >= 4 and source.get_32() == 0x04034b50
	source.close()
	# Android document URIs need not have a filename extension.
	if is_zip or path.get_extension().to_lower() == "zip":
		if not _bounded_zip(path): return {"error": "Invalid ZIP or a ROM exceeds the 8 MB import limit."}
		var archive = ZIPReader.new()
		if archive.open(path) != OK: return {"error": "Could not open this ZIP."}
		var candidates = []
		for entry in archive.get_files():
			if entry.get_extension().to_lower() in ["gb", "gbc", "gba"]: candidates.append(entry)
		if candidates.size() != 1:
			archive.close()
			return {"error": "Select a ZIP containing exactly one GB/GBC/GBA ROM."}
		data = archive.read_file(candidates[0])
		archive.close()
	else:
		var file = FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() < 0x150 or file.get_length() > MAX_SIZE:
			return {"error": "Expected a supported local ROM of up to 8 MB."}
		data = file.get_buffer(file.get_length())
	var hash = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(data)
	var digest = hash.finish().hex_encode()
	var id = Content.identify(digest)
	if id.is_empty(): return {"error": "Unrecognized ROM revision. Select an unmodified supported ROM."}
	if not expected_id.is_empty() and id != expected_id:
		return {"error": "This slot requires " + Content.ROMS[expected_id].name + ". Use Menu > Optional ROMs for expansion imports."}
	var metadata = Content.ROMS[id]
	if data.size() != metadata.bytes: return {"error": "ROM size does not match its identity."}
	var checksum = 0
	if metadata.platform == "GBA":
		for i in range(0xa0, 0xbd): checksum = (checksum - data[i]) & 255
		checksum = (checksum - 0x19) & 255
		if checksum != data[0xbd]: return {"error": "GBA header checksum failed."}
	else:
		for i in range(0x134, 0x14d): checksum = (checksum - data[i] - 1) & 255
		if checksum != data[0x14d]: return {"error": "Game Boy header checksum failed."}
	return {"data": data, "sha256": digest, "id": id, "metadata": metadata}

static func _bounded_zip(path: String) -> bool:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 16 * 1024 * 1024 or file.get_length() < 22: return false
	var bytes = file.get_buffer(file.get_length())
	var eocd = -1
	for i in range(bytes.size() - 22, maxi(-1, bytes.size() - 65558), -1):
		if bytes.decode_u32(i) == 0x06054b50:
			eocd = i
			break
	if eocd < 0 or bytes.decode_u16(eocd + 4) != 0 or bytes.decode_u16(eocd + 6) != 0: return false
	var entries = bytes.decode_u16(eocd + 10)
	var cursor = bytes.decode_u32(eocd + 16)
	if entries > 256 or cursor >= eocd: return false
	for _entry in entries:
		if cursor + 46 > eocd or bytes.decode_u32(cursor) != 0x02014b50: return false
		var size = bytes.decode_u32(cursor + 24)
		var name_length = bytes.decode_u16(cursor + 28)
		var extra_length = bytes.decode_u16(cursor + 30)
		var comment_length = bytes.decode_u16(cursor + 32)
		if cursor + 46 + name_length > eocd: return false
		var name = bytes.slice(cursor + 46, cursor + 46 + name_length).get_string_from_utf8()
		if name.get_extension().to_lower() in ["gb", "gbc", "gba"] and (size < 0x150 or size > MAX_SIZE): return false
		cursor += 46 + name_length + extra_length + comment_length
	return cursor <= eocd
