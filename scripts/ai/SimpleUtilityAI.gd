class_name SimpleUtilityAI
extends RefCounted

## Utility AI governing rival factions and neutral Barbarian raiders

var game_state: GameState
var unit_prototypes: Dictionary = {}
var improvement_farm: ImprovementData
var improvement_mine: ImprovementData

func _init(p_game_state: GameState) -> void:
	game_state = p_game_state
	_load_prototypes()

func _load_prototypes() -> void:
	var ids = [
		"settler", "builder", "scout", "slinger", "archer", "spearman",
		"swordsman", "horseman", "catapult", "crossbowman", "knight",
		"barbarian_raider", "barbarian_horseman",
		"galley", "quadrireme", "galleass",
		"musketman", "bombard", "cuirassier", "frigate"
	]
	for uid in ids:
		var path = "res://resources/units/%s.tres" % uid
		if ResourceLoader.exists(path):
			unit_prototypes[uid] = load(path)

	improvement_farm = load("res://resources/improvements/farm.tres")
	improvement_mine = load("res://resources/improvements/mine.tres")

## Main AI entry point for a faction turn
func execute_faction_turn(faction_id: int) -> void:
	if faction_id == GameEnums.FactionId.BARBARIANS:
		_execute_barbarian_turn()
	else:
		_execute_rival_faction_turn(faction_id)

# -------------------------------------------------------------
# DIPLOMACY / HOSTILITY CHECKS
# -------------------------------------------------------------
func _is_hostile(my_faction: int, other_faction: int) -> bool:
	if my_faction == other_faction:
		return false
	if my_faction == GameEnums.FactionId.BARBARIANS or other_faction == GameEnums.FactionId.BARBARIANS:
		return true
	if game_state.diplomacy_manager:
		return game_state.diplomacy_manager.is_at_war(my_faction, other_faction)
	return false

# -------------------------------------------------------------
# BARBARIAN RAIDER AI
# -------------------------------------------------------------
func _execute_barbarian_turn() -> void:
	var barbs = game_state.get_faction_units(GameEnums.FactionId.BARBARIANS)
	for barb in barbs:
		if barb.remaining_mp <= 0 or barb.has_attacked:
			continue

		# 1. First priority: Attack adjacent enemy unit or city
		var target_unit = _find_adjacent_enemy_unit(barb)
		if target_unit:
			_attack_unit(barb, target_unit)
			continue

		var target_city = _find_adjacent_enemy_city(barb)
		if target_city:
			_attack_city(barb, target_city)
			continue

		# 2. Check if current tile can be pillaged to heal and destroy infrastructure
		if _try_barbarian_pillage(barb):
			continue

		# 3. Seek nearest non-barbarian target (AI or Player) across extended map radius (up to 50 tiles)
		var nearest_target = _find_nearest_hostile_target(barb.grid_pos, GameEnums.FactionId.BARBARIANS, 50)
		if nearest_target != Vector2i(-1, -1):
			_move_towards(barb, nearest_target)

			# After moving, check if we can attack adjacent unit or city!
			target_unit = _find_adjacent_enemy_unit(barb)
			if target_unit and barb.remaining_mp > 0 and not barb.has_attacked:
				_attack_unit(barb, target_unit)
				continue

			target_city = _find_adjacent_enemy_city(barb)
			if target_city and barb.remaining_mp > 0 and not barb.has_attacked:
				_attack_city(barb, target_city)
				continue

			# Or pillage tile reached after movement
			if _try_barbarian_pillage(barb):
				continue
		else:
			# If no target found, wander towards center of map
			var map_center = Vector2i(game_state.grid_model.width / 2, game_state.grid_model.height / 2)
			_move_towards(barb, map_center)

func _try_barbarian_pillage(barb: GameState.UnitInstance) -> bool:
	if not game_state.grid_model:
		return false
	var tile = game_state.grid_model.get_tile(barb.grid_pos)
	if tile and tile.improvement_data and tile.owner_faction_id != GameEnums.FactionId.BARBARIANS and tile.owner_faction_id != -1:
		tile.improvement_data = null
		barb.current_health = mini(barb.data.max_health, barb.current_health + 20)
		barb.remaining_mp = 0
		barb.has_attacked = true
		game_state.grid_model.tile_updated.emit(barb.grid_pos)
		return true
	return false

# -------------------------------------------------------------
# RIVAL CIVILIZATION AI
# -------------------------------------------------------------
func _execute_rival_faction_turn(faction_id: int) -> void:
	# 1. Manage Cities & Production
	var cities = game_state.get_faction_cities(faction_id)
	for city in cities:
		_manage_city_production(city, faction_id)
		if city.has_walls and not city.has_bombarded_this_turn:
			_execute_city_bombardment(city)

	# 1b. Manage Fortification Bombardment (Encampments & Outposts)
	_execute_all_fortification_bombardments(faction_id)

	# 2. Move & Action Units
	var units = game_state.get_faction_units(faction_id)
	for unit in units:
		if unit.remaining_mp <= 0:
			continue

		# Try upgrading unit if possible
		_try_upgrade_unit(unit, faction_id)

		if unit.data.can_found_city:
			_execute_settler_ai(unit, faction_id)
		elif unit.data.can_build_improvements:
			_execute_builder_ai(unit)
		elif unit.data.id == "scout":
			_execute_scout_ai(unit, faction_id)
		elif unit.data.is_ranged():
			_execute_ranged_military_ai(unit, faction_id)
		else:
			_execute_melee_military_ai(unit, faction_id)

func _try_upgrade_unit(unit: GameState.UnitInstance, faction_id: int) -> bool:
	if unit.data.upgrade_unit_id == "":
		return false
	var target_id = unit.data.upgrade_unit_id
	var cost = unit.data.upgrade_cost
	var proto: UnitData = unit_prototypes.get(target_id, null)
	if not proto:
		return false
	if proto.tech_prerequisite != "" and not game_state.tech_manager.is_tech_researched(faction_id, proto.tech_prerequisite):
		return false
	if proto.strategic_prerequisite != "":
		var strat_res = game_state.get_available_strategic_resources(faction_id)
		if strat_res.get(proto.strategic_prerequisite, 0) < 1:
			return false
	var gold = game_state.faction_gold.get(faction_id, 0)
	if gold >= cost:
		game_state.faction_gold[faction_id] -= cost
		game_state.upgrade_unit(unit.instance_id, proto)
		return true
	return false

func _manage_city_production(city: CityData, faction_id: int) -> void:
	var units = game_state.get_faction_units(faction_id)
	var cities = game_state.get_faction_cities(faction_id)

	var has_settler = false
	var military_count = 0
	for u in units:
		if u.data.can_found_city:
			has_settler = true
		elif not u.data.is_civilian():
			military_count += 1

	var strat_res = game_state.get_available_strategic_resources(faction_id)
	var req_strat_amount = game_state.get_required_resource_amount_for_city(city)

	# Decide next production respecting pop drafting and encampment resource discounts:
	if not has_settler and cities.size() < 3 and city.population >= 2:
		city.current_production_id = "settler"
	elif not city.has_walls and military_count >= 2:
		city.current_production_id = "walls"
	elif game_state.tech_manager.is_unit_unlocked(faction_id, "knight") and strat_res.get("horses", 0) >= req_strat_amount and city.population >= 3:
		city.current_production_id = "knight"
	elif game_state.tech_manager.is_unit_unlocked(faction_id, "crossbowman") and strat_res.get("iron", 0) >= req_strat_amount and city.population >= 3:
		city.current_production_id = "crossbowman"
	elif game_state.tech_manager.is_unit_unlocked(faction_id, "catapult") and strat_res.get("iron", 0) >= req_strat_amount and city.population >= 3:
		city.current_production_id = "catapult"
	elif game_state.tech_manager.is_unit_unlocked(faction_id, "swordsman") and strat_res.get("iron", 0) >= req_strat_amount and city.population >= 2:
		city.current_production_id = "swordsman"
	elif game_state.tech_manager.is_unit_unlocked(faction_id, "spearman") and city.population >= 2:
		city.current_production_id = "spearman"
	elif game_state.tech_manager.is_unit_unlocked(faction_id, "archer") and city.population >= 2:
		city.current_production_id = "archer"
	elif game_state.tech_manager.is_unit_unlocked(faction_id, "slinger"):
		city.current_production_id = "slinger"
	else:
		city.current_production_id = "scout"

func _execute_settler_ai(settler: GameState.UnitInstance, faction_id: int) -> void:
	var current_tile = game_state.grid_model.get_tile(settler.grid_pos)
	if current_tile and current_tile.owner_faction_id == -1 and _is_far_from_all_cities(settler.grid_pos, 4):
		var c_name = "%s Haven %d" % [game_state.faction_names[faction_id], game_state.next_city_id]
		game_state.found_city(faction_id, settler.grid_pos, c_name)
		game_state.remove_unit(settler.instance_id)
		return

	var best_spot = _find_best_city_location(settler.grid_pos)
	if best_spot != Vector2i(-1, -1):
		_move_towards(settler, best_spot)

func _execute_builder_ai(builder: GameState.UnitInstance) -> void:
	var tile = game_state.grid_model.get_tile(builder.grid_pos)
	if tile and tile.improvement_data == null:
		if tile.resource_data and tile.resource_data.resource_type == GameEnums.StrategicResourceType.RICE:
			tile.improvement_data = improvement_farm
			builder.remaining_mp = 0
			return
		elif tile.biome_data.biome_type == GameEnums.BiomeType.HILLS:
			tile.improvement_data = improvement_mine
			builder.remaining_mp = 0
			return

	for n in game_state.grid_model.get_neighbors(builder.grid_pos, false):
		var nt = game_state.grid_model.get_tile(n)
		if nt and nt.biome_data.is_passable and nt.improvement_data == null:
			_move_towards(builder, n)
			break

func _execute_scout_ai(scout: GameState.UnitInstance, faction_id: int) -> void:
	# Explore towards nearest unrevealed tile
	var target = _find_nearest_unrevealed_tile(scout.grid_pos, faction_id, 20)
	if target != Vector2i(-1, -1):
		_move_towards(scout, target)
	else:
		# If entire local sector revealed, wander towards map corners
		var center = Vector2i(game_state.grid_model.width / 2, game_state.grid_model.height / 2)
		var dir = (scout.grid_pos - center)
		var wander_target = scout.grid_pos + Vector2i(signi(dir.x) * 4, signi(dir.y) * 4)
		wander_target.x = clampi(wander_target.x, 0, game_state.grid_model.width - 1)
		wander_target.y = clampi(wander_target.y, 0, game_state.grid_model.height - 1)
		_move_towards(scout, wander_target)

func _execute_melee_military_ai(unit: GameState.UnitInstance, faction_id: int) -> void:
	# 1. Attack adjacent hostile unit or city (prioritize vulnerable city)
	var enemy_city = _find_adjacent_enemy_city(unit)
	if enemy_city and (enemy_city.health < 40 or not _find_adjacent_enemy_unit(unit)):
		_attack_city(unit, enemy_city)
		return

	var enemy_unit = _find_adjacent_enemy_unit(unit)
	if enemy_unit:
		_attack_unit(unit, enemy_unit)
		return

	if enemy_city:
		_attack_city(unit, enemy_city)
		return

	# 2. Seek nearest hostile target (extended range 25 to actively siege/hunt)
	var target = _find_nearest_hostile_target(unit.grid_pos, faction_id, 25)
	if target != Vector2i(-1, -1):
		_move_towards(unit, target)
		# Post-move attack check (check city and unit!)
		enemy_city = _find_adjacent_enemy_city(unit)
		if enemy_city and unit.remaining_mp > 0 and not unit.has_attacked and enemy_city.health < 40:
			_attack_city(unit, enemy_city)
			return
		enemy_unit = _find_adjacent_enemy_unit(unit)
		if enemy_unit and unit.remaining_mp > 0 and not unit.has_attacked:
			_attack_unit(unit, enemy_unit)
			return
		if enemy_city and unit.remaining_mp > 0 and not unit.has_attacked:
			_attack_city(unit, enemy_city)
			return
	else:
		# If no hostile target known, explore shroud or patrol territory
		var unrevealed = _find_nearest_unrevealed_tile(unit.grid_pos, faction_id, 15)
		if unrevealed != Vector2i(-1, -1):
			_move_towards(unit, unrevealed)
		else:
			# Patrol towards nearest own city border
			var cities = game_state.get_faction_cities(faction_id)
			if not cities.is_empty():
				var c_pos = cities[0].grid_pos
				var dist = absi(unit.grid_pos.x - c_pos.x) + absi(unit.grid_pos.y - c_pos.y)
				if dist > 4:
					_move_towards(unit, c_pos)

func _execute_ranged_military_ai(unit: GameState.UnitInstance, faction_id: int) -> void:
	# Check 2-tile radius for hostile units or cities
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var dist = absi(dx) + absi(dy)
			if dist <= 2 and dist > 0:
				var check_pos = unit.grid_pos + Vector2i(dx, dy)
				var enemy_c = game_state.get_city_at(check_pos)
				if enemy_c and _is_hostile(faction_id, enemy_c.faction_id):
					_attack_city_ranged(unit, enemy_c)
					return
				var enemy_u = game_state.get_unit_at(check_pos)
				if enemy_u and _is_hostile(faction_id, enemy_u.faction_id):
					_attack_ranged(unit, enemy_u)
					return

	# If no enemy in range, move towards nearest hostile target (range 25)
	var target = _find_nearest_hostile_target(unit.grid_pos, faction_id, 25)
	if target != Vector2i(-1, -1):
		_move_towards(unit, target)
		# Post-move ranged attack check
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				var dist = absi(dx) + absi(dy)
				if dist <= 2 and dist > 0 and unit.remaining_mp > 0 and not unit.has_attacked:
					var check_pos = unit.grid_pos + Vector2i(dx, dy)
					var enemy_c = game_state.get_city_at(check_pos)
					if enemy_c and _is_hostile(faction_id, enemy_c.faction_id):
						_attack_city_ranged(unit, enemy_c)
						return
					var enemy_u = game_state.get_unit_at(check_pos)
					if enemy_u and _is_hostile(faction_id, enemy_u.faction_id):
						_attack_ranged(unit, enemy_u)
						return
	else:
		var unrevealed = _find_nearest_unrevealed_tile(unit.grid_pos, faction_id, 15)
		if unrevealed != Vector2i(-1, -1):
			_move_towards(unit, unrevealed)

# -------------------------------------------------------------
# HELPER ACTIONS
# -------------------------------------------------------------
func _find_adjacent_enemy_unit(unit: GameState.UnitInstance) -> GameState.UnitInstance:
	for n in game_state.grid_model.get_neighbors(unit.grid_pos, false):
		# Civ 6 rule: garrisoned units inside a city cannot be targeted directly!
		if game_state.get_city_at(n) != null:
			continue
		var target = game_state.get_unit_at(n)
		if target and _is_hostile(unit.faction_id, target.faction_id):
			return target
	return null

func _find_adjacent_enemy_city(unit: GameState.UnitInstance) -> CityData:
	for n in game_state.grid_model.get_neighbors(unit.grid_pos, false):
		var city = game_state.get_city_at(n)
		if city and _is_hostile(unit.faction_id, city.faction_id):
			return city
	return null

func _attack_unit(attacker: GameState.UnitInstance, defender: GameState.UnitInstance) -> void:
	var terrain_bonus = game_state.grid_model.get_defense_bonus(defender.grid_pos)
	var faction_bonus = game_state.tech_manager.get_combat_attack_bonus_percent(attacker.faction_id)

	var result = CombatEngine.resolve_unit_melee(
		attacker.data.combat_strength,
		attacker.current_health,
		defender.data.combat_strength,
		defender.current_health,
		terrain_bonus,
		faction_bonus
	)

	attacker.current_health = result.remaining_attacker_hp
	defender.current_health = result.remaining_defender_hp
	attacker.remaining_mp = 0
	attacker.has_attacked = true
	attacker.is_fortified = false
	attacker.fortify_turns = 0
	attacker.is_resting_heal = false
	defender.is_fortified = false
	defender.fortify_turns = 0
	defender.is_resting_heal = false

	game_state.unit_attacked.emit(attacker, defender, result)

	if result.defender_died:
		game_state.remove_unit(defender.instance_id)
		# Melee attacker advances into vacated tile only if not occupied by living city
		if not attacker.data.is_ranged() and game_state.get_city_at(defender.grid_pos) == null:
			_advance_unit_into_tile(attacker, defender.grid_pos)

	if result.attacker_died:
		game_state.remove_unit(attacker.instance_id)

func _attack_ranged(attacker: GameState.UnitInstance, defender: GameState.UnitInstance) -> void:
	var terrain_bonus = game_state.grid_model.get_defense_bonus(defender.grid_pos)
	var result = CombatEngine.resolve_ranged_attack(
		attacker.data.ranged_strength,
		attacker.current_health,
		defender.data.combat_strength,
		defender.current_health,
		terrain_bonus
	)
	defender.current_health = result.remaining_defender_hp
	attacker.remaining_mp = 0
	attacker.has_attacked = true
	attacker.is_fortified = false
	attacker.fortify_turns = 0
	attacker.is_resting_heal = false
	defender.is_fortified = false
	defender.fortify_turns = 0
	defender.is_resting_heal = false
	game_state.unit_attacked.emit(attacker, defender, result)

	if result.defender_died:
		game_state.remove_unit(defender.instance_id)

func _attack_city(attacker: GameState.UnitInstance, city: CityData) -> void:
	var is_ranged = attacker.data.is_ranged()
	var strength = attacker.data.ranged_strength if is_ranged else attacker.data.combat_strength
	var result = CombatEngine.resolve_city_siege(strength, attacker.current_health, city, is_ranged)
	attacker.current_health = result.remaining_attacker_hp
	attacker.remaining_mp = 0
	attacker.has_attacked = true

	game_state.city_attacked.emit(attacker, city, result)

	if result.city_captured:
		var target_coord = city.grid_pos
		# Remove defeated enemy garrison if present
		var garrison = game_state.get_unit_at(target_coord)
		if garrison and garrison.faction_id != attacker.faction_id:
			game_state.remove_unit(garrison.instance_id)
		game_state.raze_city(city.city_id, attacker.faction_id)
		if not is_ranged:
			_advance_unit_into_tile(attacker, target_coord)

	if result.attacker_died:
		game_state.remove_unit(attacker.instance_id)

func _attack_city_ranged(attacker: GameState.UnitInstance, city: CityData) -> void:
	var result = CombatEngine.resolve_city_siege(attacker.data.ranged_strength, attacker.current_health, city, true)
	attacker.remaining_mp = 0
	attacker.has_attacked = true

	if result.city_captured:
		var target_coord = city.grid_pos
		var garrison = game_state.get_unit_at(target_coord)
		if garrison and garrison.faction_id != attacker.faction_id:
			game_state.remove_unit(garrison.instance_id)
		game_state.raze_city(city.city_id, attacker.faction_id)

func _advance_unit_into_tile(unit: GameState.UnitInstance, target_coord: Vector2i) -> void:
	var old_pos = unit.grid_pos
	var old_tile = game_state.grid_model.get_tile(old_pos)
	if old_tile and old_tile.unit_id == unit.instance_id:
		old_tile.unit_id = -1

	# Clear garrison link and reset tactical states
	var old_city = game_state.get_city_at(old_pos)
	if old_city and old_city.garrison_unit_id == unit.instance_id:
		old_city.garrison_unit_id = -1
	unit.is_garrisoned = false
	unit.is_fortified = false
	unit.fortify_turns = 0
	unit.is_resting_heal = false

	unit.grid_pos = target_coord
	var new_tile = game_state.grid_model.get_tile(target_coord)
	if new_tile:
		new_tile.unit_id = unit.instance_id
		var is_ocean = (new_tile.biome_data.biome_type == GameEnums.BiomeType.OCEAN)
		unit.is_embarked = (is_ocean and not unit.is_naval_unit())

	game_state.unit_moved.emit(unit, old_pos, target_coord)
	game_state.update_fog_of_war(unit.faction_id)

	if unit.faction_id != GameEnums.FactionId.BARBARIANS and game_state.barbarian_camps.has(target_coord):
		game_state.barbarian_camps.erase(target_coord)
		game_state.barbarian_camp_cleared.emit(target_coord, unit)

func _move_towards(unit: GameState.UnitInstance, target: Vector2i) -> void:
	var path = game_state.pathfinding.find_path(unit.grid_pos, target)
	if path.size() <= 1:
		return

	# Follow path steps while MP remains
	for i in range(1, path.size()):
		var step = path[i]
		var occupant = game_state.get_unit_at(step)
		if occupant != null:
			break # Blocked by unit

		var city_at_step = game_state.get_city_at(step)
		if city_at_step != null:
			break # Blocked by city; cannot walk into cities!

		var tile = game_state.grid_model.get_tile(step)
		if not tile:
			break

		# Foreign Border Wall check
		var is_foreign = (tile.owner_faction_id != -1 and tile.owner_faction_id != unit.faction_id)
		if is_foreign and (tile.has_border_wall or (tile.improvement_data and tile.improvement_data.improvement_type == GameEnums.ImprovementType.BORDER_WALL)):
			var dmg = unit.data.combat_strength
			tile.border_wall_health = maxi(0, tile.border_wall_health - dmg)
			unit.remaining_mp = 0
			unit.has_attacked = true
			if tile.border_wall_health <= 0:
				tile.has_border_wall = false
				if tile.improvement_data and tile.improvement_data.improvement_type == GameEnums.ImprovementType.BORDER_WALL:
					tile.improvement_data = null
			game_state.grid_model.tile_updated.emit(step)
			break

		# Foreign Military Encampment check
		if is_foreign and tile.improvement_data and tile.improvement_data.improvement_type == GameEnums.ImprovementType.MILITARY_ENCAMPMENT:
			var parent_city: CityData = null
			for c in game_state.cities.values():
				if c.faction_id == tile.owner_faction_id and c.encampment_pos == step:
					parent_city = c
					break
			if parent_city:
				var dmg = unit.data.combat_strength
				var res = parent_city.take_encampment_damage(dmg)
				tile.improvement_data.health = res.remaining_hp
				tile.improvement_data.fortification = res.remaining_fort
				if res.is_destroyed:
					tile.improvement_data = null
					game_state.grid_model.tile_updated.emit(step)
					game_state.fortification_razed.emit(step, unit.faction_id)
				else:
					game_state.grid_model.tile_updated.emit(step)
			unit.remaining_mp = 0
			unit.has_attacked = true
			break

		# Foreign Temporary Military Camp check
		if is_foreign and tile.improvement_data and tile.improvement_data.improvement_type == GameEnums.ImprovementType.TEMPORARY_CAMP:
			var dmg = unit.data.combat_strength
			var imp = tile.improvement_data
			if imp.fortification > 0:
				if dmg <= imp.fortification:
					imp.fortification -= dmg
					dmg = 0
				else:
					dmg -= imp.fortification
					imp.fortification = 0
			if dmg > 0:
				imp.health = maxi(0, imp.health - dmg)
			if imp.health <= 0:
				tile.improvement_data = null
				tile.owner_faction_id = -1
				game_state.grid_model.tile_updated.emit(step)
				game_state.fortification_razed.emit(step, unit.faction_id)
			else:
				game_state.grid_model.tile_updated.emit(step)
			unit.remaining_mp = 0
			unit.has_attacked = true
			break

		var cost = game_state.grid_model.get_move_cost(step)
		var reduction = game_state.tech_manager.get_highland_move_reduction(unit.faction_id)
		if tile.biome_data.biome_type == GameEnums.BiomeType.HILLS and reduction > 0:
			cost = maxi(1, cost - reduction)

		if unit.remaining_mp >= cost:
			unit.remaining_mp -= cost
			_advance_unit_into_tile(unit, step)
		else:
			break

func _find_nearest_hostile_target(from_pos: Vector2i, my_faction: int, max_range: int) -> Vector2i:
	var nearest_pos = Vector2i(-1, -1)
	var min_dist = max_range + 1

	# Check hostile cities first with a siege priority bonus (-3 virtual distance)
	for c in game_state.cities.values():
		if _is_hostile(my_faction, c.faction_id):
			var d = absi(c.grid_pos.x - from_pos.x) + absi(c.grid_pos.y - from_pos.y)
			var effective_d = maxi(1, d - 3)
			if effective_d < min_dist:
				min_dist = effective_d
				nearest_pos = c.grid_pos

	# Check hostile units
	for u in game_state.units.values():
		if _is_hostile(my_faction, u.faction_id):
			var d = absi(u.grid_pos.x - from_pos.x) + absi(u.grid_pos.y - from_pos.y)
			if d < min_dist:
				min_dist = d
				nearest_pos = u.grid_pos

	return nearest_pos

func _find_nearest_unrevealed_tile(from_pos: Vector2i, faction_id: int, max_search: int = 15) -> Vector2i:
	var best_coord = Vector2i(-1, -1)
	var min_dist = max_search + 1
	for r in range(1, max_search + 1):
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				var c = from_pos + Vector2i(dx, dy)
				if game_state.grid_model.is_valid_coord(c):
					var tile = game_state.grid_model.get_tile(c)
					if tile and tile.biome_data.is_passable and not tile.revealed_by_faction.get(faction_id, false):
						var d = absi(c.x - from_pos.x) + absi(c.y - from_pos.y)
						if d < min_dist:
							min_dist = d
							best_coord = c
		for dy in range(-r + 1, r):
			for dx in [-r, r]:
				var c = from_pos + Vector2i(dx, dy)
				if game_state.grid_model.is_valid_coord(c):
					var tile = game_state.grid_model.get_tile(c)
					if tile and tile.biome_data.is_passable and not tile.revealed_by_faction.get(faction_id, false):
						var d = absi(c.x - from_pos.x) + absi(c.y - from_pos.y)
						if d < min_dist:
							min_dist = d
							best_coord = c
		if best_coord != Vector2i(-1, -1):
			return best_coord
	return best_coord

func _is_far_from_all_cities(pos: Vector2i, min_dist: int) -> bool:
	for c in game_state.cities.values():
		var dx = absi(c.grid_pos.x - pos.x)
		var dy = absi(c.grid_pos.y - pos.y)
		if dx <= 2 and dy <= 2:
			return false
		var d = dx + dy
		if d < min_dist:
			return false
	return true

func _find_best_city_location(from_pos: Vector2i) -> Vector2i:
	var best_coord = Vector2i(-1, -1)
	var best_score = -999.0

	for y in range(maxi(0, from_pos.y - 6), mini(game_state.grid_model.height, from_pos.y + 7)):
		for x in range(maxi(0, from_pos.x - 6), mini(game_state.grid_model.width, from_pos.x + 7)):
			var c = Vector2i(x, y)
			var tile = game_state.grid_model.get_tile(c)
			if not tile or not tile.biome_data.is_passable or tile.owner_faction_id != -1:
				continue
			if not _is_far_from_all_cities(c, 4):
				continue

			var score = 10.0
			if tile.resource_data:
				score += 15.0
			for n in game_state.grid_model.get_neighbors(c, true):
				var nt = game_state.grid_model.get_tile(n)
				if nt and nt.resource_data:
					score += 8.0

			var dist = absi(from_pos.x - c.x) + absi(from_pos.y - c.y)
			score -= float(dist) * 1.5

			if score > best_score:
				best_score = score
				best_coord = c

	return best_coord

func _execute_city_bombardment(city: CityData) -> void:
	for dx in range(-city.bombard_range, city.bombard_range + 1):
		for dy in range(-city.bombard_range, city.bombard_range + 1):
			var dist = absi(dx) + absi(dy)
			if dist > 0 and dist <= city.bombard_range:
				var target_coord = city.grid_pos + Vector2i(dx, dy)
				var enemy_unit = game_state.get_unit_at(target_coord)
				if enemy_unit and _is_hostile(city.faction_id, enemy_unit.faction_id):
					var terrain_bonus = game_state.grid_model.get_defense_bonus(target_coord)
					var result = CombatEngine.resolve_ranged_attack(
						city.bombard_strength, 100, enemy_unit.data.combat_strength, enemy_unit.current_health, terrain_bonus
					)
					enemy_unit.current_health = result.remaining_defender_hp
					enemy_unit.is_fortified = false
					enemy_unit.fortify_turns = 0
					enemy_unit.is_resting_heal = false
					city.has_bombarded_this_turn = true
					game_state.city_bombarded.emit(city, enemy_unit, result.attacker_damage_dealt)
					if result.defender_died:
						game_state.remove_unit(enemy_unit.instance_id)
					return

func _execute_all_fortification_bombardments(faction_id: int) -> void:
	for y in range(game_state.grid_model.height):
		for x in range(game_state.grid_model.width):
			var pos = Vector2i(x, y)
			var tile = game_state.grid_model.get_tile(pos)
			if tile and tile.owner_faction_id == faction_id and tile.improvement_data:
				var imp = tile.improvement_data
				var can_fire = false
				if imp.improvement_type == GameEnums.ImprovementType.TEMPORARY_CAMP and not imp.has_bombarded_this_turn:
					can_fire = true
				elif imp.improvement_type == GameEnums.ImprovementType.MILITARY_ENCAMPMENT and not imp.has_bombarded_this_turn and imp.has_walls:
					can_fire = true
				if can_fire:
					_execute_fortification_bombardment(pos, imp, faction_id)

func _execute_fortification_bombardment(source_pos: Vector2i, imp: ImprovementData, faction_id: int) -> void:
	for dx in range(-imp.bombard_range, imp.bombard_range + 1):
		for dy in range(-imp.bombard_range, imp.bombard_range + 1):
			var dist = absi(dx) + absi(dy)
			if dist > 0 and dist <= imp.bombard_range:
				var target_coord = source_pos + Vector2i(dx, dy)
				var enemy_unit = game_state.get_unit_at(target_coord)
				if enemy_unit and _is_hostile(faction_id, enemy_unit.faction_id):
					var terrain_bonus = game_state.grid_model.get_defense_bonus(target_coord)
					var result = CombatEngine.resolve_ranged_attack(
						imp.bombard_strength, 100, enemy_unit.data.combat_strength, enemy_unit.current_health, terrain_bonus
					)
					enemy_unit.current_health = result.remaining_defender_hp
					enemy_unit.is_fortified = false
					enemy_unit.fortify_turns = 0
					enemy_unit.is_resting_heal = false
					imp.has_bombarded_this_turn = true
					game_state.fortification_bombarded.emit(source_pos, enemy_unit, result.attacker_damage_dealt)
					if result.defender_died:
						game_state.remove_unit(enemy_unit.instance_id)
					return

