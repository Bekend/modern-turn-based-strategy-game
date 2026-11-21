class_name PathfindingSystem
extends RefCounted

## Pathfinding manager utilizing Godot's AStar2D with terrain movement cost weighting

var astar: AStar2D
var grid_model: GridModel
var width: int
var height: int

func _init(p_grid: GridModel) -> void:
	grid_model = p_grid
	width = grid_model.width
	height = grid_model.height
	astar = AStar2D.new()
	_build_graph()

func _coord_to_id(coords: Vector2i) -> int:
	return coords.y * width + coords.x

func _id_to_coord(id: int) -> Vector2i:
	return Vector2i(id % width, id / width)

func _build_graph() -> void:
	astar.clear()

	# Register all passable points
	for y in range(height):
		for x in range(width):
			var coords = Vector2i(x, y)
			var tile = grid_model.get_tile(coords)
			if tile and tile.biome_data.is_passable:
				var point_id = _coord_to_id(coords)
				astar.add_point(point_id, Vector2(coords.x, coords.y), tile.biome_data.move_cost)

	# Connect 4-way orthogonal neighbors
	for y in range(height):
		for x in range(width):
			var coords = Vector2i(x, y)
			var current_id = _coord_to_id(coords)
			if not astar.has_point(current_id):
				continue

			for neighbor in grid_model.get_neighbors(coords, false):
				var neighbor_id = _coord_to_id(neighbor)
				if astar.has_point(neighbor_id) and not astar.are_points_connected(current_id, neighbor_id):
					var dest_tile = grid_model.get_tile(neighbor)
					var weight = dest_tile.biome_data.move_cost
					# Connect bidirectional
					astar.connect_points(current_id, neighbor_id, true)
					astar.set_point_weight_scale(neighbor_id, float(weight))

## Find full path between two tiles
func find_path(from_coord: Vector2i, to_coord: Vector2i, highland_reduction: int = 0) -> Array[Vector2i]:
	var from_id = _coord_to_id(from_coord)
	var to_id = _coord_to_id(to_coord)

	if not astar.has_point(from_id) or not astar.has_point(to_id):
		return []

	var point_path = astar.get_point_path(from_id, to_id)
	var result: Array[Vector2i] = []
	for pt in point_path:
		result.append(Vector2i(int(pt.x), int(pt.y)))
	return result

## Returns all coordinates reachable within a given MP budget,
## dynamically factoring in terrain costs and tech perks
func get_reachable_tiles(start: Vector2i, mp_budget: int, highland_reduction: int = 0, impassable_coords: Array[Vector2i] = [], is_naval: bool = false, can_embark: bool = false) -> Dictionary:
	# Dictionary: Vector2i -> remaining_mp
	var reachable: Dictionary = { start: mp_budget }
	var queue: Array[Dictionary] = [{ "coord": start, "mp": mp_budget }]

	while not queue.is_empty():
		var current = queue.pop_front()
		var curr_coord: Vector2i = current["coord"]
		var curr_mp: int = current["mp"]

		for neighbor in grid_model.get_neighbors(curr_coord, false):
			if impassable_coords.has(neighbor):
				continue

			var tile = grid_model.get_tile(neighbor)
			if not tile or not tile.biome_data:
				continue

			var is_ocean = (tile.biome_data.biome_type == GameEnums.BiomeType.OCEAN)
			var cost: int = 1

			if is_naval:
				# Naval units can only move on ocean
				if not is_ocean:
					continue
				cost = 1
			else:
				# Land units
				if is_ocean:
					if not can_embark:
						continue
					cost = 2
				else:
					if not tile.biome_data.is_passable:
						continue
					cost = tile.biome_data.move_cost
					if tile.biome_data.biome_type == GameEnums.BiomeType.HILLS and highland_reduction > 0:
						cost = maxi(1, cost - highland_reduction)

			if curr_mp >= cost:
				var new_mp = curr_mp - cost
				if not reachable.has(neighbor) or reachable[neighbor] < new_mp:
					reachable[neighbor] = new_mp
					queue.append({ "coord": neighbor, "mp": new_mp })

	return reachable

## Temporarily block an enemy tile for pathfinding
func set_tile_blocked(coords: Vector2i, blocked: bool) -> void:
	var id = _coord_to_id(coords)
	if astar.has_point(id):
		astar.set_point_disabled(id, blocked)
