class_name PlayerInputController
extends Node

## Manages player selection state, action preview highlights, and command dispatch

signal unit_selected(unit: GameState.UnitInstance, reachable_tiles: Dictionary, attackable_tiles: Array[Vector2i])
signal city_selected(city: CityData)
signal fortification_selected(coords: Vector2i, imp_data: ImprovementData, attackable_tiles: Array[Vector2i])
signal tile_inspected(coords: Vector2i, tile_state: GridModel.TileState)
signal selection_cleared()
signal district_placement_started(city: CityData, district_id: String, valid_tiles: Array[Vector2i])
signal district_placement_ended()

var game_state: GameState
var turn_manager: TurnManager

var selected_unit: GameState.UnitInstance = null
var selected_city: CityData = null
var selected_fortification: Vector2i = Vector2i(-1, -1)
var current_reachable_tiles: Dictionary = {}
var current_attackable_tiles: Array[Vector2i] = []

var is_placing_district: bool = false
var placement_city: CityData = null
var placement_district_id: String = ""
var valid_district_tiles: Array[Vector2i] = []

func setup(p_game_state: GameState, p_turn_manager: TurnManager) -> void:
	game_state = p_game_state
	turn_manager = p_turn_manager

func start_district_placement(city: CityData, district_id: String) -> void:
	clear_selection()
	is_placing_district = true
	placement_city = city
	placement_district_id = district_id
	valid_district_tiles = get_valid_district_placement_tiles(city, district_id)
	district_placement_started.emit(city, district_id, valid_district_tiles)

func cancel_district_placement() -> void:
	is_placing_district = false
	placement_city = null
	placement_district_id = ""
	valid_district_tiles.clear()
	district_placement_ended.emit()

func get_valid_district_placement_tiles(city: CityData, district_id: String) -> Array[Vector2i]:
	var valid: Array[Vector2i] = []
	if not city or not game_state:
		return valid

	var planned_coords = city.planned_district_tiles.values()

	if district_id == "harbor":
		for coord in city.territory_tiles:
			if coord == city.grid_pos:
				continue
			if coord in planned_coords:
				continue
			var tile = game_state.grid_model.get_tile(coord)
			if tile and tile.biome_data.biome_type == GameEnums.BiomeType.OCEAN:
				if tile.improvement_data != null and tile.improvement_data.improvement_type == GameEnums.ImprovementType.HARBOR:
					continue
				valid.append(coord)
		return valid

	for coord in city.territory_tiles:
		if coord == city.grid_pos:
			continue
		if coord in planned_coords:
			continue
		var tile = game_state.grid_model.get_tile(coord)
		if not tile or not tile.biome_data.is_passable:
			continue
		if tile.biome_data.biome_type == GameEnums.BiomeType.OCEAN:
			continue
		if tile.improvement_data != null:
			var imp_t = tile.improvement_data.improvement_type
			if imp_t in [
				GameEnums.ImprovementType.MILITARY_ENCAMPMENT,
				GameEnums.ImprovementType.SCIENCE_CAMP,
				GameEnums.ImprovementType.NEIGHBORHOOD,
				GameEnums.ImprovementType.MARKET,
				GameEnums.ImprovementType.AQUEDUCT,
				GameEnums.ImprovementType.CASTLE,
				GameEnums.ImprovementType.HARBOR
			]:
				continue
		valid.append(coord)
	return valid

func on_tile_tapped(coords: Vector2i) -> void:
	if not game_state.grid_model.is_valid_coord(coords):
		if is_placing_district:
			cancel_district_placement()
		clear_selection()
		return

	if is_placing_district:
		if valid_district_tiles.has(coords):
			placement_city.planned_district_tiles[placement_district_id] = coords
			placement_city.current_production_id = placement_district_id
			var d_id = placement_district_id
			var c = placement_city
			cancel_district_placement()
			turn_manager.action_feedback.emit("📍 Planned %s for %s at (%d, %d)!" % [d_id.capitalize(), c.city_name, coords.x, coords.y], false)
			_select_city(c)
		else:
			turn_manager.action_feedback.emit("❌ Invalid location for district! Tap a highlighted tile or tap Cancel.", true)
		return

	var clicked_unit = game_state.get_unit_at(coords)
	var clicked_city = game_state.get_city_at(coords)

	# 1. Tapping a friendly city: if unit is garrisoned or no unit, select city
	if clicked_city and clicked_city.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
		if clicked_unit == null or clicked_unit.is_garrisoned:
			_select_city(clicked_city)
			return

	# 2. Tapping another friendly non-garrisoned unit -> ALWAYS switch selection immediately!
	if clicked_unit and clicked_unit.faction_id == GameEnums.FactionId.SOLARIS_DOMINION and clicked_unit != selected_unit and not clicked_unit.is_garrisoned:
		_select_unit(clicked_unit)
		return

	# 3. Tapping friendly city fallback (e.g. if unit was selected)
	if clicked_city and clicked_city.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
		if clicked_unit == null or clicked_unit == selected_unit:
			_select_city(clicked_city)
			return

	# 3. If we have an active city selection with walls and player tapped an in-range target
	if selected_city != null and current_attackable_tiles.has(coords):
		turn_manager.city_bombard_target(selected_city.city_id, coords)
		_select_city(selected_city)
		return

	# If we have an active fortification selection and player tapped an in-range target
	if selected_fortification != Vector2i(-1, -1) and current_attackable_tiles.has(coords):
		turn_manager.fortification_bombard_target(selected_fortification, coords)
		var f_tile = game_state.grid_model.get_tile(selected_fortification)
		if f_tile and f_tile.improvement_data:
			_select_fortification(selected_fortification, f_tile.improvement_data)
		else:
			clear_selection()
		return

	# 4. If we have an active unit selection and player tapped an in-range action
	if selected_unit != null:
		# Check if tapping an attackable enemy
		if current_attackable_tiles.has(coords):
			turn_manager.attack_target(selected_unit.instance_id, coords)
			_refresh_selected_unit()
			return

		# Check if tapping a reachable move destination
		if current_reachable_tiles.has(coords):
			if coords != selected_unit.grid_pos:
				var success = turn_manager.move_unit(selected_unit.instance_id, coords)
				if success:
					_refresh_selected_unit()
				return
		else:
			# Player tapped a tile within reach distance that cannot be entered
			var dist = absi(coords.x - selected_unit.grid_pos.x) + absi(coords.y - selected_unit.grid_pos.y)
			if dist <= 3:
				var target_tile = game_state.grid_model.get_tile(coords)
				if target_tile and target_tile.biome_data.biome_type == GameEnums.BiomeType.OCEAN:
					var is_naval: bool = selected_unit.is_naval_unit()
					if not is_naval:
						turn_manager.action_feedback.emit("Water traversal requires Shipbuilding technology to embark!", true)
					else:
						turn_manager.action_feedback.emit("Not enough MP to navigate waters.", true)
				elif target_tile and not target_tile.biome_data.is_passable:
					turn_manager.action_feedback.emit("Impassable terrain (%s)!" % target_tile.biome_data.biome_name, true)
				elif selected_unit.remaining_mp <= 0:
					turn_manager.action_feedback.emit("Unit exhausted all MP for this turn. Press END TURN.", true)
				else:
					turn_manager.action_feedback.emit("Not enough MP to reach tile (Hills cost 2 MP).", true)
				return # Keep unit selected!

	# 4. Check if clicking friendly unit (re-selecting or first selection)
	if clicked_unit and clicked_unit.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
		_select_unit(clicked_unit)
		return

	# 5. Check if clicking a friendly city
	if clicked_city and clicked_city.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
		_select_city(clicked_city)
		return

	# 6. Check if clicking an enemy / barbarian unit to inspect
	if clicked_unit:
		clear_selection()
		unit_selected.emit(clicked_unit, {}, [])
		return

	# 7. Check if clicking a rival city to inspect
	if clicked_city:
		clear_selection()
		city_selected.emit(clicked_city)
		return

	# 8. Check if clicking a friendly fortification (Encampment or Temporary Camp)
	var tile_for_fort = game_state.grid_model.get_tile(coords)
	if tile_for_fort and tile_for_fort.owner_faction_id == GameEnums.FactionId.SOLARIS_DOMINION and tile_for_fort.improvement_data:
		var imp_type = tile_for_fort.improvement_data.improvement_type
		if imp_type == GameEnums.ImprovementType.MILITARY_ENCAMPMENT or imp_type == GameEnums.ImprovementType.TEMPORARY_CAMP:
			_select_fortification(coords, tile_for_fort.improvement_data)
			return

	# 9. Otherwise: inspect terrain tile
	clear_selection()
	var tile_state = game_state.grid_model.get_tile(coords)
	tile_inspected.emit(coords, tile_state)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			cycle_next_unit()
			return

		if selected_unit != null:
			match event.keycode:
				KEY_UP, KEY_W:
					move_selected_unit_direction(Vector2i(0, -1))
				KEY_DOWN, KEY_S:
					move_selected_unit_direction(Vector2i(0, 1))
				KEY_LEFT, KEY_A:
					move_selected_unit_direction(Vector2i(-1, 0))
				KEY_RIGHT, KEY_D:
					move_selected_unit_direction(Vector2i(1, 0))
				KEY_ESCAPE:
					clear_selection()

## Cycles to the next friendly unit (prefers units with remaining movement points)
func cycle_next_unit() -> void:
	var p_units = game_state.get_faction_units(GameEnums.FactionId.SOLARIS_DOMINION)
	if p_units.is_empty():
		clear_selection()
		return

	var start_idx = 0
	if selected_unit:
		var curr_idx = p_units.find(selected_unit)
		if curr_idx >= 0:
			start_idx = (curr_idx + 1) % p_units.size()

	var chosen: GameState.UnitInstance = null
	for i in range(p_units.size()):
		var u = p_units[(start_idx + i) % p_units.size()]
		if u.remaining_mp > 0 and not u.is_turn_skipped and not u.is_fortified:
			chosen = u
			break

	# Fallback: If all units exhausted MP, cycle to next unit anyway for inspection
	if chosen == null:
		chosen = p_units[start_idx]

	_select_unit(chosen)

## Cycles to the next friendly city
func cycle_next_city() -> void:
	var p_cities = game_state.get_faction_cities(GameEnums.FactionId.SOLARIS_DOMINION)
	if p_cities.is_empty():
		turn_manager.action_feedback.emit("No cities founded yet! Use your Settler to found a city.", true)
		clear_selection()
		return

	var start_idx = 0
	if selected_city:
		var curr_idx = p_cities.find(selected_city)
		if curr_idx >= 0:
			start_idx = (curr_idx + 1) % p_cities.size()

	var chosen = p_cities[start_idx]
	_select_city(chosen)


## Moves the selected unit in a cardinal direction (D-Pad support)
func move_selected_unit_direction(dir: Vector2i) -> bool:
	if selected_unit == null:
		turn_manager.action_feedback.emit("No unit selected. Tap a friendly unit first.", true)
		return false

	if selected_unit.remaining_mp <= 0:
		turn_manager.action_feedback.emit("Unit exhausted all MP for this turn. Press END TURN.", true)
		return false

	var target = selected_unit.grid_pos + dir
	if not game_state.grid_model.is_valid_coord(target):
		turn_manager.action_feedback.emit("Cannot move outside map boundaries.", true)
		return false

	# If target has enemy, attack it!
	var enemy_u = game_state.get_unit_at(target)
	var enemy_c = game_state.get_city_at(target)
	if (enemy_u and enemy_u.faction_id != selected_unit.faction_id) or (enemy_c and enemy_c.faction_id != selected_unit.faction_id):
		var ok = turn_manager.attack_target(selected_unit.instance_id, target)
		_refresh_selected_unit()
		return ok

	if not current_reachable_tiles.has(target):
		var tile = game_state.grid_model.get_tile(target)
		if tile and not tile.biome_data.is_passable:
			turn_manager.action_feedback.emit("Terrain is impassable (%s)!" % tile.biome_data.biome_name, true)
		else:
			turn_manager.action_feedback.emit("Not enough MP to enter tile (Hills cost 2 MP)!", true)
		return false

	var ok = turn_manager.move_unit(selected_unit.instance_id, target)
	if ok:
		_refresh_selected_unit()
	return ok

func _select_unit(unit: GameState.UnitInstance) -> void:
	if unit == null:
		clear_selection()
		return

	selected_unit = unit
	selected_city = null

	var reduction = game_state.tech_manager.get_highland_move_reduction(unit.faction_id)
	var is_naval: bool = unit.is_naval_unit()
	var can_embark = game_state.tech_manager.can_faction_embark(unit.faction_id) if (game_state.tech_manager and game_state.tech_manager.has_method("can_faction_embark")) else false
	# Collect impassable foreign fortified obstacles
	var impassable_coords: Array[Vector2i] = []
	for y in range(game_state.grid_model.height):
		for x in range(game_state.grid_model.width):
			var c = Vector2i(x, y)
			var t = game_state.grid_model.get_tile(c)
			if t:
				var is_foreign = (t.owner_faction_id != -1 and t.owner_faction_id != unit.faction_id)
				if is_foreign and (t.has_border_wall or (t.improvement_data and t.improvement_data.improvement_type == GameEnums.ImprovementType.BORDER_WALL)):
					impassable_coords.append(c)
				elif is_foreign and t.improvement_data and (t.improvement_data.improvement_type == GameEnums.ImprovementType.MILITARY_ENCAMPMENT or t.improvement_data.improvement_type == GameEnums.ImprovementType.TEMPORARY_CAMP):
					impassable_coords.append(c)

	var raw_reachable = game_state.pathfinding.get_reachable_tiles(unit.grid_pos, unit.remaining_mp, reduction, impassable_coords, is_naval, can_embark)

	# Exclude hostile units, friendly other units, enemy cities, and foreign fortifications from movement destinations
	current_reachable_tiles.clear()
	for tile_pos in raw_reachable.keys():
		var occupant = game_state.get_unit_at(tile_pos)
		if occupant != null and occupant.instance_id != unit.instance_id:
			continue
		var city_at_tile = game_state.get_city_at(tile_pos)
		if city_at_tile != null and city_at_tile.faction_id != unit.faction_id:
			continue
		var tile_obj = game_state.grid_model.get_tile(tile_pos)
		if tile_obj:
			var is_foreign = (tile_obj.owner_faction_id != -1 and tile_obj.owner_faction_id != unit.faction_id)
			if is_foreign and (tile_obj.has_border_wall or (tile_obj.improvement_data and tile_obj.improvement_data.improvement_type == GameEnums.ImprovementType.BORDER_WALL)):
				continue
			if is_foreign and tile_obj.improvement_data and (tile_obj.improvement_data.improvement_type == GameEnums.ImprovementType.MILITARY_ENCAMPMENT or tile_obj.improvement_data.improvement_type == GameEnums.ImprovementType.TEMPORARY_CAMP):
				continue
		current_reachable_tiles[tile_pos] = raw_reachable[tile_pos]

	# Determine attackable targets
	current_attackable_tiles.clear()
	var current_tile = game_state.grid_model.get_tile(unit.grid_pos)
	var is_on_water = (current_tile and current_tile.biome_data.biome_type == GameEnums.BiomeType.OCEAN)
	var is_embarked_land = (is_on_water or unit.is_embarked) and not is_naval

	if not unit.data.is_civilian() and not unit.has_attacked and unit.remaining_mp > 0 and not is_embarked_land:
		var max_range = unit.data.attack_range
		for dx in range(-max_range, max_range + 1):
			for dy in range(-max_range, max_range + 1):
				var dist = absi(dx) + absi(dy)
				if dist > 0 and dist <= max_range:
					var target = unit.grid_pos + Vector2i(dx, dy)
					var enemy_u = game_state.get_unit_at(target)
					if enemy_u and enemy_u.faction_id != unit.faction_id:
						current_attackable_tiles.append(target)
					var enemy_c = game_state.get_city_at(target)
					if enemy_c and enemy_c.faction_id != unit.faction_id:
						current_attackable_tiles.append(target)
					var target_t = game_state.grid_model.get_tile(target)
					if target_t:
						var is_foreign = (target_t.owner_faction_id != -1 and target_t.owner_faction_id != unit.faction_id)
						if is_foreign and (target_t.has_border_wall or (target_t.improvement_data and target_t.improvement_data.improvement_type == GameEnums.ImprovementType.BORDER_WALL)):
							if not current_attackable_tiles.has(target):
								current_attackable_tiles.append(target)
						elif is_foreign and target_t.improvement_data and (target_t.improvement_data.improvement_type == GameEnums.ImprovementType.MILITARY_ENCAMPMENT or target_t.improvement_data.improvement_type == GameEnums.ImprovementType.TEMPORARY_CAMP):
							if not current_attackable_tiles.has(target):
								current_attackable_tiles.append(target)

	unit_selected.emit(unit, current_reachable_tiles, current_attackable_tiles)

func select_city(city: CityData) -> void:
	_select_city(city)

func _select_city(city: CityData) -> void:
	if city == null:
		clear_selection()
		return

	selected_city = city
	selected_unit = null
	selected_fortification = Vector2i(-1, -1)
	current_reachable_tiles.clear()
	current_attackable_tiles.clear()

	# If player walled city has not yet bombarded this turn, find targets in range
	if city.faction_id == GameEnums.FactionId.SOLARIS_DOMINION and city.has_walls and not city.has_bombarded_this_turn:
		var max_range = city.bombard_range
		for dx in range(-max_range, max_range + 1):
			for dy in range(-max_range, max_range + 1):
				var dist = absi(dx) + absi(dy)
				if dist > 0 and dist <= max_range:
					var target = city.grid_pos + Vector2i(dx, dy)
					var enemy_u = game_state.get_unit_at(target)
					if enemy_u and enemy_u.faction_id != city.faction_id:
						current_attackable_tiles.append(target)

	city_selected.emit(city)

func _select_fortification(coords: Vector2i, imp: ImprovementData) -> void:
	selected_fortification = coords
	selected_unit = null
	selected_city = null
	current_reachable_tiles.clear()
	current_attackable_tiles.clear()

	var can_fire = not imp.has_bombarded_this_turn
	if imp.improvement_type == GameEnums.ImprovementType.MILITARY_ENCAMPMENT and not imp.has_walls:
		can_fire = false

	if can_fire:
		var max_range = imp.bombard_range
		for dx in range(-max_range, max_range + 1):
			for dy in range(-max_range, max_range + 1):
				var dist = absi(dx) + absi(dy)
				if dist > 0 and dist <= max_range:
					var target = coords + Vector2i(dx, dy)
					var enemy_u = game_state.get_unit_at(target)
					if enemy_u and enemy_u.faction_id != GameEnums.FactionId.SOLARIS_DOMINION:
						current_attackable_tiles.append(target)

	fortification_selected.emit(coords, imp, current_attackable_tiles)

func _refresh_selected_unit() -> void:
	if selected_unit and game_state.units.has(selected_unit.instance_id):
		_select_unit(selected_unit)
	else:
		clear_selection()

func clear_selection() -> void:
	selected_unit = null
	selected_city = null
	selected_fortification = Vector2i(-1, -1)
	current_reachable_tiles.clear()
	current_attackable_tiles.clear()
	selection_cleared.emit()
