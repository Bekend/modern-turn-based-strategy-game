class_name AssetHelper
extends RefCounted

## Procedural 8-bit retro pixel art texture generator.
## Builds crisp 16x16 pixel sprites and a unified TileSet at runtime,
## ensuring the prototype is immediately playable without external asset dependencies.

const CELL_SIZE: int = 16
const ATLAS_COLS: int = 8
const ATLAS_ROWS: int = 8

# Atlas Coordinates
const ATLAS_OCEAN = Vector2i(0, 0)
const ATLAS_PLAINS = Vector2i(1, 0)
const ATLAS_HILLS = Vector2i(2, 0)
const ATLAS_MOUNTAINS = Vector2i(3, 0)
const ATLAS_TUNDRA = Vector2i(4, 0)
const ATLAS_REACHABLE_OVERLAY = Vector2i(5, 0)
const ATLAS_ATTACK_OVERLAY = Vector2i(6, 0)
const ATLAS_SELECT_CURSOR = Vector2i(7, 0)

const ATLAS_RICE = Vector2i(0, 1)
const ATLAS_IRON = Vector2i(1, 1)
const ATLAS_HORSES = Vector2i(2, 1)
const ATLAS_FARM = Vector2i(3, 1)
const ATLAS_MINE = Vector2i(4, 1)
const ATLAS_ENCAMPMENT = Vector2i(5, 1)
const ATLAS_SCIENCE_CAMP = Vector2i(6, 1)
const ATLAS_TERRITORY_BORDER = Vector2i(7, 1)

const ATLAS_CITY = Vector2i(0, 2)
const ATLAS_REACHABLE_COST1 = Vector2i(1, 2)
const ATLAS_REACHABLE_COST2 = Vector2i(2, 2)
const ATLAS_REACHABLE_COST3 = Vector2i(3, 2)
const ATLAS_GOLD_ORE = Vector2i(4, 2)
const ATLAS_GEMS = Vector2i(5, 2)
const ATLAS_MARKET = Vector2i(6, 2)
const ATLAS_CASTLE = Vector2i(7, 2)
const ATLAS_AQUEDUCT = Vector2i(0, 3)
const ATLAS_PASTURE = Vector2i(1, 3)
const ATLAS_SCIENCE_NODE = Vector2i(2, 3)
const ATLAS_NEIGHBORHOOD = Vector2i(3, 3)
const ATLAS_BORDER_WALL = Vector2i(4, 3)
const ATLAS_TEMPORARY_CAMP = Vector2i(5, 3)
const ATLAS_HARBOR = Vector2i(6, 3)
const ATLAS_NITER = Vector2i(7, 3)
const ATLAS_BORDER_WALL_BADGE = Vector2i(0, 4)
const ATLAS_DISTRICT_VALID = Vector2i(1, 4)


## Creates the complete 8-bit TileSet with nearest-neighbor texture filtering
static func create_procedural_tileset() -> TileSet:
	var atlas_width = ATLAS_COLS * CELL_SIZE
	var atlas_height = ATLAS_ROWS * CELL_SIZE

	var image = Image.create(atlas_width, atlas_height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0)) # Transparent background

	# Draw 8-bit terrain tiles
	_draw_ocean(image, ATLAS_OCEAN)
	_draw_plains(image, ATLAS_PLAINS)
	_draw_hills(image, ATLAS_HILLS)
	_draw_mountains(image, ATLAS_MOUNTAINS)
	_draw_tundra(image, ATLAS_TUNDRA)

	# Overlays & Indicators
	_draw_reachable(image, ATLAS_REACHABLE_OVERLAY)
	_draw_attack_indicator(image, ATLAS_ATTACK_OVERLAY)
	_draw_cursor(image, ATLAS_SELECT_CURSOR)

	# Resources & Improvements
	_draw_rice(image, ATLAS_RICE)
	_draw_iron(image, ATLAS_IRON)
	_draw_horses(image, ATLAS_HORSES)
	_draw_farm(image, ATLAS_FARM)
	_draw_mine(image, ATLAS_MINE)
	_draw_encampment(image, ATLAS_ENCAMPMENT)
	_draw_science_camp(image, ATLAS_SCIENCE_CAMP)
	_draw_territory_border(image, ATLAS_TERRITORY_BORDER)

	# New Era Content
	_draw_gold_ore(image, ATLAS_GOLD_ORE)
	_draw_gems(image, ATLAS_GEMS)
	_draw_market(image, ATLAS_MARKET)
	_draw_castle(image, ATLAS_CASTLE)
	_draw_aqueduct(image, ATLAS_AQUEDUCT)
	_draw_pasture(image, ATLAS_PASTURE)
	_draw_science_node(image, ATLAS_SCIENCE_NODE)
	_draw_neighborhood(image, ATLAS_NEIGHBORHOOD)
	_draw_border_wall(image, ATLAS_BORDER_WALL)
	_draw_temporary_camp(image, ATLAS_TEMPORARY_CAMP)
	_draw_harbor(image, ATLAS_HARBOR)
	_draw_niter(image, ATLAS_NITER)
	_draw_border_wall_badge(image, ATLAS_BORDER_WALL_BADGE)
	_draw_district_valid(image, ATLAS_DISTRICT_VALID)

	# Overlays with MP Numbers
	_draw_city(image, ATLAS_CITY)
	_draw_reachable_cost(image, ATLAS_REACHABLE_COST1, 1)
	_draw_reachable_cost(image, ATLAS_REACHABLE_COST2, 2)
	_draw_reachable_cost(image, ATLAS_REACHABLE_COST3, 3)

	var texture = ImageTexture.create_from_image(image)

	var tileset = TileSet.new()
	tileset.tile_size = Vector2i(CELL_SIZE, CELL_SIZE)

	var source = TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(CELL_SIZE, CELL_SIZE)

	# Register all active tiles in atlas
	for y in range(5):
		for x in range(ATLAS_COLS):
			source.create_tile(Vector2i(x, y))

	tileset.add_source(source, 0)
	return tileset

# -------------------------------------------------------------
# 8-BIT PROCEDURAL PIXEL DRAWING ROUTINES
# -------------------------------------------------------------

static func _draw_ocean(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_base = Color("1a3a60")
	var c_deep = Color("10243d")
	var c_wave = Color("3895d3")
	var c_crest = Color("90e0ef")

	for y in range(CELL_SIZE):
		for x in range(CELL_SIZE):
			var c = c_base if (x + y) % 3 != 0 else c_deep
			img.set_pixel(ox + x, oy + y, c)

	# Wave crest lines
	for x in range(2, 6):
		img.set_pixel(ox + x, oy + 4, c_wave)
	img.set_pixel(ox + 4, oy + 3, c_crest)

	for x in range(9, 14):
		img.set_pixel(ox + x, oy + 10, c_wave)
	img.set_pixel(ox + 11, oy + 9, c_crest)
	_apply_tile_grid(img, ox, oy)

static func _apply_tile_grid(img: Image, ox: int, oy: int) -> void:
	var c_border = Color(0.0, 0.0, 0.0, 0.40)
	for i in range(CELL_SIZE):
		img.set_pixel(ox + i, oy + CELL_SIZE - 1, c_border)
		img.set_pixel(ox + CELL_SIZE - 1, oy + i, c_border)


static func _draw_plains(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_base = Color("2e7d32")
	var c_shade = Color("1b5e20")
	var c_blade = Color("81c784")
	var c_flower = Color("fff59d")

	for y in range(CELL_SIZE):
		for x in range(CELL_SIZE):
			var c = c_base if (x + y) % 2 == 0 else c_shade
			img.set_pixel(ox + x, oy + y, c)

	# Grass tufts
	img.set_pixel(ox + 3, oy + 5, c_blade)
	img.set_pixel(ox + 3, oy + 4, c_blade)
	img.set_pixel(ox + 4, oy + 3, c_blade)

	img.set_pixel(ox + 11, oy + 12, c_blade)
	img.set_pixel(ox + 12, oy + 11, c_blade)
	img.set_pixel(ox + 12, oy + 10, c_blade)
	img.set_pixel(ox + 7, oy + 8, c_flower)
	_apply_tile_grid(img, ox, oy)

static func _draw_hills(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_base = Color("5d4037")
	var c_light = Color("8d6e63")
	var c_dark = Color("3e2723")

	for y in range(CELL_SIZE):
		for x in range(CELL_SIZE):
			img.set_pixel(ox + x, oy + y, c_base)

	# 8-bit rounded hill contour with rock shelf (peak at top, wide base at bottom)
	for x in range(2, 14):
		for y in range(6, 15):
			var dist = absf(float(x) - 8.0) + float(14 - y) * 0.7
			if dist <= 6.5:
				var c = c_light if x < 8 else c_dark
				img.set_pixel(ox + x, oy + y, c)

	# Rock shelf lines and peak highlight
	for x in range(5, 11):
		img.set_pixel(ox + x, oy + 10, Color("bcaaa4"))
	img.set_pixel(ox + 8, oy + 6, Color("d7ccc8"))
	_apply_tile_grid(img, ox, oy)

static func _draw_mountains(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_base = Color("263238")
	var c_rock_l = Color("78909c")
	var c_rock_d = Color("455a64")
	var c_snow = Color("eceff1")

	for y in range(CELL_SIZE):
		for x in range(CELL_SIZE):
			img.set_pixel(ox + x, oy + y, c_base)

	# Triangular peak
	for y in range(2, 15):
		var span = int(float(y - 2) * 0.9)
		for x in range(8 - span, 8 + span + 1):
			if x >= 0 and x < CELL_SIZE:
				var c: Color
				if y <= 5:
					c = c_snow
				elif x < 8:
					c = c_rock_l
				else:
					c = c_rock_d
				img.set_pixel(ox + x, oy + y, c)
	_apply_tile_grid(img, ox, oy)

static func _draw_tundra(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_base = Color("90a4ae")
	var c_snow = Color("cfd8dc")

	for y in range(CELL_SIZE):
		for x in range(CELL_SIZE):
			var c = c_snow if (x * 3 + y * 5) % 7 == 0 else c_base
			img.set_pixel(ox + x, oy + y, c)
	_apply_tile_grid(img, ox, oy)

static func _draw_reachable(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_rim = Color(0.0, 0.9, 1.0, 0.85)
	var c_center = Color(0.0, 0.6, 0.9, 0.30)

	for y in range(CELL_SIZE):
		for x in range(CELL_SIZE):
			if x == 0 or x == CELL_SIZE - 1 or y == 0 or y == CELL_SIZE - 1:
				img.set_pixel(ox + x, oy + y, c_rim)
			else:
				img.set_pixel(ox + x, oy + y, c_center)

## Draws reachable tile with a clear 8-bit movement cost number
static func _draw_reachable_cost(img: Image, slot: Vector2i, cost: int) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_rim = Color(0.0, 0.9, 1.0, 0.9)
	var c_fill = Color(0.0, 0.4, 0.8, 0.35)
	var c_num = Color(1.0, 1.0, 1.0, 1.0)
	var c_shadow = Color(0.0, 0.0, 0.0, 0.9)

	# Background tile
	for y in range(CELL_SIZE):
		for x in range(CELL_SIZE):
			if x == 0 or x == CELL_SIZE - 1 or y == 0 or y == CELL_SIZE - 1:
				img.set_pixel(ox + x, oy + y, c_rim)
			else:
				img.set_pixel(ox + x, oy + y, c_fill)

	# Center number badge
	var cx = ox + 7
	var cy = oy + 6

	if cost == 1:
		# Digit '1'
		for y in range(cy - 2, cy + 3):
			img.set_pixel(cx + 1, y, c_shadow)
			img.set_pixel(cx, y, c_num)
		img.set_pixel(cx - 1, cy - 1, c_num)
		for x in range(cx - 2, cx + 3):
			img.set_pixel(x, cy + 2, c_num)
	elif cost == 2:
		# Digit '2'
		for x in range(cx - 2, cx + 3):
			img.set_pixel(x, cy - 2, c_num)
			img.set_pixel(x, cy, c_num)
			img.set_pixel(x, cy + 2, c_num)
		img.set_pixel(cx + 2, cy - 1, c_num)
		img.set_pixel(cx - 2, cy + 1, c_num)
	elif cost == 3:
		# Digit '3'
		for x in range(cx - 2, cx + 3):
			img.set_pixel(x, cy - 2, c_num)
			img.set_pixel(x, cy, c_num)
			img.set_pixel(x, cy + 2, c_num)
		img.set_pixel(cx + 2, cy - 1, c_num)
		img.set_pixel(cx + 2, cy + 1, c_num)

static func _draw_attack_indicator(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_red = Color(1.0, 0.15, 0.15, 0.95)
	var c_fill = Color(0.9, 0.1, 0.1, 0.40)

	for y in range(CELL_SIZE):
		for x in range(CELL_SIZE):
			if x == y or x == (CELL_SIZE - 1 - y) or x == 0 or x == 15 or y == 0 or y == 15:
				img.set_pixel(ox + x, oy + y, c_red)
			else:
				img.set_pixel(ox + x, oy + y, c_fill)

static func _draw_cursor(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_gold = Color("ffd700")

	for i in range(5):
		img.set_pixel(ox + i, oy, c_gold)
		img.set_pixel(ox, oy + i, c_gold)

		img.set_pixel(ox + CELL_SIZE - 1 - i, oy, c_gold)
		img.set_pixel(ox + CELL_SIZE - 1, oy + i, c_gold)

		img.set_pixel(ox + i, oy + CELL_SIZE - 1, c_gold)
		img.set_pixel(ox, oy + CELL_SIZE - 1 - i, c_gold)

		img.set_pixel(ox + CELL_SIZE - 1 - i, oy + CELL_SIZE - 1, c_gold)
		img.set_pixel(ox + CELL_SIZE - 1, oy + CELL_SIZE - 1 - i, c_gold)

static func _draw_rice(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_gold = Color("ffd166")
	var c_stem = Color("06d6a0")

	for y in range(6, 14):
		img.set_pixel(ox + 8, oy + y, c_stem)
	img.set_pixel(ox + 7, oy + 5, c_gold)
	img.set_pixel(ox + 8, oy + 4, c_gold)
	img.set_pixel(ox + 9, oy + 5, c_gold)
	img.set_pixel(ox + 6, oy + 7, c_gold)
	img.set_pixel(ox + 10, oy + 7, c_gold)

static func _draw_iron(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_ore = Color("e63946")
	var c_metal = Color("8d99ae")

	img.set_pixel(ox + 5, oy + 8, c_ore)
	img.set_pixel(ox + 6, oy + 8, c_ore)
	img.set_pixel(ox + 6, oy + 9, c_metal)
	img.set_pixel(ox + 9, oy + 7, c_metal)
	img.set_pixel(ox + 10, oy + 7, c_ore)
	img.set_pixel(ox + 10, oy + 8, c_ore)

static func _draw_horses(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_body = Color("a74f20")       # Rich chestnut coat
	var c_light = Color("c86a34")      # Highlighted flank
	var c_dark = Color("2d160c")       # Mane, tail, and hooves
	var c_muzzle = Color("d99f70")     # Tan muzzle
	var c_eye = Color("1a0b05")        # Dark eye

	# Ears
	img.set_pixel(ox + 4, oy + 2, c_dark)
	img.set_pixel(ox + 5, oy + 3, c_body)

	# Mane
	img.set_pixel(ox + 6, oy + 3, c_dark)
	img.set_pixel(ox + 7, oy + 4, c_dark)
	img.set_pixel(ox + 7, oy + 5, c_dark)
	img.set_pixel(ox + 8, oy + 6, c_dark)
	img.set_pixel(ox + 8, oy + 7, c_dark)

	# Head & Muzzle
	img.set_pixel(ox + 3, oy + 4, c_muzzle)
	img.set_pixel(ox + 4, oy + 4, c_body)
	img.set_pixel(ox + 5, oy + 4, c_body)
	img.set_pixel(ox + 3, oy + 5, c_muzzle)
	img.set_pixel(ox + 4, oy + 5, c_body)
	img.set_pixel(ox + 5, oy + 5, c_body)
	img.set_pixel(ox + 4, oy + 4, c_eye) # Eye

	# Neck & Shoulder
	img.set_pixel(ox + 5, oy + 6, c_body)
	img.set_pixel(ox + 6, oy + 6, c_body)
	img.set_pixel(ox + 7, oy + 6, c_body)
	img.set_pixel(ox + 5, oy + 7, c_body)
	img.set_pixel(ox + 6, oy + 7, c_light)
	img.set_pixel(ox + 7, oy + 7, c_body)

	# Body & Torso
	for x in range(6, 12):
		img.set_pixel(ox + x, oy + 8, c_body)
	for x in range(5, 12):
		img.set_pixel(ox + x, oy + 9, c_light if (x in [7, 8, 9]) else c_body)
	for x in range(5, 12):
		img.set_pixel(ox + x, oy + 10, c_body)

	# Flowing Tail
	img.set_pixel(ox + 12, oy + 8, c_dark)
	img.set_pixel(ox + 13, oy + 9, c_dark)
	img.set_pixel(ox + 13, oy + 10, c_dark)
	img.set_pixel(ox + 14, oy + 11, c_dark)
	img.set_pixel(ox + 13, oy + 12, c_dark)

	# Forelegs & Hooves
	img.set_pixel(ox + 5, oy + 11, c_body)
	img.set_pixel(ox + 5, oy + 12, c_body)
	img.set_pixel(ox + 5, oy + 13, c_dark)
	img.set_pixel(ox + 7, oy + 11, c_body)
	img.set_pixel(ox + 7, oy + 12, c_body)
	img.set_pixel(ox + 7, oy + 13, c_dark)

	# Hindlegs & Hooves
	img.set_pixel(ox + 10, oy + 11, c_body)
	img.set_pixel(ox + 10, oy + 12, c_body)
	img.set_pixel(ox + 10, oy + 13, c_dark)
	img.set_pixel(ox + 12, oy + 11, c_body)
	img.set_pixel(ox + 12, oy + 12, c_body)
	img.set_pixel(ox + 12, oy + 13, c_dark)

static func _draw_farm(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_furrow = Color("582f0e")
	var c_crop = Color("aacc00")

	for y in range(3, 14, 3):
		for x in range(2, 14):
			img.set_pixel(ox + x, oy + y, c_furrow)
			if x % 2 == 0:
				img.set_pixel(ox + x, oy + y - 1, c_crop)

static func _draw_mine(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_wood = Color("7f4f24")
	var c_black = Color("1b1b1e")

	for y in range(6, 14):
		img.set_pixel(ox + 4, oy + y, c_wood)
		img.set_pixel(ox + 11, oy + y, c_wood)
	for x in range(3, 13):
		img.set_pixel(ox + x, oy + 6, c_wood)
	for y in range(7, 14):
		for x in range(5, 11):
			img.set_pixel(ox + x, oy + y, c_black)

static func _draw_encampment(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_palisade = Color("b08968")
	var c_red_tent = Color("d90429")

	for x in range(2, 14, 2):
		for y in range(9, 14):
			img.set_pixel(ox + x, oy + y, c_palisade)
		img.set_pixel(ox + x, oy + 8, c_palisade)

	for y in range(3, 8):
		var span = y - 3
		for x in range(8 - span, 8 + span + 1):
			img.set_pixel(ox + x, oy + y, c_red_tent)

static func _draw_science_camp(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_blue = Color("0077b6")
	var c_cyan = Color("90e0ef")

	for y in range(5, 13):
		for x in range(4, 12):
			img.set_pixel(ox + x, oy + y, c_blue)
	img.set_pixel(ox + 7, oy + 4, c_cyan)
	img.set_pixel(ox + 8, oy + 4, c_cyan)

static func _draw_territory_border(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_border = Color(1.0, 1.0, 1.0, 0.4)

	for x in range(CELL_SIZE):
		img.set_pixel(ox + x, oy, c_border)
		img.set_pixel(ox + x, oy + CELL_SIZE - 1, c_border)
	for y in range(CELL_SIZE):
		img.set_pixel(ox, oy + y, c_border)
		img.set_pixel(ox + CELL_SIZE - 1, oy + y, c_border)

static func _draw_city(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_stone = Color("495057")
	var c_wall = Color("ced4da")
	var c_gate = Color("212529")
	var c_roof = Color("d90429")

	for y in range(6, 14):
		for x in range(3, 13):
			img.set_pixel(ox + x, oy + y, c_wall)
	for x in range(3, 13, 2):
		img.set_pixel(ox + x, oy + 5, c_stone)
		img.set_pixel(ox + x, oy + 4, c_roof)
	for y in range(9, 14):
		for x in range(7, 9):
			img.set_pixel(ox + x, oy + y, c_gate)

static func _draw_gold_ore(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_gold = Color("f1c40f")
	var c_dark_gold = Color("d4ac0d")
	var c_shine = Color("fef9e7")

	for y in range(6, 11):
		for x in range(5, 11):
			img.set_pixel(ox + x, oy + y, c_gold)
	img.set_pixel(ox + 6, oy + 5, c_gold)
	img.set_pixel(ox + 9, oy + 5, c_dark_gold)
	img.set_pixel(ox + 6, oy + 7, c_shine)
	img.set_pixel(ox + 9, oy + 10, c_dark_gold)

static func _draw_gems(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_gem = Color("9b59b6")
	var c_gem_dark = Color("6c3483")
	var c_sparkle = Color("f4ecf7")

	for y in range(5, 11):
		for x in range(6, 11):
			img.set_pixel(ox + x, oy + y, c_gem)
	img.set_pixel(ox + 7, oy + 4, c_gem)
	img.set_pixel(ox + 9, oy + 4, c_gem)
	img.set_pixel(ox + 7, oy + 6, c_sparkle)
	img.set_pixel(ox + 8, oy + 10, c_gem_dark)

static func _draw_market(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_red = Color("e74c3c")
	var c_white = Color("ecf0f1")
	var c_wood = Color("7f4f24")

	for x in range(3, 13):
		var c = c_red if (x % 2 == 0) else c_white
		img.set_pixel(ox + x, oy + 4, c)
		img.set_pixel(ox + x, oy + 5, c)
	for y in range(6, 13):
		img.set_pixel(ox + 3, oy + y, c_wood)
		img.set_pixel(ox + 12, oy + y, c_wood)
	for x in range(4, 12):
		img.set_pixel(ox + x, oy + 10, c_wood)

static func _draw_aqueduct(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_stone = Color("bdc3c7")
	var c_dark_stone = Color("7f8c8d")
	var c_water = Color("3498db")

	for x in range(2, 14):
		img.set_pixel(ox + x, oy + 5, c_stone)
		img.set_pixel(ox + x, oy + 6, c_water)
		img.set_pixel(ox + x, oy + 7, c_stone)
	for y in range(8, 14):
		img.set_pixel(ox + 3, oy + y, c_dark_stone)
		img.set_pixel(ox + 4, oy + y, c_stone)
		img.set_pixel(ox + 11, oy + y, c_stone)
		img.set_pixel(ox + 12, oy + y, c_dark_stone)

static func _draw_castle(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_stone = Color("95a5a6")
	var c_shadow = Color("566573")
	var c_banner = Color("e74c3c")

	for y in range(6, 14):
		for x in range(3, 13):
			img.set_pixel(ox + x, oy + y, c_stone)
	for x in range(3, 13, 2):
		img.set_pixel(ox + x, oy + 4, c_stone)
		img.set_pixel(ox + x, oy + 5, c_stone)
	img.set_pixel(ox + 7, oy + 2, c_banner)
	img.set_pixel(ox + 7, oy + 3, c_banner)
	for y in range(10, 14):
		for x in range(7, 9):
			img.set_pixel(ox + x, oy + y, c_shadow)

static func _draw_pasture(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_post = Color("8c562e")
	var c_rail = Color("c49a6c")
	var c_grass = Color("6b8e23")

	# Wooden rail fence
	for x in range(2, 14):
		img.set_pixel(ox + x, oy + 7, c_rail)
		img.set_pixel(ox + x, oy + 11, c_rail)
	for y in range(5, 14):
		img.set_pixel(ox + 3, oy + y, c_post)
		img.set_pixel(ox + 8, oy + y, c_post)
		img.set_pixel(ox + 13, oy + y, c_post)
	img.set_pixel(ox + 5, oy + 9, c_grass)
	img.set_pixel(ox + 10, oy + 9, c_grass)

static func _draw_science_node(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_border = Color("003859")     # Deep navy border
	var c_outer = Color("0098cc")      # Vibrant sapphire rim
	var c_core = Color("00e5ff")       # Vivid cyan core
	var c_sparkle = Color("e0f7fa")    # Bright white-cyan highlight dot

	# Small 4x4 subtle blue dot on the top-left of the tile (pixels (1,1) to (4,4))
	# Top rim
	img.set_pixel(ox + 2, oy + 1, c_border)
	img.set_pixel(ox + 3, oy + 1, c_border)

	# Row 2
	img.set_pixel(ox + 1, oy + 2, c_border)
	img.set_pixel(ox + 2, oy + 2, c_sparkle)
	img.set_pixel(ox + 3, oy + 2, c_core)
	img.set_pixel(ox + 4, oy + 2, c_border)

	# Row 3
	img.set_pixel(ox + 1, oy + 3, c_border)
	img.set_pixel(ox + 2, oy + 3, c_core)
	img.set_pixel(ox + 3, oy + 3, c_outer)
	img.set_pixel(ox + 4, oy + 3, c_border)

	# Bottom rim
	img.set_pixel(ox + 2, oy + 4, c_border)
	img.set_pixel(ox + 3, oy + 4, c_border)

static func _draw_neighborhood(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_grass = Color("2e7d32")
	var c_roof_red = Color("c0392b")
	var c_roof_blue = Color("2980b9")
	var c_wall1 = Color("eceff1")
	var c_wall2 = Color("cfd8dc")
	var c_wood = Color("5d4037")
	var c_window = Color("f1c40f")
	var c_path = Color("78909c")

	# Ground
	for y in range(CELL_SIZE):
		for x in range(CELL_SIZE):
			img.set_pixel(ox + x, oy + y, c_grass)

	# Cobblestone pathway
	for y in range(10, 15):
		img.set_pixel(ox + 7, oy + y, c_path)
		img.set_pixel(ox + 8, oy + y, c_path)

	# Left Cottage (Red Roof)
	for x in range(2, 7):
		img.set_pixel(ox + x, oy + 6, c_roof_red)
	for x in range(3, 6):
		img.set_pixel(ox + x, oy + 5, c_roof_red)
	img.set_pixel(ox + 4, oy + 4, c_roof_red)

	for y in range(7, 12):
		for x in range(2, 7):
			img.set_pixel(ox + x, oy + y, c_wall1)
	img.set_pixel(ox + 4, oy + 8, c_window) # Lit window
	img.set_pixel(ox + 4, oy + 10, c_wood)  # Door
	img.set_pixel(ox + 4, oy + 11, c_wood)

	# Right Cottage (Blue Roof)
	for x in range(9, 14):
		img.set_pixel(ox + x, oy + 7, c_roof_blue)
	for x in range(10, 13):
		img.set_pixel(ox + x, oy + 6, c_roof_blue)
	img.set_pixel(ox + 11, oy + 5, c_roof_blue)

	for y in range(8, 13):
		for x in range(9, 14):
			img.set_pixel(ox + x, oy + y, c_wall2)
	img.set_pixel(ox + 11, oy + 9, c_window) # Lit window
	img.set_pixel(ox + 10, oy + 11, c_wood)  # Door
	img.set_pixel(ox + 10, oy + 12, c_wood)

static func _draw_border_wall(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_stone_l = Color("78909c")
	var c_stone_m = Color("546e7a")
	var c_stone_d = Color("37474f")
	var c_mortar = Color("263238")
	var c_iron = Color("cfd8dc")

	# Stone wall body
	for y in range(6, 14):
		for x in range(1, 15):
			var c = c_stone_m if (x + y) % 2 == 0 else c_stone_d
			img.set_pixel(ox + x, oy + y, c)

	# Crenellations on top
	for x in [2, 3, 6, 7, 10, 11, 13]:
		img.set_pixel(ox + x, oy + 4, c_stone_l)
		img.set_pixel(ox + x, oy + 5, c_stone_m)

	# Horizontal mortar joints
	for x in range(1, 15):
		img.set_pixel(ox + x, oy + 9, c_mortar)
		img.set_pixel(ox + x, oy + 12, c_mortar)

	# Iron reinforcement studs
	for x in [3, 7, 11]:
		img.set_pixel(ox + x, oy + 7, c_iron)
		img.set_pixel(ox + x, oy + 10, c_iron)

static func _draw_temporary_camp(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_log_l = Color("8d6e63")
	var c_log_d = Color("4e342e")
	var c_canopy = Color("d35400")
	var c_flag = Color("e74c3c")
	var c_fire = Color("f39c12")

	# Wooden palisade wall with sharpened stakes
	for x in range(2, 14):
		for y in range(9, 14):
			img.set_pixel(ox + x, oy + y, c_log_d if x % 2 == 0 else c_log_l)
		img.set_pixel(ox + x, oy + 8, c_log_l if x % 2 == 0 else c_log_d)

	# Central Watchtower
	for y in range(3, 9):
		for x in range(6, 10):
			img.set_pixel(ox + x, oy + y, c_log_d)

	# Tower canopy roof
	for x in range(5, 11):
		img.set_pixel(ox + x, oy + 3, c_canopy)
	for x in range(6, 10):
		img.set_pixel(ox + x, oy + 2, c_canopy)

	# Flag
	img.set_pixel(ox + 8, oy + 1, c_flag)
	img.set_pixel(ox + 9, oy + 1, c_flag)

	# Campfire
	img.set_pixel(ox + 12, oy + 12, c_fire)

static func _draw_harbor(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_wood_l = Color("a1887f")
	var c_wood_d = Color("5d4037")
	var c_roof = Color("e74c3c")
	var c_light = Color("f1c40f")
	var c_water_foam = Color("e0f7fa")
	var c_dock = Color("8d6e63")

	# Wooden pier walkway (T-shape dock)
	for y in range(6, 14):
		for x in range(7, 10):
			img.set_pixel(ox + x, oy + y, c_dock if (x + y) % 2 == 0 else c_wood_l)

	# Cross pier
	for x in range(3, 14):
		for y in range(11, 13):
			img.set_pixel(ox + x, oy + y, c_wood_d if x % 2 == 0 else c_dock)

	# Pier pilings in water with foam
	for x in [3, 7, 9, 13]:
		img.set_pixel(ox + x, oy + 13, c_wood_d)
		img.set_pixel(ox + x - 1, oy + 13, c_water_foam)
		img.set_pixel(ox + x + 1, oy + 13, c_water_foam)

	# Harbor lighthouse / watch station on pier head
	for y in range(2, 6):
		for x in range(7, 10):
			img.set_pixel(ox + x, oy + y, Color("ecf0f1"))
	# Lighthouse lantern
	img.set_pixel(ox + 8, oy + 3, c_light)
	img.set_pixel(ox + 7, oy + 3, c_light)
	# Lighthouse red conical roof
	for x in range(6, 11):
		img.set_pixel(ox + x, oy + 2, c_roof)
	for x in range(7, 10):
		img.set_pixel(ox + x, oy + 1, c_roof)
	img.set_pixel(ox + 8, oy + 0, c_roof)

static func _draw_niter(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_crystal_white = Color("ffffff")
	var c_crystal_pale = Color("eceff1")
	var c_crystal_grey = Color("b0bec5")
	var c_sulfur_amber = Color("ffb74d")
	var c_dirt_dark = Color("37474f")

	# Base earthen quarry pit / mineral mound
	for x in range(3, 13):
		for y in range(8, 14):
			img.set_pixel(ox + x, oy + y, c_dirt_dark)

	# Left Saltpeter Crystalline Spire
	img.set_pixel(ox + 4, oy + 7, c_crystal_white)
	img.set_pixel(ox + 5, oy + 6, c_crystal_white)
	img.set_pixel(ox + 5, oy + 7, c_crystal_pale)
	img.set_pixel(ox + 6, oy + 7, c_crystal_grey)
	img.set_pixel(ox + 4, oy + 8, c_crystal_pale)
	img.set_pixel(ox + 5, oy + 8, c_crystal_white)
	img.set_pixel(ox + 6, oy + 8, c_crystal_grey)

	# Main Central Niter Shard Cluster
	for y in range(4, 9):
		for x in range(7, 10):
			img.set_pixel(ox + x, oy + y, c_crystal_pale)
	img.set_pixel(ox + 8, oy + 3, c_crystal_white)
	img.set_pixel(ox + 8, oy + 4, c_crystal_white)
	img.set_pixel(ox + 7, oy + 5, c_crystal_white)
	img.set_pixel(ox + 9, oy + 6, c_crystal_grey)

	# Right Saltpeter Bed & Sulfur Powder Grains
	img.set_pixel(ox + 10, oy + 8, c_sulfur_amber)
	img.set_pixel(ox + 11, oy + 7, c_crystal_white)
	img.set_pixel(ox + 11, oy + 8, c_crystal_pale)
	img.set_pixel(ox + 12, oy + 9, c_sulfur_amber)

	# Fine crystalline glint sparks
	img.set_pixel(ox + 6, oy + 10, c_crystal_white)
	img.set_pixel(ox + 9, oy + 11, c_sulfur_amber)
	img.set_pixel(ox + 11, oy + 11, c_crystal_white)

static func _draw_border_wall_badge(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_stone_l = Color("90a4ae")
	var c_stone_m = Color("607d8b")
	var c_stone_d = Color("37474f")
	var c_border = Color("212121")
	var c_gold = Color("f39c12")

	# 6x6 stone wall badge at top-left
	for y in range(1, 7):
		for x in range(1, 7):
			img.set_pixel(ox + x, oy + y, c_stone_m if (x + y) % 2 == 0 else c_stone_d)

	# Crenellations on top (x=1, 3, 5)
	img.set_pixel(ox + 1, oy + 0, c_stone_l)
	img.set_pixel(ox + 3, oy + 0, c_stone_l)
	img.set_pixel(ox + 5, oy + 0, c_stone_l)

	# Dark outline border around badge
	for x in range(0, 7):
		img.set_pixel(ox + x, oy + 7, c_border)
	for y in range(0, 7):
		img.set_pixel(ox + 7, oy + y, c_border)

	# Tiny defensive crest dot in center
	img.set_pixel(ox + 3, oy + 3, c_gold)

static func _draw_district_valid(img: Image, slot: Vector2i) -> void:
	var ox = slot.x * CELL_SIZE
	var oy = slot.y * CELL_SIZE
	var c_cyan = Color("00e5ff")
	var c_glow = Color(0.0, 0.9, 1.0, 0.45)

	# Corner brackets
	for i in range(4):
		img.set_pixel(ox + i, oy + 0, c_cyan)
		img.set_pixel(ox + 0, oy + i, c_cyan)
		img.set_pixel(ox + 15 - i, oy + 0, c_cyan)
		img.set_pixel(ox + 15, oy + i, c_cyan)
		img.set_pixel(ox + i, oy + 15, c_cyan)
		img.set_pixel(ox + 0, oy + 15 - i, c_cyan)
		img.set_pixel(ox + 15 - i, oy + 15, c_cyan)
		img.set_pixel(ox + 15, oy + 15 - i, c_cyan)

	# Center diamond placement pip
	img.set_pixel(ox + 7, oy + 6, c_cyan)
	img.set_pixel(ox + 8, oy + 6, c_cyan)
	img.set_pixel(ox + 6, oy + 7, c_cyan)
	img.set_pixel(ox + 7, oy + 7, Color.WHITE)
	img.set_pixel(ox + 8, oy + 7, Color.WHITE)
	img.set_pixel(ox + 9, oy + 7, c_cyan)
	img.set_pixel(ox + 6, oy + 8, c_cyan)
	img.set_pixel(ox + 7, oy + 8, Color.WHITE)
	img.set_pixel(ox + 8, oy + 8, Color.WHITE)
	img.set_pixel(ox + 9, oy + 8, c_cyan)
	img.set_pixel(ox + 7, oy + 9, c_cyan)
	img.set_pixel(ox + 8, oy + 9, c_cyan)


