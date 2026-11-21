class_name GridModel
extends RefCounted

## Pure data model representing the 2D game grid state independent of rendering

signal tile_changed(coords: Vector2i)
signal tile_updated(coords: Vector2i)

class TileState:
	var coords: Vector2i
	var biome_data: BiomeData
	var elevation: float = 0.0
	var resource_data: ResourceData = null
	var improvement_data: ImprovementData = null
	var owner_faction_id: int = -1 # -1: Unclaimed
	var city_id: int = -1
	var is_city: bool = false
	var unit_id: int = -1
	var natural_science: int = 0
	var science_tag: String = ""
	var has_border_wall: bool = false
	var border_wall_health: int = 50
	var border_wall_max_health: int = 50
	# Fog of war visibility flags per faction: { faction_id: bool }
	var revealed_by_faction: Dictionary = {}
	var visible_by_faction: Dictionary = {}

	func _init(p_coords: Vector2i, p_biome: BiomeData) -> void:
		coords = p_coords
		biome_data = p_biome

var width: int = 36
var height: int = 24
var tiles: Dictionary = {} # Vector2i -> TileState

func initialize(p_width: int, p_height: int) -> void:
	width = p_width
	height = p_height
	tiles.clear()

func set_tile(coords: Vector2i, biome: BiomeData) -> TileState:
	var state = TileState.new(coords, biome)
	tiles[coords] = state
	return state

func get_tile(coords: Vector2i) -> TileState:
	return tiles.get(coords, null)

func is_valid_coord(coords: Vector2i) -> bool:
	return coords.x >= 0 and coords.x < width and coords.y >= 0 and coords.y < height

func is_passable(coords: Vector2i) -> bool:
	var tile = get_tile(coords)
	if not tile:
		return false
	return tile.biome_data.is_passable

func get_move_cost(coords: Vector2i) -> int:
	var tile = get_tile(coords)
	if not tile:
		return 999
	return tile.biome_data.move_cost

func get_defense_bonus(coords: Vector2i) -> int:
	var tile = get_tile(coords)
	if not tile:
		return 0
	var bonus = tile.biome_data.defense_bonus_percent
	if tile.improvement_data:
		bonus += tile.improvement_data.defense_bonus_percent
	return bonus

func get_neighbors(coords: Vector2i, include_diagonals: bool = false) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var offsets: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)
	]
	if include_diagonals:
		offsets.append_array([
			Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)
		])

	for offset in offsets:
		var next = coords + offset
		if is_valid_coord(next):
			result.append(next)
	return result

func get_all_tiles_in_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var tile = center + Vector2i(dx, dy)
			if is_valid_coord(tile) and absi(dx) + absi(dy) <= radius + 1: # Chebychev / Manhattan blend
				result.append(tile)
	return result

func clear_visibility(faction_id: int) -> void:
	for tile in tiles.values():
		tile.visible_by_faction[faction_id] = false

func reveal_tile(coords: Vector2i, faction_id: int) -> void:
	var tile = get_tile(coords)
	if tile:
		tile.revealed_by_faction[faction_id] = true
		tile.visible_by_faction[faction_id] = true
