@tool
class_name CityData
extends Resource

## Data class representing a City entity, its fortifications, production, and territory

@export var city_id: int = 0
@export var city_name: String = "City"
@export var faction_id: int = 0
@export var grid_pos: Vector2i = Vector2i.ZERO

@export_group("Defenses")
@export var health: int = 100
@export var max_health: int = 100
@export var fortification: int = 0
@export var max_fortification: int = 0
@export var base_defense_strength: int = 20
@export var has_walls: bool = false
@export var defensive_strike_range: int = 1
@export var has_bombarded_this_turn: bool = false
@export var bombard_strength: int = 18
@export var bombard_range: int = 2
@export var garrison_unit_id: int = -1

@export_group("Population & Economy")
@export var population: int = 1
@export var food_stored: int = 0
@export var food_needed: int = 25
@export var housing: int = 4
@export var production_stored: int = 0
@export var current_production_id: String = "scout" # ID of unit or building being produced
@export var production_queue: Array[String] = [] # Queue of upcoming production item IDs

@export_group("Districts & Infrastructure")
@export var has_military_encampment: bool = false
@export var has_encampment: bool = false
@export var encampment_pos: Vector2i = Vector2i(-1, -1)
@export var encampment_health: int = 100
@export var encampment_max_health: int = 100
@export var encampment_fortification: int = 0
@export var encampment_max_fortification: int = 0
@export var has_science_camp: bool = false
@export var science_camp_pos: Vector2i = Vector2i(-1, -1)
@export var has_market: bool = false
@export var has_aqueduct: bool = false
@export var has_castle: bool = false
@export var has_neighborhood: bool = false
@export var neighborhood_pos: Vector2i = Vector2i(-1, -1)
@export var has_harbor: bool = false
@export var harbor_pos: Vector2i = Vector2i(-1, -1)
@export var planned_district_tiles: Dictionary = {} # district_id -> Vector2i
var housing_capacity: int:
	get: return housing
	set(val): housing = val
var harbor_coord: Vector2i:
	get: return harbor_pos
	set(val): harbor_pos = val
var current_health: int:
	get: return health
	set(val): health = val

@export_group("Territory")
@export var territory_tiles: Array[Vector2i] = []

@export_group("Visibility & Discovery")
@export var discovered_by_faction: Dictionary = {} # faction_id -> bool

signal city_attacked(damage: int, remaining_health: int, remaining_fortification: int)
signal city_bombarded(target_unit: RefCounted, damage: int)
signal city_captured(new_faction_id: int)
signal production_completed(item_id: String)
signal city_grown(new_population: int)

func initialize(p_id: int, p_name: String, p_faction: int, p_pos: Vector2i) -> void:
	city_id = p_id
	city_name = p_name
	faction_id = p_faction
	grid_pos = p_pos
	health = 100
	max_health = 100
	fortification = 0
	max_fortification = 0
	population = 1
	food_stored = 0
	housing = 4
	food_needed = 25
	production_stored = 0
	current_production_id = "scout"
	has_walls = false
	has_market = false
	has_aqueduct = false
	has_science_camp = false
	science_camp_pos = Vector2i(-1, -1)
	has_military_encampment = false
	has_encampment = false
	encampment_pos = Vector2i(-1, -1)
	encampment_health = 100
	encampment_max_health = 100
	encampment_fortification = 0
	encampment_max_fortification = 0
	has_neighborhood = false
	neighborhood_pos = Vector2i(-1, -1)
	has_castle = false
	planned_district_tiles = {}
	production_queue = []
	discovered_by_faction = { p_faction: true }
	territory_tiles = [p_pos]
	# Initial 1-ring radius territory
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var tile = p_pos + Vector2i(dx, dy)
			if not territory_tiles.has(tile):
				territory_tiles.append(tile)

## Takes damage according to the fortification absorption mechanics
## Fortification pool absorbs damage first. Excess damage pierces into city health.
func take_damage(incoming_damage: int) -> Dictionary:
	var absorbed_by_fort: int = 0
	var absorbed_by_hp: int = 0

	if fortification > 0:
		if incoming_damage <= fortification:
			fortification -= incoming_damage
			absorbed_by_fort = incoming_damage
			incoming_damage = 0
		else:
			absorbed_by_fort = fortification
			incoming_damage -= fortification
			fortification = 0

	if incoming_damage > 0:
		absorbed_by_hp = mini(incoming_damage, health)
		health -= absorbed_by_hp

	city_attacked.emit(absorbed_by_fort + absorbed_by_hp, health, fortification)

	var is_conquered = health <= 0
	return {
		"absorbed_by_fort": absorbed_by_fort,
		"absorbed_by_hp": absorbed_by_hp,
		"is_conquered": is_conquered,
		"remaining_hp": health,
		"remaining_fort": fortification
	}

func take_encampment_damage(incoming_damage: int) -> Dictionary:
	var absorbed_by_fort: int = 0
	var absorbed_by_hp: int = 0

	if encampment_fortification > 0:
		if incoming_damage <= encampment_fortification:
			encampment_fortification -= incoming_damage
			absorbed_by_fort = incoming_damage
			incoming_damage = 0
		else:
			absorbed_by_fort = encampment_fortification
			incoming_damage -= encampment_fortification
			encampment_fortification = 0

	if incoming_damage > 0:
		absorbed_by_hp = mini(incoming_damage, encampment_health)
		encampment_health -= absorbed_by_hp

	var is_destroyed = encampment_health <= 0
	return {
		"absorbed_by_fort": absorbed_by_fort,
		"absorbed_by_hp": absorbed_by_hp,
		"is_destroyed": is_destroyed,
		"remaining_hp": encampment_health,
		"remaining_fort": encampment_fortification
	}

## Fortification recovers per turn if city was not attacked
func regenerate_defenses() -> void:
	has_bombarded_this_turn = false
	if health < max_health:
		health = mini(max_health, health + 5)
	if has_walls and fortification < max_fortification:
		fortification = mini(max_fortification, fortification + 10)
	if has_military_encampment:
		if encampment_health < encampment_max_health:
			encampment_health = mini(encampment_max_health, encampment_health + 5)
		if has_walls and encampment_fortification < encampment_max_fortification:
			encampment_fortification = mini(encampment_max_fortification, encampment_fortification + 10)

## Adds production and returns completed item if threshold reached
func add_production(prod_amount: int, cost_lookup: Callable) -> String:
	if current_production_id == "":
		if not production_queue.is_empty():
			current_production_id = production_queue.pop_front()
		else:
			return ""
	production_stored += prod_amount
	var target_cost: int = cost_lookup.call(current_production_id)
	if production_stored >= target_cost and target_cost > 0:
		var finished_item = current_production_id
		production_stored -= target_cost
		if not production_queue.is_empty():
			current_production_id = production_queue.pop_front()
		else:
			current_production_id = "" # Idle until player chooses next project!
		production_completed.emit(finished_item)
		return finished_item
	return ""

## Queue helper methods
func queue_production(item_id: String) -> void:
	if current_production_id == "":
		current_production_id = item_id
	else:
		production_queue.append(item_id)

func remove_from_queue_at(index: int) -> void:
	if index >= 0 and index < production_queue.size():
		production_queue.remove_at(index)

func clear_production_queue() -> void:
	production_queue.clear()

## Calculates food required to grow to population + 1
func calculate_food_needed(pop: int) -> int:
	return 20 + int(12.0 * pow(float(pop), 1.35))

## Growth check with Civ 6 Housing rules
func add_food(food_amount: int) -> bool:
	var consumption = maxi(1, int(population * 1.5))
	var net_food = food_amount - consumption
	if net_food > 0:
		if population >= housing:
			# At or exceeding housing limit: growth halts completely!
			net_food = 0
			food_stored = mini(food_stored, food_needed - 1)
		elif population == housing - 1:
			# Near housing capacity: 50% growth penalty
			net_food = maxi(1, int(net_food * 0.5))
		food_stored += net_food
	else:
		food_stored += net_food

	if food_stored >= food_needed and population < housing:
		food_stored -= food_needed
		population += 1
		food_needed = calculate_food_needed(population)
		city_grown.emit(population)
		return true
	elif food_stored < 0:
		food_stored = 0
	return false

func get_effective_defense_strength() -> int:
	var strength = base_defense_strength + (population * 2)
	if has_walls:
		strength += 15
	if has_military_encampment:
		strength += 10
	if has_castle:
		strength += 20
	if garrison_unit_id != -1:
		strength += 10
	return strength

func is_discovered_by(faction_id: int) -> bool:
	return discovered_by_faction.get(faction_id, false)

