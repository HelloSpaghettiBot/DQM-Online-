extends RefCounted
## Stable cosmetic IDs, never game assets. Only complete 16x16 walking actors.
const SPRITES = [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,73,75,76,77,78,79,80,81,82,83,85,87,92,95,97]
const PALETTES = 59
const DEFAULT_PALETTE = 18
static func valid(sprite: int, palette: int) -> bool:
	return sprite in SPRITES and palette >= 0 and palette < PALETTES
