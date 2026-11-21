class_name GameState
extends RefCounted

## Pure simulation state store holding all entities, grid references, and factions

signal unit_spawned(unit: UnitInstance)
signal unit_removed(unit_id: int, faction_id: int, coords: Vector2i)
signal unit_moved(unit: UnitInstance, from_coords: Vector2i, to_coords: Vector2i)
signal unit_attacked(attacker: UnitInstance, defender: UnitInstance, combat_result: CombatEngine.CombatResult)
signal city_attacked(attacker: UnitInstance, city: CityData, combat_result: CombatEngine.CombatResult)
signal city_bombarded(city: CityData, target_unit: UnitInstance, damage: int)
signal city_founded(city: CityData)
signal city_captured(city: CityData, old_faction_id: int, new_faction_id: int)
signal city_razed(city: CityData, conqueror_faction_id: int)
signal city_borders_expanded(city: CityData, newly_claimed: Array[Vector2i])
signal unit_upgraded(unit: UnitInstance, old_data: UnitData, new_data: UnitData)
signal barbarian_camp_cleared(coords: Vector2i, conqueror_unit: UnitInstance)
signal fortification_bombarded(coords: Vector2i, target_unit: UnitInstance, damage: int)
signal fortification_razed(coords: Vector2i, conqueror_faction_id: int)
signal fog_of_war_updated()

class UnitInstance:
	var instance_id: int
	var data: UnitData
	var faction_id: int
	var grid_pos: Vector2i
	var current_health: int
	var remaining_mp: int
	var build_charges: int = 3
	var has_attacked: bool = false
	var is_fortified: bool = false
	var fortify_turns: int = 0
	var is_turn_skipped: bool = false
	var is_resting_heal: bool = false
	var is_embarked: bool = false
	var is_garrisoned: bool = false
	var is_automated: bool = false

	func _init(p_id: int, p_data: UnitData, p_faction: int, p_pos: Vector2i) -> void:
		instance_id = p_id
		data = p_data
		faction_id = p_faction
		grid_pos = p_pos
		current_health = p_data.max_health
		remaining_mp = p_data.max_movement_points
		if p_data.can_build_improvements:
			build_charges = 3
		elif p_data.can_build_military_structures or p_data.id == "military_engineer":
			build_charges = 2

	func reset_turn() -> void:
		remaining_mp = data.max_movement_points
		has_attacked = false
		is_turn_skipped = false
		if (is_fortified or is_resting_heal) and current_health < data.max_health:
			current_health = mini(data.max_health, current_health + 15)
		if current_health >= data.max_health:
			is_resting_heal = false

	func is_naval_unit() -> bool:
		if data == null:
			return false
		var u_class = data.get("unit_class")
		return data.get("is_naval") == true or u_class == GameEnums.UnitClass.NAVAL_MELEE or u_class == GameEnums.UnitClass.NAVAL_RANGED

	func is_ranged_unit() -> bool:
		if data == null:
			return false
		var u_class = data.get("unit_class")
		var r_str = data.get("ranged_strength")
		var rng = data.get("attack_range")
		return (u_class == GameEnums.UnitClass.RANGED or u_class == GameEnums.UnitClass.NAVAL_RANGED or (r_str != null and r_str > 0)) and (rng != null and rng >= 1)

var next_unit_id: int = 1
var next_city_id: int = 1

var grid_model: GridModel
var pathfinding: PathfindingSystem
var tech_manager: TechTreeManager
var diplomacy_manager: DiplomacyManager
var espionage_manager: EspionageManager

var units: Dictionary = {} # instance_id -> UnitInstance
var cities: Dictionary = {} # city_id -> CityData
var barbarian_camps: Array[Vector2i] = []
var barbarian_spawn_turn: int = 0
var faction_gold: Dictionary = {
	GameEnums.FactionId.SOLARIS_DOMINION: 50,
	GameEnums.FactionId.IRONFANG_EMPIRE: 50,
	GameEnums.FactionId.VERDANT_KINGDOM: 50,
	GameEnums.FactionId.OBSIDIAN_CONCLAVE: 50,
	GameEnums.FactionId.CELESTIAL_SHOGUNATE: 50,
	GameEnums.FactionId.FROSTVEIN_CLAN: 50,
	GameEnums.FactionId.GOLDEN_EMIRATE: 50,
	GameEnums.FactionId.BARBARIANS: 0
}
var factions: Array[int] = [
	GameEnums.FactionId.SOLARIS_DOMINION,
	GameEnums.FactionId.IRONFANG_EMPIRE,
	GameEnums.FactionId.VERDANT_KINGDOM,
	GameEnums.FactionId.OBSIDIAN_CONCLAVE,
	GameEnums.FactionId.CELESTIAL_SHOGUNATE,
	GameEnums.FactionId.FROSTVEIN_CLAN,
	GameEnums.FactionId.GOLDEN_EMIRATE,
	GameEnums.FactionId.BARBARIANS
]

var faction_names: Dictionary = {
	GameEnums.FactionId.SOLARIS_DOMINION: "Solaris Dominion",
	GameEnums.FactionId.IRONFANG_EMPIRE: "Ironfang Empire",
	GameEnums.FactionId.VERDANT_KINGDOM: "Verdant Kingdom",
	GameEnums.FactionId.OBSIDIAN_CONCLAVE: "Obsidian Conclave",
	GameEnums.FactionId.CELESTIAL_SHOGUNATE: "Celestial Shogunate",
	GameEnums.FactionId.FROSTVEIN_CLAN: "Frostvein Clan",
	GameEnums.FactionId.GOLDEN_EMIRATE: "Golden Emirate",
	GameEnums.FactionId.BARBARIANS: "Barbarian Raiders"
}

var faction_colors: Dictionary = {
	GameEnums.FactionId.SOLARIS_DOMINION: Color("3498db"), # Blue
	GameEnums.FactionId.IRONFANG_EMPIRE: Color("e74c3c"),  # Red
	GameEnums.FactionId.VERDANT_KINGDOM: Color("2ecc71"),  # Green
	GameEnums.FactionId.OBSIDIAN_CONCLAVE: Color("9b59b6"),# Purple
	GameEnums.FactionId.CELESTIAL_SHOGUNATE: Color("f1c40f"), # Amber / Gold
	GameEnums.FactionId.FROSTVEIN_CLAN: Color("1abc9c"),    # Teal / Cyan
	GameEnums.FactionId.GOLDEN_EMIRATE: Color("e67e22"),    # Orange
	GameEnums.FactionId.BARBARIANS: Color("78281f")         # Dark Crimson
}

func get_faction_name(f_id: int) -> String:
	return faction_names.get(f_id, "Faction %d" % f_id)

func get_faction_color(f_id: int) -> Color:
	return faction_colors.get(f_id, Color.WHITE)

func initialize(p_grid: GridModel) -> void:
	grid_model = p_grid
	pathfinding = PathfindingSystem.new(grid_model)
	var tech_mgr_script = preload("res://scripts/tech/TechTreeManager.gd")
	tech_manager = tech_mgr_script.new()
	diplomacy_manager = DiplomacyManager.new()
	diplomacy_manager.initialize(factions)
	espionage_manager = EspionageManager.new(self)
	for f in factions:
		if f != GameEnums.FactionId.BARBARIANS:
			tech_manager.initialize_faction(f)

func get_unit_at(coords: Vector2i) -> UnitInstance:
	for u in units.values():
		if u.grid_pos == coords:
			return u
	return null

func get_city_at(coords: Vector2i) -> CityData:
	for c in cities.values():
		if c.grid_pos == coords:
			return c
	return null

func get_garrison_unit(city: CityData) -> UnitInstance:
	if not city: return null
	if city.garrison_unit_id != -1 and units.has(city.garrison_unit_id):
		return units[city.garrison_unit_id]
	var u = get_unit_at(city.grid_pos)
	if u and u.faction_id == city.faction_id and not u.data.is_civilian():
		return u
	return null

func get_faction_units(faction_id: int) -> Array[UnitInstance]:
	var res: Array[UnitInstance] = []
	for u in units.values():
		if u.faction_id == faction_id:
			res.append(u)
	return res

func get_faction_cities(faction_id: int) -> Array[CityData]:
	var res: Array[CityData] = []
	for c in cities.values():
		if c.faction_id == faction_id:
			res.append(c)
	return res

func spawn_unit(data: UnitData, faction_id: int, coords: Vector2i) -> UnitInstance:
	var is_naval = false
	if data != null:
		var u_class = data.get("unit_class")
		if data.get("is_naval") == true or u_class == GameEnums.UnitClass.NAVAL_MELEE or u_class == GameEnums.UnitClass.NAVAL_RANGED:
			is_naval = true
	if is_naval:
		# If spawning at city, prefer the city's harbor tile
		var city = get_city_at(coords)
		if city and city.has_harbor and city.harbor_pos != Vector2i(-1, -1):
			coords = city.harbor_pos
		elif city:
			# Find closest water tile in territory
			for t in city.territory_tiles:
				var tile = grid_model.get_tile(t)
				if tile and tile.biome_data.biome_type == GameEnums.BiomeType.OCEAN:
					coords = t
					break

		# If target tile occupied or not water, find adjacent free ocean tile
		var dest_tile = grid_model.get_tile(coords)
		if get_unit_at(coords) != null or (dest_tile and dest_tile.biome_data.biome_type != GameEnums.BiomeType.OCEAN):
			var placed = false
			for n in grid_model.get_neighbors(coords, true):
				var n_tile = grid_model.get_tile(n)
				if n_tile and n_tile.biome_data.biome_type == GameEnums.BiomeType.OCEAN and get_unit_at(n) == null:
					coords = n
					placed = true
					break
			if not placed:
				return null
	else:
		if get_unit_at(coords) != null:
			# Search adjacent free tile
			var placed = false
			for n in grid_model.get_neighbors(coords, true):
				if grid_model.is_passable(n) and get_unit_at(n) == null:
					coords = n
					placed = true
					break
			if not placed:
				return null

	var uid = next_unit_id
	next_unit_id += 1
	var unit = UnitInstance.new(uid, data, faction_id, coords)
	var spawn_tile = grid_model.get_tile(coords)
	if spawn_tile and spawn_tile.biome_data.biome_type == GameEnums.BiomeType.OCEAN and not is_naval:
		unit.is_embarked = true
	units[uid] = unit

	if spawn_tile:
		spawn_tile.unit_id = uid

	unit_spawned.emit(unit)
	update_fog_of_war(faction_id)
	return unit

const UNIT_PRODUCTION_COSTS: Dictionary = {
	"scout": 25,
	"builder": 30,
	"settler": 50,
	"slinger": 30,
	"archer": 50,
	"spearman": 45,
	"swordsman": 65,
	"horseman": 55,
	"catapult": 65,
	"crossbowman": 75,
	"knight": 85,
	"barbarian_raider": 35,
	"barbarian_horseman": 45,
	"military_engineer": 45,
	"galley": 40,
	"quadrireme": 50,
	"galleass": 70,
	"musketman": 100,
	"bombard": 110,
	"cuirassier": 120,
	"frigate": 115,
	"spy": 75
}

const UNIT_POPULATION_COSTS: Dictionary = {
	"scout": 0,
	"builder": 1,
	"settler": 2,
	"slinger": 0,
	"barbarian_raider": 0,
	"archer": 1,
	"spearman": 1,
	"swordsman": 1,
	"horseman": 1,
	"catapult": 2,
	"crossbowman": 2,
	"knight": 2,
	"barbarian_horseman": 1,
	"military_engineer": 1,
	"galley": 1,
	"quadrireme": 1,
	"galleass": 1,
	"musketman": 1,
	"bombard": 2,
	"cuirassier": 2,
	"frigate": 2,
	"spy": 0
}

const UNIT_MAINTENANCE_COSTS: Dictionary = {
	"scout": 0,
	"builder": 0,
	"settler": 0,
	"slinger": 0,
	"barbarian_raider": 1,
	"archer": 1,
	"spearman": 1,
	"swordsman": 2,
	"horseman": 2,
	"catapult": 2,
	"crossbowman": 2,
	"barbarian_horseman": 2,
	"knight": 3,
	"military_engineer": 1,
	"galley": 1,
	"quadrireme": 1,
	"galleass": 2,
	"musketman": 2,
	"bombard": 3,
	"cuirassier": 3,
	"frigate": 3
}

func city_has_military_encampment(city: CityData) -> bool:
	if not city:
		return false
	if city.has_military_encampment or city.has_encampment:
		return true
	for coord in city.territory_tiles:
		var tile = grid_model.get_tile(coord)
		if tile and tile.improvement_data and tile.improvement_data.improvement_type == GameEnums.ImprovementType.MILITARY_ENCAMPMENT:
			return true
	return false

func get_required_resource_amount_for_city(city: CityData) -> int:
	return 1 if city_has_military_encampment(city) else 2

func purchase_unit(city_id: int, unit_id: String) -> UnitInstance:
	var city = cities.get(city_id, null)
	if not city:
		return null

	if unit_id == "military_engineer" and not city_has_military_encampment(city):
		return null

	# Naval units require Harbor
	if unit_id in ["galley", "quadrireme", "galleass"] and not city.has_harbor:
		return null

	var cost = UNIT_PRODUCTION_COSTS.get(unit_id, 30) * 2
	var current_gold = faction_gold.get(city.faction_id, 0)
	if current_gold < cost:
		return null

	# Check population requirement: city must remain at least pop 1
	var pop_cost = UNIT_POPULATION_COSTS.get(unit_id, 0)
	if pop_cost > 0 and city.population <= pop_cost:
		return null

	# Check strategic resource requirements with encampment discount (1 with encampment, 2 without)
	var req_amount = get_required_resource_amount_for_city(city)
	var strat_res = get_available_strategic_resources(city.faction_id)
	if unit_id in ["swordsman", "catapult", "crossbowman"]:
		if strat_res.get("iron", 0) < req_amount:
			return null
	if unit_id in ["horseman", "knight", "barbarian_horseman"]:
		if strat_res.get("horses", 0) < req_amount:
			return null
	if unit_id in ["musketman", "bombard", "cuirassier", "frigate"]:
		if strat_res.get("niter", 0) < req_amount:
			return null

	var res_path = "res://resources/units/%s.tres" % unit_id
	if not ResourceLoader.exists(res_path):
		return null
	var unit_data = load(res_path) as UnitData
	if not unit_data:
		return null

	# Spawn unit at city position (or adjacent free tile)
	var unit = spawn_unit(unit_data, city.faction_id, city.grid_pos)
	if not unit:
		return null

	# Deduct gold and exhaust movement for the muster turn
	faction_gold[city.faction_id] = current_gold - cost
	unit.remaining_mp = 0

	# Deduct population and recalculate city food threshold
	if pop_cost > 0:
		city.population -= pop_cost
		city.food_needed = city.calculate_food_needed(city.population)
		calculate_city_yields(city)

	return unit

func remove_unit(unit_id: int) -> void:
	if units.has(unit_id):
		var u: UnitInstance = units[unit_id]
		var tile = grid_model.get_tile(u.grid_pos)
		if tile and tile.unit_id == unit_id:
			tile.unit_id = -1
		for city in cities.values():
			if city.garrison_unit_id == unit_id:
				city.garrison_unit_id = -1
		units.erase(unit_id)
		unit_removed.emit(unit_id, u.faction_id, u.grid_pos)

func found_city(faction_id: int, coords: Vector2i, city_name: String) -> CityData:
	var cid = next_city_id
	next_city_id += 1
	var city = CityData.new()
	city.initialize(cid, city_name, faction_id, coords)
	cities[cid] = city

	var tile = grid_model.get_tile(coords)
	if tile:
		tile.city_id = cid
		tile.owner_faction_id = faction_id
		tile.is_city = true

	for t in city.territory_tiles:
		if grid_model.is_valid_coord(t):
			var terr_tile = grid_model.get_tile(t)
			if terr_tile and terr_tile.owner_faction_id == -1:
				terr_tile.owner_faction_id = faction_id
				terr_tile.city_id = cid

	city_founded.emit(city)
	update_fog_of_war(faction_id)
	return city

func raze_city(city_id: int, conqueror_faction_id: int) -> void:
	if not cities.has(city_id):
		return
	var city: CityData = cities[city_id]

	# Release all territory tiles back to neutral unclaimed
	for t in city.territory_tiles:
		var tile = grid_model.get_tile(t)
		if tile and tile.city_id == city_id:
			tile.owner_faction_id = -1
			tile.city_id = -1

	var center_tile = grid_model.get_tile(city.grid_pos)
	if center_tile:
		center_tile.city_id = -1
		center_tile.owner_faction_id = -1
		center_tile.is_city = false

	cities.erase(city_id)
	city_razed.emit(city, conqueror_faction_id)
	update_fog_of_war(conqueror_faction_id)
	update_fog_of_war(city.faction_id)

## Expands the city's territory by claiming unclaimed adjacent candidate tiles
func expand_city_borders(city: CityData, tiles_to_claim: int = 3) -> Array[Vector2i]:
	var newly_claimed: Array[Vector2i] = []
	var candidates: Array[Vector2i] = []

	# Scan for adjacent unclaimed tiles up to radius 3
	var max_radius = 3
	for t in city.territory_tiles:
		for n in grid_model.get_neighbors(t, false):
			if grid_model.is_valid_coord(n) and not city.territory_tiles.has(n) and not candidates.has(n):
				var tile_state = grid_model.get_tile(n)
				if tile_state and tile_state.owner_faction_id == -1:
					var dist = maxi(absi(n.x - city.grid_pos.x), absi(n.y - city.grid_pos.y))
					if dist <= max_radius:
						candidates.append(n)

	# If no candidates within radius 3, search outer ring (radius 4)
	if candidates.is_empty():
		for t in city.territory_tiles:
			for n in grid_model.get_neighbors(t, true):
				if grid_model.is_valid_coord(n) and not city.territory_tiles.has(n) and not candidates.has(n):
					var tile_state = grid_model.get_tile(n)
					if tile_state and tile_state.owner_faction_id == -1:
						candidates.append(n)

	if candidates.is_empty():
		return newly_claimed

	# Sort candidates by strategic and economic value
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var tile_a = grid_model.get_tile(a)
		var tile_b = grid_model.get_tile(b)
		var score_a = 0
		var score_b = 0
		if tile_a:
			score_a += tile_a.biome_data.yield_food * 2 + tile_a.biome_data.yield_production * 3
			if tile_a.resource_data:
				score_a += 15
			if tile_a.biome_data.is_passable:
				score_a += 5
			score_a -= (absi(a.x - city.grid_pos.x) + absi(a.y - city.grid_pos.y))
		if tile_b:
			score_b += tile_b.biome_data.yield_food * 2 + tile_b.biome_data.yield_production * 3
			if tile_b.resource_data:
				score_b += 15
			if tile_b.biome_data.is_passable:
				score_b += 5
			score_b -= (absi(b.x - city.grid_pos.x) + absi(b.y - city.grid_pos.y))
		return score_a > score_b
	)

	var count = mini(tiles_to_claim, candidates.size())
	for i in range(count):
		var c_tile = candidates[i]
		city.territory_tiles.append(c_tile)
		var tile_state = grid_model.get_tile(c_tile)
		if tile_state:
			tile_state.owner_faction_id = city.faction_id
			tile_state.city_id = city.city_id
		newly_claimed.append(c_tile)

	city_borders_expanded.emit(city, newly_claimed)
	update_fog_of_war(city.faction_id)
	return newly_claimed

func update_fog_of_war(faction_id: int) -> void:
	grid_model.clear_visibility(faction_id)
	# Reveal around cities
	for c in get_faction_cities(faction_id):
		for t in grid_model.get_all_tiles_in_radius(c.grid_pos, 2):
			grid_model.reveal_tile(t, faction_id)
	# Reveal around friendly temporary military camps (outposts)
	for y in range(grid_model.height):
		for x in range(grid_model.width):
			var c_pos = Vector2i(x, y)
			var c_tile = grid_model.get_tile(c_pos)
			if c_tile and c_tile.improvement_data != null and c_tile.improvement_data.improvement_type == GameEnums.ImprovementType.TEMPORARY_CAMP and c_tile.owner_faction_id == faction_id:
				for t in grid_model.get_all_tiles_in_radius(c_pos, 2):
					grid_model.reveal_tile(t, faction_id)
	# Reveal around units
	for u in get_faction_units(faction_id):
		for t in grid_model.get_all_tiles_in_radius(u.grid_pos, u.data.sight_range):
			grid_model.reveal_tile(t, faction_id)

	# Update city discovery state for this faction and trigger diplomacy meetings
	for other_city in cities.values():
		if other_city.faction_id == faction_id:
			other_city.discovered_by_faction[faction_id] = true
		else:
			var c_tile = grid_model.get_tile(other_city.grid_pos)
			if c_tile and (c_tile.visible_by_faction.get(faction_id, false) or c_tile.revealed_by_faction.get(faction_id, false)):
				other_city.discovered_by_faction[faction_id] = true
				if diplomacy_manager and other_city.faction_id != GameEnums.FactionId.BARBARIANS:
					diplomacy_manager.meet_factions(faction_id, other_city.faction_id)

	# Check visible foreign units to trigger diplomacy meetings
	if diplomacy_manager:
		for other_unit in units.values():
			if other_unit.faction_id != faction_id and other_unit.faction_id != GameEnums.FactionId.BARBARIANS:
				var u_tile = grid_model.get_tile(other_unit.grid_pos)
				if u_tile and u_tile.visible_by_faction.get(faction_id, false):
					diplomacy_manager.meet_factions(faction_id, other_unit.faction_id)

	# Active surveillance: if espionage has surveillance active on foreign empire, reveal its units
	if espionage_manager:
		for foreign_fac in factions:
			if foreign_fac != faction_id and foreign_fac != GameEnums.FactionId.BARBARIANS:
				if espionage_manager.has_active_surveillance(faction_id, foreign_fac):
					for f_u in get_faction_units(foreign_fac):
						grid_model.reveal_tile(f_u.grid_pos, faction_id)

	fog_of_war_updated.emit()

func calculate_city_yields(city: CityData) -> Dictionary:
	# Base city center yield
	var base_food: int = 2
	var base_prod: int = 2
	var base_sci: int = 1
	var base_gold: int = 2

	# Population works territory tiles up to city.population (best tiles first)
	var tile_evaluations: Array = []
	for coord in city.territory_tiles:
		if coord == city.grid_pos:
			continue # City center tile provides the base yield
		var tile = grid_model.get_tile(coord)
		if tile:
			var f = tile.biome_data.yield_food
			var p = tile.biome_data.yield_production
			var s = tile.biome_data.yield_science + tile.natural_science
			var g = 0
			if tile.resource_data:
				# Resources only provide bonus if player has required tech (e.g. Rice -> Agriculture)
				var req_tech = tile.resource_data.required_tech
				if req_tech == "" or tech_manager.is_tech_researched(city.faction_id, req_tech):
					f += tile.resource_data.food_bonus
					p += tile.resource_data.production_bonus
					s += tile.resource_data.science_bonus
					if "gold_bonus" in tile.resource_data:
						g += tile.resource_data.gold_bonus
			if tile.improvement_data:
				var imp_f = tile.improvement_data.food_bonus
				if tile.improvement_data.improvement_type == GameEnums.ImprovementType.FARM:
					# Farm on bare grass/plains gives +1 food (weaker than on rice)
					if tile.resource_data == null or tile.resource_data.id != "rice":
						imp_f = 1
					else:
						imp_f = 3
				f += imp_f
				p += tile.improvement_data.production_bonus
				s += tile.improvement_data.science_bonus
				if "gold_bonus" in tile.improvement_data:
					g += tile.improvement_data.gold_bonus

				# Base improved tile produces +1 Gold
				var imp_g = 1

				# Improved tiles with tech-unlocked resources produce bonus commercial revenue
				if tile.resource_data != null:
					var r_tech = tile.resource_data.required_tech
					if r_tech == "" or tech_manager.is_tech_researched(city.faction_id, r_tech):
						match tile.resource_data.id:
							"rice": imp_g += 2       # Total +3 Gold
							"horses": imp_g += 2     # Total +3 Gold
							"iron": imp_g += 3       # Total +4 Gold
							"gold_ore": imp_g += 4   # Total +5 Gold
							"gems": imp_g += 5       # Total +6 Gold
				g += imp_g

				# Feudalism perk: +1 food to all farms!
				if tile.improvement_data.improvement_type == GameEnums.ImprovementType.FARM and tech_manager.is_tech_researched(city.faction_id, "feudalism"):
					f += 1
			tile_evaluations.append({
				"food": f,
				"prod": p,
				"sci": s,
				"gold": g,
				"score": f * 2 + p * 3 + s * 3 + g * 3
			})

	tile_evaluations.sort_custom(func(a, b): return a["score"] > b["score"])

	var worked_food: int = 0
	var worked_prod: int = 0
	var worked_sci: int = 0
	var worked_gold: int = 0
	var max_worked = mini(maxi(1, city.population), tile_evaluations.size())
	for i in range(max_worked):
		worked_food += tile_evaluations[i]["food"]
		worked_prod += tile_evaluations[i]["prod"]
		worked_sci += tile_evaluations[i]["sci"]
		worked_gold += tile_evaluations[i]["gold"]

	calculate_city_housing(city)

	# Infrastructure yields
	var infra_food = 3 if city.has_aqueduct else 0
	var infra_prod = 2 if city.has_castle else 0
	if city.has_military_encampment:
		infra_prod += 2
		# Highland bonus (+3 ⚙ Production if constructed on Highlands / Hills)
		var enc_pos = city.encampment_pos
		if enc_pos == Vector2i(-1, -1):
			for c in city.territory_tiles:
				var t = grid_model.get_tile(c)
				if t and t.improvement_data and t.improvement_data.improvement_type == GameEnums.ImprovementType.MILITARY_ENCAMPMENT:
					enc_pos = c
					city.encampment_pos = c
					break
		if enc_pos != Vector2i(-1, -1) and is_highland_tile(enc_pos):
			infra_prod += 3

	var infra_gold = 4 if city.has_market else 0
	var infra_sci = 3 if city.has_science_camp else 0
	if city.has_science_camp:
		# Science tile bonus (+3 🔬 Science if constructed on or adjacent to natural science / mountain / anomaly)
		var sci_pos = city.science_camp_pos
		if sci_pos == Vector2i(-1, -1):
			for c in city.territory_tiles:
				var t = grid_model.get_tile(c)
				if t and t.improvement_data and t.improvement_data.improvement_type == GameEnums.ImprovementType.SCIENCE_CAMP:
					sci_pos = c
					city.science_camp_pos = c
					break
		if sci_pos != Vector2i(-1, -1) and is_science_adjacent_tile(sci_pos):
			infra_sci += 3

	return {
		"food": base_food + worked_food + infra_food,
		"production": base_prod + worked_prod + infra_prod,
		"science": base_sci + worked_sci + infra_sci,
		"gold": base_gold + int(city.population / 2) + worked_gold + infra_gold,
		"housing": city.housing,
		"base_production": base_prod + infra_prod,
		"worked_production": worked_prod,
		"worked_count": max_worked
	}

func is_highland_tile(coords: Vector2i) -> bool:
	var t = grid_model.get_tile(coords)
	if not t: return false
	if t.biome_data.biome_type == GameEnums.BiomeType.HILLS or t.biome_data.biome_type == GameEnums.BiomeType.MOUNTAINS:
		return true
	for n in grid_model.get_neighbors(coords, false):
		var nt = grid_model.get_tile(n)
		if nt and nt.biome_data.biome_type == GameEnums.BiomeType.MOUNTAINS:
			return true
	return false

func is_science_adjacent_tile(coords: Vector2i) -> bool:
	var t = grid_model.get_tile(coords)
	if not t: return false
	if t.natural_science > 0 or t.biome_data.biome_type == GameEnums.BiomeType.MOUNTAINS:
		return true
	for n in grid_model.get_neighbors(coords, false):
		var nt = grid_model.get_tile(n)
		if nt and (nt.natural_science > 0 or nt.biome_data.biome_type == GameEnums.BiomeType.MOUNTAINS):
			return true
	return false

func is_food_district_adjacent_tile(coords: Vector2i) -> bool:
	for n in grid_model.get_neighbors(coords, false):
		var nt = grid_model.get_tile(n)
		if not nt: continue
		if nt.improvement_data:
			var imp_t = nt.improvement_data.improvement_type
			if imp_t == GameEnums.ImprovementType.AQUEDUCT or imp_t == GameEnums.ImprovementType.FARM or imp_t == GameEnums.ImprovementType.PASTURE:
				return true
		if nt.resource_data and nt.resource_data.id == "rice":
			return true
		if nt.biome_data and nt.biome_data.yield_food >= 2:
			return true
	return false

func calculate_city_housing(city: CityData) -> int:
	if not city:
		return 4
	var total_housing: float = 4.0 # Base housing
	var farm_pasture_count: int = 0
	var neighborhood_bonus: float = 0.0

	for coord in city.territory_tiles:
		var tile = grid_model.get_tile(coord)
		if tile and tile.improvement_data:
			match tile.improvement_data.improvement_type:
				GameEnums.ImprovementType.FARM, GameEnums.ImprovementType.PASTURE:
					farm_pasture_count += 1
				GameEnums.ImprovementType.NEIGHBORHOOD:
					total_housing += 4.0
					if is_food_district_adjacent_tile(coord):
						neighborhood_bonus += 2.0
				GameEnums.ImprovementType.AQUEDUCT:
					total_housing += 3.0
				GameEnums.ImprovementType.MARKET, GameEnums.ImprovementType.CASTLE:
					total_housing += 1.0

	# Farms & Pastures give +0.5 housing each (every 2 give +1 Housing)
	total_housing += float(farm_pasture_count) * 0.5 + neighborhood_bonus

	if city.has_aqueduct and total_housing < 7.0:
		total_housing = maxf(total_housing, 7.0)

	city.housing = int(total_housing)
	return city.housing


func get_unmoved_units(faction_id: int) -> Array[UnitInstance]:
	var unmoved: Array[UnitInstance] = []
	for u in get_faction_units(faction_id):
		if u.remaining_mp > 0 and not u.is_turn_skipped and not u.is_fortified and not u.is_resting_heal and not u.is_automated:
			unmoved.append(u)
	return unmoved

func get_faction_strategic_resources(faction_id: int) -> Dictionary:
	var res_counts: Dictionary = {
		"horses": 0,
		"iron": 0,
		"gold_ore": 0,
		"gems": 0,
		"rice": 0,
		"niter": 0
	}
	for city in get_faction_cities(faction_id):
		for coord in city.territory_tiles:
			var tile = grid_model.get_tile(coord)
			if tile and tile.resource_data and tile.resource_data.is_strategic:
				# Strategic resource is only harnessed if faction has the required tech AND improved tile!
				var req_tech = tile.resource_data.required_tech
				if req_tech == "" or tech_manager.is_tech_researched(faction_id, req_tech):
					if tile.improvement_data != null:
						var res_id = tile.resource_data.id
						res_counts[res_id] = res_counts.get(res_id, 0) + 1
	return res_counts

func get_available_strategic_resources(faction_id: int) -> Dictionary:
	var total = get_faction_strategic_resources(faction_id)
	if diplomacy_manager:
		for res_id in total.keys():
			var locked = diplomacy_manager.get_locked_resource_count(faction_id, res_id)
			total[res_id] = maxi(0, total[res_id] - locked)
	return total

func upgrade_unit(unit_id: int, new_data: UnitData) -> bool:
	if not units.has(unit_id):
		return false
	var u: UnitInstance = units[unit_id]
	var old_data = u.data
	var hp_ratio = float(u.current_health) / float(maxi(1, old_data.max_health))
	u.data = new_data
	u.current_health = clampi(int(hp_ratio * new_data.max_health), 1, new_data.max_health)
	u.remaining_mp = 0
	unit_upgraded.emit(u, old_data, new_data)
	return true
