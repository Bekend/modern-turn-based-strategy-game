class_name MapGenerator
extends RefCounted

## Procedural Map Generator utilizing FastNoiseLite for seeded biome elevation,
## strategic resource clustering, and fair faction start positions.

signal generation_completed(grid_model: GridModel, start_positions: Array[Vector2i], barbarian_camps: Array[Vector2i])

# Cached biome definitions
var biome_ocean: BiomeData
var biome_plains: BiomeData
var biome_hills: BiomeData
var biome_mountains: BiomeData
var biome_tundra: BiomeData

# Cached resource definitions
var res_rice: ResourceData
var res_iron: ResourceData
var res_horses: ResourceData
var res_gold_ore: ResourceData
var res_gems: ResourceData
var res_niter: ResourceData

var width: int = 36
var height: int = 24
var map_seed: int = 1337
var faction_count: int = 3

func _init(p_width: int = 36, p_height: int = 24, p_seed: int = 1337, p_faction_count: int = 3) -> void:
	width = p_width
	height = p_height
	map_seed = p_seed
	faction_count = maxi(2, p_faction_count)
	_load_resources()

func _load_resources() -> void:
	biome_ocean = load("res://resources/biomes/ocean.tres")
	biome_plains = load("res://resources/biomes/plains.tres")
	biome_hills = load("res://resources/biomes/hills.tres")
	biome_mountains = load("res://resources/biomes/mountains.tres")
	biome_tundra = load("res://resources/biomes/tundra.tres")

	res_rice = load("res://resources/strategic_resources/rice.tres")
	res_iron = load("res://resources/strategic_resources/iron.tres")
	res_horses = load("res://resources/strategic_resources/horses.tres")
	res_gold_ore = load("res://resources/strategic_resources/gold_ore.tres")
	res_gems = load("res://resources/strategic_resources/gems.tres")
	res_niter = load("res://resources/strategic_resources/niter.tres")

## Generates a complete GridModel with seeded biomes and placed resources
func generate_map() -> Dictionary:
	var grid = GridModel.new()
	grid.initialize(width, height)

	var elevation_noise = FastNoiseLite.new()
	elevation_noise.seed = map_seed
	elevation_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	elevation_noise.frequency = 0.055
	elevation_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	elevation_noise.fractal_octaves = 4

	var moisture_noise = FastNoiseLite.new()
	moisture_noise.seed = map_seed + 101
	moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	moisture_noise.frequency = 0.075

	var rng = RandomNumberGenerator.new()
	rng.seed = map_seed

	# 1. Biome Assignment Phase
	for y in range(height):
		# Polar tundra gradient (poles at top and bottom 15% of map)
		var lat_factor = absf(float(y) - float(height) * 0.5) / (float(height) * 0.5)
		for x in range(width):
			var coords = Vector2i(x, y)
			var elev = elevation_noise.get_noise_2d(float(x), float(y))
			var moist = moisture_noise.get_noise_2d(float(x), float(y))

			var assigned_biome: BiomeData
			if elev < -0.15:
				assigned_biome = biome_ocean
			elif elev >= 0.52:
				assigned_biome = biome_mountains
			elif lat_factor > 0.72 and elev > -0.05:
				assigned_biome = biome_tundra
			elif elev >= 0.22:
				assigned_biome = biome_hills
			else:
				assigned_biome = biome_plains

			var t_state = grid.set_tile(coords, assigned_biome)
			t_state.elevation = elev

	# 2. Resource Placement Phase
	for y in range(height):
		for x in range(width):
			var coords = Vector2i(x, y)
			var tile = grid.get_tile(coords)

			if not tile or not tile.biome_data.is_passable:
				continue

			var roll = rng.randf()

			# Rice: Spawns on Plains, higher likelihood near water
			if tile.biome_data.biome_type == GameEnums.BiomeType.PLAINS:
				var has_adjacent_water = _has_adjacent_biome(grid, coords, GameEnums.BiomeType.OCEAN)
				var rice_threshold = 0.16 if has_adjacent_water else 0.07
				if roll < rice_threshold:
					tile.resource_data = res_rice
					continue

			# Iron: Spawns on Hills or near Mountains
			if tile.biome_data.biome_type == GameEnums.BiomeType.HILLS:
				if roll < 0.14:
					tile.resource_data = res_iron
					continue
			elif tile.biome_data.biome_type == GameEnums.BiomeType.PLAINS:
				if _has_adjacent_biome(grid, coords, GameEnums.BiomeType.MOUNTAINS) and roll < 0.10:
					tile.resource_data = res_iron
					continue

			# Horses: Open grasslands away from dense mountains
			if tile.biome_data.biome_type == GameEnums.BiomeType.PLAINS:
				if roll > 0.88 and roll < 0.96:
					tile.resource_data = res_horses
					continue

			# Gold Ore: Mineral wealth in hills and highland peaks
			if tile.biome_data.biome_type == GameEnums.BiomeType.HILLS:
				if roll >= 0.14 and roll < 0.22:
					tile.resource_data = res_gold_ore
					continue

			# Gems: Precious luxury crystals in tundra or hills
			if tile.biome_data.biome_type in [GameEnums.BiomeType.TUNDRA, GameEnums.BiomeType.HILLS]:
				if roll >= 0.78 and roll < 0.84:
					tile.resource_data = res_gems
					continue

			# Niter (Saltpeter): Natural explosive mineral deposits in plains, hills, and cold tundra
			if tile.biome_data.biome_type == GameEnums.BiomeType.PLAINS:
				if roll >= 0.94 and roll < 0.995:
					tile.resource_data = res_niter
					continue
			elif tile.biome_data.biome_type == GameEnums.BiomeType.TUNDRA:
				if roll < 0.16:
					tile.resource_data = res_niter
					continue
			elif tile.biome_data.biome_type == GameEnums.BiomeType.HILLS:
				if roll >= 0.84 and roll < 0.89:
					tile.resource_data = res_niter
					continue

	# 2.5. Natural Tile Science Distribution Phase
	for y in range(height):
		for x in range(width):
			var coords = Vector2i(x, y)
			var tile = grid.get_tile(coords)
			if not tile or not tile.biome_data.is_passable:
				continue

			var near_mountains = _has_adjacent_biome(grid, coords, GameEnums.BiomeType.MOUNTAINS)
			var near_water = _has_adjacent_biome(grid, coords, GameEnums.BiomeType.OCEAN)

			if near_mountains and near_water:
				tile.natural_science += 2
				tile.science_tag = "Alpine-Coastal Research Site"
			elif near_mountains:
				tile.natural_science += 1
				tile.science_tag = "Mountain Observatory Site"
			elif near_water:
				tile.natural_science += 1
				tile.science_tag = "Marine Research Site"

			# Rare Natural Wonders / Science Anomalies (~5.5% chance)
			var anomaly_roll = rng.randf()
			if anomaly_roll < 0.055:
				var anomaly_bonus = rng.randi_range(2, 3)
				tile.natural_science += anomaly_bonus
				var anomalies = [
					"Geothermal Vents",
					"Ancient Astronomical Ruins",
					"Glowing Crystal Fissure",
					"Meteorite Impact Crater"
				]
				tile.science_tag = anomalies[rng.randi() % anomalies.size()]

	# 3. Faction Starting Locations Selection
	var start_positions = _find_balanced_start_positions(grid, faction_count, rng)
	var num_camps = maxi(2, int(faction_count * 0.75) + 1)
	var barbarian_camps = _find_barbarian_camps(grid, start_positions, num_camps, rng)

	# Guarantee starter resources near spawn points
	for pos in start_positions:
		_guarantee_starter_tile_resources(grid, pos)

	generation_completed.emit(grid, start_positions, barbarian_camps)
	return {
		"grid": grid,
		"start_positions": start_positions,
		"barbarian_camps": barbarian_camps
	}

func _has_adjacent_biome(grid: GridModel, coords: Vector2i, target_type: GameEnums.BiomeType) -> bool:
	for neighbor in grid.get_neighbors(coords, true):
		var n_tile = grid.get_tile(neighbor)
		if n_tile and n_tile.biome_data.biome_type == target_type:
			return true
	return false

func _find_balanced_start_positions(grid: GridModel, faction_count: int, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	# Gather all candidate plains with surrounding fertile tiles
	for y in range(3, height - 3):
		for x in range(3, width - 3):
			var coords = Vector2i(x, y)
			var tile = grid.get_tile(coords)
			if tile and tile.biome_data.biome_type == GameEnums.BiomeType.PLAINS:
				# Check neighborhood passability
				var passable_count = 0
				for n in grid.get_neighbors(coords, true):
					var nt = grid.get_tile(n)
					if nt and nt.biome_data.is_passable:
						passable_count += 1
				if passable_count >= 6:
					candidates.append(coords)

	var selected: Array[Vector2i] = []
	var min_distance = int(float(width) / float(maxi(1, faction_count))) + 2

	# Shuffle candidates
	for i in range(candidates.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var tmp = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	for candidate in candidates:
		var too_close = false
		for chosen in selected:
			var dist = absi(candidate.x - chosen.x) + absi(candidate.y - chosen.y)
			if dist < min_distance:
				too_close = true
				break
		if not too_close:
			selected.append(candidate)
			if selected.size() >= faction_count:
				break

	# Fallback if too strict
	while selected.size() < faction_count:
		var fallback_pos = Vector2i(rng.randi_range(3, width - 4), rng.randi_range(3, height - 4))
		var fb_tile = grid.get_tile(fallback_pos)
		if fb_tile and fb_tile.biome_data.is_passable and not selected.has(fallback_pos):
			selected.append(fallback_pos)

	return selected

func _find_barbarian_camps(grid: GridModel, start_positions: Array[Vector2i], camp_count: int, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var camps: Array[Vector2i] = []
	var attempts = 0
	while camps.size() < camp_count and attempts < 200:
		attempts += 1
		var pos = Vector2i(rng.randi_range(2, width - 3), rng.randi_range(2, height - 3))
		var tile = grid.get_tile(pos)
		if not tile or not tile.biome_data.is_passable:
			continue

		var far_enough = true
		for sp in start_positions:
			var dist = absi(pos.x - sp.x) + absi(pos.y - sp.y)
			if dist < 6:
				far_enough = false
				break
		for cp in camps:
			var dist = absi(pos.x - cp.x) + absi(pos.y - cp.y)
			if dist < 8:
				far_enough = false
				break

		if far_enough:
			camps.append(pos)

	return camps

func _guarantee_starter_tile_resources(grid: GridModel, center: Vector2i) -> void:
	var neighbors = grid.get_neighbors(center, false)
	var has_food = false
	var has_prod = false

	for n in neighbors:
		var tile = grid.get_tile(n)
		if tile:
			if tile.resource_data != null:
				if tile.resource_data.food_bonus > 0:
					has_food = true
				if tile.resource_data.production_bonus > 0:
					has_prod = true

	# Ensure at least 1 Rice and 1 nearby production (Iron or Hill)
	for n in neighbors:
		var tile = grid.get_tile(n)
		if tile and tile.biome_data.is_passable and tile.resource_data == null:
			if not has_food:
				tile.resource_data = res_rice
				has_food = true
			elif not has_prod:
				tile.resource_data = res_iron
				has_prod = true

	# Place 1 Horses resource within 2-tile radius on an open plains tile
	var ring2 = grid.get_all_tiles_in_radius(center, 2)
	var has_horses = false
	for t in ring2:
		var tile = grid.get_tile(t)
		if tile and tile.resource_data == res_horses:
			has_horses = true
			break
	if not has_horses:
		for t in ring2:
			var tile = grid.get_tile(t)
			if tile and tile.biome_data.biome_type == GameEnums.BiomeType.PLAINS and tile.resource_data == null:
				tile.resource_data = res_horses
				break
