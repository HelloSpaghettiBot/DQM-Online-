extends RefCounted
## Decode artwork in memory from the user's verified USA ROM. No network/assets.
const Appearance = preload("res://shared/appearance.gd")
const ROM_HASH = preload("res://shared/content.gd").ROMS.cobi.sha256
var records: Array[PackedByteArray] = []
var palettes: Array[PackedByteArray] = []
var textures: Dictionary = {}

func load_rom(rom: PackedByteArray) -> bool:
	records.clear()
	palettes.clear()
	textures.clear()
	var hash = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(rom)
	if hash.finish().hex_encode() != ROM_HASH: return false
	var at = 0x1f4001
	for id in 98:
		if id == 80: at = 0x1f8001
		var length = int(rom[at]) | (int(rom[at + 1]) << 8)
		var escape = rom[at + 2]
		at += 3
		if length < 64 or length > 512 or length % 16 != 0: return false
		var result = PackedByteArray()
		while result.size() < length:
			var value = rom[at]
			at += 1
			if value != escape:
				result.append(value)
				continue
			var offset = int(rom[at]) | ((int(rom[at + 1]) >> 4) << 8)
			var count = (int(rom[at + 1]) & 15) + 4
			at += 2
			if count == 19:
				count += int(rom[at])
				at += 1
			if result.size() + count > length: return false
			for i in count: result.append(result[offset + i] if offset + i < result.size() else 0)
		records.append(result)
	if at != 0x1f8b15: return false
	for id in Appearance.PALETTES: palettes.append(rom.slice(at + id * 8, at + (id + 1) * 8))
	return true

func tiles(id: int) -> PackedByteArray:
	if records.is_empty() or id not in Appearance.SPRITES: return PackedByteArray()
	var source = records[id]
	var result = PackedByteArray()
	var mapping = range(16)
	if source.size() <= 208:
		mapping = [0,1,2,3,4,5,6,7,2,3,8,9,10,11,10,11]
	elif source.size() < 256:
		mapping = [0,1,2,3,4,5,6,7,8,9,10,11,12,13,12,13]
	for tile in mapping: result.append_array(source.slice(tile * 16, tile * 16 + 16))
	return result

func texture(id: int, palette: int, facing: int) -> Texture2D:
	if records.is_empty() or not Appearance.valid(id, palette): return null
	var key = "%d:%d:%d" % [id, palette, facing]
	if textures.has(key): return textures[key]
	var image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var data = tiles(id)
	var colors = palettes[palette]
	var first_tile = [0, 10, 4, 4][clampi(facing, 0, 3)]
	for y in 16:
		for x in 16:
			var source_x = 15 - x if facing == 2 else x
			var tile = first_tile + (y / 8) * 2 + source_x / 8
			var row = tile * 16 + (y % 8) * 2
			var index = ((data[row] >> (7 - source_x % 8)) & 1) | (((data[row + 1] >> (7 - source_x % 8)) & 1) << 1)
			if index == 0: continue
			var rgb = int(colors[index * 2]) | (int(colors[index * 2 + 1]) << 8)
			# Match the native RGB565 output exactly.
			var green = (rgb >> 5) & 31
			image.set_pixel(x, y, Color8((rgb & 31) * 255 / 31, ((green << 1) | (green >> 4)) * 255 / 63, ((rgb >> 10) & 31) * 255 / 31))
	var value = ImageTexture.create_from_image(image)
	textures[key] = value
	return value
