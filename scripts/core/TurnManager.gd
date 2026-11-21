class_name TurnManager
extends RefCounted

## Central Turn Manager driving the turn-based state machine,
## movement limits, combat actions, city production queues, and domination victory checks.

signal turn_started(turn_number: int)
signal turn_phase_changed(phase: GameEnums.TurnPhase, active_faction_id: int)
signal domination_victory(winning_faction_id: int)
signal faction_defeated(defeated_faction_id: int)
signal action_feedback(text: String, is_warning: bool)

var game_state: GameState
var ai_controller: SimpleUtilityAI

var current_turn: int = 1
var current_phase: GameEnums.TurnPhase = GameEnums.TurnPhase.PLAYER_TURN
var active_faction_id: int = GameEnums.FactionId.SOLARIS_DOMINION
var is_game_over: bool = false
var winner_faction_id: int = -1

# Resource cache for unit production lookups
var unit_prototypes: Dictionary = {}

func _init(p_game_state: GameState) -> void:
	game_state = p_game_state
	ai_controller = SimpleUtilityAI.new(game_state)
	_load_prototypes()

func _load_prototypes() -> void:
	var ids = [
		"settler", "builder", "scout", "slinger", "archer", "spearman",
		"swordsman", "horseman", "catapult", "crossbowman", "knight",
		"barbarian_raider", "barbarian_horseman", "military_engineer",
		"galley", "quadrireme", "galleass",
		"musketman", "bombard", "cuirassier", "frigate", "spy"
	]
	for uid in ids:
		unit_prototypes[uid] = load("res://resources/units/%s.tres" % uid)

func start_game() -> void:
	current_turn = 1
	is_game_over = false
	winner_faction_id = -1
	_start_player_turn()

# =============================================================
# TURN STATE MACHINE
# =============================================================

func _start_player_turn() -> void:
	if is_game_over:
		return
	current_phase = GameEnums.TurnPhase.PLAYER_TURN
	active_faction_id = GameEnums.FactionId.SOLARIS_DOMINION
	_reset_faction_movement(active_faction_id)
	for c in game_state.get_faction_cities(active_faction_id):
		c.has_bombarded_this_turn = false
		if c.has_military_encampment:
			c.encampment_max_fortification = 50 if c.has_walls else 0
			if not c.has_walls:
				c.encampment_fortification = 0
			var enc_tile = game_state.grid_model.get_tile(c.encampment_pos)
			if enc_tile and enc_tile.improvement_data:
				enc_tile.improvement_data.has_bombarded_this_turn = false
				enc_tile.improvement_data.fortification = c.encampment_fortification
				enc_tile.improvement_data.max_fortification = c.encampment_max_fortification
				enc_tile.improvement_data.has_walls = c.has_walls

	for y in range(game_state.grid_model.height):
		for x in range(game_state.grid_model.width):
			var t = game_state.grid_model.get_tile(Vector2i(x, y))
			if t and t.improvement_data != null:
				if t.improvement_data.improvement_type == GameEnums.ImprovementType.TEMPORARY_CAMP:
					t.improvement_data.has_bombarded_this_turn = false

	game_state.update_fog_of_war(active_faction_id)
	process_automated_units(active_faction_id)
	turn_started.emit(current_turn)
	turn_phase_changed.emit(current_phase, active_faction_id)

	# Check for idle cities needing production orders
	var idle_cities: Array[String] = []
	for c in game_state.get_faction_cities(GameEnums.FactionId.SOLARIS_DOMINION):
		if c.current_production_id == "":
			idle_cities.append(c.city_name)
	if not idle_cities.is_empty():
		action_feedback.emit("⚠️ %s finished project and is idle! Choose new production." % ", ".join(idle_cities), true)

func end_player_turn() -> void:
	if current_phase != GameEnums.TurnPhase.PLAYER_TURN or is_game_over:
		return
	# Civ 6 rule 1: Player cannot end turn while any city is idle without production
	for c in game_state.get_faction_cities(GameEnums.FactionId.SOLARIS_DOMINION):
		if c.current_production_id == "":
			action_feedback.emit("⚠️ Cannot end turn! %s requires production orders." % c.city_name, true)
			return

	# Civ 6 rule 2: Player cannot end turn while active units have unspent moves and haven't skipped/fortified
	var unmoved = game_state.get_unmoved_units(GameEnums.FactionId.SOLARIS_DOMINION)
	if not unmoved.is_empty():
		action_feedback.emit("⚠️ Units awaiting orders! Move them, or tap 'SKIP TURN ⏳' / 'FORTIFY 🛡'.", true)
		return

	_execute_ai_factions_phase()

func _execute_ai_factions_phase() -> void:
	current_phase = GameEnums.TurnPhase.AI_FACTIONS_TURN

	var rival_factions: Array[int] = []
	for fid in game_state.factions:
		if fid != GameEnums.FactionId.SOLARIS_DOMINION and fid != GameEnums.FactionId.BARBARIANS:
			rival_factions.append(fid)

	for fid in rival_factions:
		if is_faction_alive(fid):
			active_faction_id = fid
			turn_phase_changed.emit(current_phase, fid)
			_reset_faction_movement(fid)
			ai_controller.execute_faction_turn(fid)
			check_victory_conditions()
			if is_game_over:
				return

	_execute_barbarian_phase()

func _execute_barbarian_phase() -> void:
	current_phase = GameEnums.TurnPhase.BARBARIAN_TURN
	active_faction_id = GameEnums.FactionId.BARBARIANS
	turn_phase_changed.emit(current_phase, active_faction_id)

	_reset_faction_movement(active_faction_id)
	ai_controller.execute_faction_turn(active_faction_id)
	check_victory_conditions()

	if not is_game_over:
		_execute_turn_resolution()

func _execute_turn_resolution() -> void:
	current_phase = GameEnums.TurnPhase.TURN_RESOLUTION
	turn_phase_changed.emit(current_phase, -1)

	# 1. Resolve City Production, Growth, & Defenses
	for city in game_state.cities.values():
		# Calculate balanced city yields based on population and worked tiles
		var yields = game_state.calculate_city_yields(city)
		var food_yield = yields["food"]
		var prod_yield = yields["production"]
		var science_yield = yields["science"]

		# Growth
		city.add_food(food_yield)

		# Production
		var completed_item = city.add_production(prod_yield, func(item_id: String) -> int:
			match item_id:
				"expand_border": return 25
				"walls": return 40
				"market": return 50
				"aqueduct": return 55
				"castle": return 75
				"encampment": return 45
				"science_camp": return 45
				"neighborhood": return 55
				"harbor": return 50
				"spy": return 75
				"harvest_project": return 30
				"commercial_project": return 30
				"festival_project": return 40
			var proto: UnitData = unit_prototypes.get(item_id, null)
			return proto.production_cost if proto else 30
		)

		if completed_item != "":
			if completed_item == "expand_border":
				var claimed = game_state.expand_city_borders(city, 3)
				if city.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
					if claimed.is_empty():
						action_feedback.emit("🏰 %s borders cannot expand further! Choose new production." % city.city_name, true)
					else:
						action_feedback.emit("🏰 %s completed border expansion (+%d tiles)! Choose new production." % [city.city_name, claimed.size()], false)
			elif completed_item == "walls":
				city.has_walls = true
				city.max_fortification += 50
				city.fortification = city.max_fortification
				if city.has_military_encampment:
					city.encampment_max_fortification = 50
					city.encampment_fortification = 50
				if city.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
					action_feedback.emit("🧱 %s finished City Walls (+50 Fortification, Encampment fortified & Bombardment active)! Choose new production." % city.city_name, false)
			elif completed_item == "encampment":
				city.has_military_encampment = true
				city.has_encampment = true
				city.encampment_health = 100
				city.encampment_max_health = 100
				if city.has_walls:
					city.encampment_max_fortification = 50
					city.encampment_fortification = 50
				else:
					city.encampment_fortification = 0
					city.encampment_max_fortification = 0
				_place_district_on_city_territory(city, "encampment")
				game_state.calculate_city_yields(city)
				if city.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
					action_feedback.emit("⚔ %s established Military Encampment (-50%% Strategic Cost & +10 Defense)! Choose new production." % city.city_name, false)
			elif completed_item == "science_camp":
				city.has_science_camp = true
				_place_district_on_city_territory(city, "science_camp")
				game_state.calculate_city_yields(city)
				if city.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
					action_feedback.emit("🔬 %s built a Science Campus (+3 🔬/turn)! Choose new production." % city.city_name, false)
			elif completed_item == "neighborhood":
				city.has_neighborhood = true
				_place_district_on_city_territory(city, "neighborhood")
				game_state.calculate_city_housing(city)
				game_state.calculate_city_yields(city)
				if city.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
					action_feedback.emit("🏘 %s established a Neighborhood District (+4 Housing 🏠)! Choose new production." % city.city_name, false)
			elif completed_item == "market":
				city.has_market = true
				_place_district_on_city_territory(city, "market")
				game_state.calculate_city_housing(city)
				game_state.calculate_city_yields(city)
				if city.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
					action_feedback.emit("💰 %s constructed a Market (+4 🪙/turn & +1 Housing)! Choose new production." % city.city_name, false)
			elif completed_item == "aqueduct":
				city.has_aqueduct = true
				city.food_stored += 10
				_place_district_on_city_territory(city, "aqueduct")
				game_state.calculate_city_housing(city)
				game_state.calculate_city_yields(city)
				if city.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
					action_feedback.emit("💧 %s built an Aqueduct (+3 🌾/turn & +3 Housing)! Choose new production." % city.city_name, false)
			elif completed_item == "castle":
				city.has_castle = true
				city.max_fortification += 50
				city.fortification = city.max_fortification
				city.bombard_strength += 10
				_place_district_on_city_territory(city, "castle")
				game_state.calculate_city_housing(city)
				game_state.calculate_city_yields(city)
				if city.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
					action_feedback.emit("🏰 %s constructed a Castle (+50 Fortification & +10 Bombard Strength)! Choose new production." % city.city_name, false)
			elif completed_item == "harbor":
				city.has_harbor = true
				_place_harbor_district(city)
				game_state.calculate_city_housing(city)
				game_state.calculate_city_yields(city)
				if city.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
					action_feedback.emit("⚓ %s constructed a Harbor District (+2 🪙, +1 ⚙, +1 🌾)! Naval units can now be built." % city.city_name, false)
			elif completed_item == "harvest_project":
				city.food_stored += 30
				city.add_food(0)
				if city.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
					action_feedback.emit("🌾 %s concluded Harvest Festival (+30 Food stored)! Growth accelerated." % city.city_name, false)
			elif completed_item == "commercial_project":
				game_state.faction_gold[city.faction_id] = game_state.faction_gold.get(city.faction_id, 0) + 40
				if city.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
					action_feedback.emit("🪙 %s concluded Commercial Investment (+40 Gold deposited into Treasury)!" % city.city_name, false)
			elif completed_item == "festival_project":
				city.food_stored += 20
				city.add_food(0)
				game_state.faction_gold[city.faction_id] = game_state.faction_gold.get(city.faction_id, 0) + 25
				if city.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
					action_feedback.emit("🎉 %s celebrated a Grand Festival (+20 Food & +25 Gold)!" % city.city_name, false)
			elif completed_item == "spy":
				if game_state.espionage_manager:
					var agent = game_state.espionage_manager.recruit_agent(city.faction_id, city.city_id)
					if city.faction_id == GameEnums.FactionId.SOLARIS_DOMINION and agent:
						action_feedback.emit("🕵️ %s trained covert agent: %s! Manage operations in the Espionage Bureau." % [city.city_name, agent.name], false)
			elif unit_prototypes.has(completed_item):
				var proto: UnitData = unit_prototypes[completed_item]
				var spawned = game_state.spawn_unit(proto, city.faction_id, city.grid_pos)
				# Deduct drafted population
				var pop_cost = game_state.UNIT_POPULATION_COSTS.get(completed_item, 0)
				if pop_cost > 0:
					city.population = maxi(1, city.population - pop_cost)
					city.food_needed = city.calculate_food_needed(city.population)
					game_state.calculate_city_yields(city)
				if city.faction_id == GameEnums.FactionId.SOLARIS_DOMINION and spawned:
					action_feedback.emit("🏛 %s trained %s (consumed %d Pop)! Choose new production." % [city.city_name, proto.unit_name, pop_cost], false)

			# If city had queued items, add_production has already popped the next order.
			# Otherwise current_production_id is empty ("") and player will choose next.
			if city.current_production_id != "" and city.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
				action_feedback.emit("📋 %s automatically began next queued order: %s!" % [city.city_name, city.current_production_id.capitalize()], false)

		# Fortification recovery
		city.regenerate_defenses()

		# Science Research Contribution
		game_state.tech_manager.add_science_yield(city.faction_id, science_yield)

		# Gold Treasury Income
		var gold_yield = yields.get("gold", 2)
		game_state.faction_gold[city.faction_id] = game_state.faction_gold.get(city.faction_id, 0) + gold_yield

	# Deduct Unit Maintenance Upkeep
	for fac_id in game_state.factions:
		if fac_id == GameEnums.FactionId.BARBARIANS:
			continue
		var fac_units = game_state.get_faction_units(fac_id)
		var upkeep_total = 0
		for u in fac_units:
			upkeep_total += game_state.UNIT_MAINTENANCE_COSTS.get(u.data.id, 0)
		var cur_gold = game_state.faction_gold.get(fac_id, 0)
		game_state.faction_gold[fac_id] = maxi(0, cur_gold - upkeep_total)

	# 2. Process Diplomatic Trade Agreements
	if game_state.diplomacy_manager:
		game_state.diplomacy_manager.process_turn_deals(game_state)

	# 2.5 Process Espionage Operations
	if game_state.espionage_manager:
		game_state.espionage_manager.process_turn()

	# 3. Barbarian Encampment Raider Spawning
	game_state.barbarian_spawn_turn += 1
	if game_state.barbarian_spawn_turn >= 6:
		game_state.barbarian_spawn_turn = 0
		for camp_pos in game_state.barbarian_camps:
			if game_state.get_unit_at(camp_pos) == null:
				var proto_raider: UnitData = unit_prototypes.get("barbarian_raider", null)
				if proto_raider:
					game_state.spawn_unit(proto_raider, GameEnums.FactionId.BARBARIANS, camp_pos)

	# 4. Check Domination Victory
	check_victory_conditions()

	if not is_game_over:
		current_turn += 1
		_start_player_turn()

func _reset_faction_movement(faction_id: int) -> void:
	for unit in game_state.get_faction_units(faction_id):
		unit.reset_turn()

# =============================================================
# PLAYER ACTION DISPATCHERS (DETERMINISTIC COMMANDS)
# =============================================================

func move_unit(unit_id: int, target_coord: Vector2i) -> bool:
	if current_phase != GameEnums.TurnPhase.PLAYER_TURN or is_game_over:
		action_feedback.emit("Wait for your turn!", true)
		return false

	var unit = game_state.units.get(unit_id, null)
	if not unit or unit.faction_id != GameEnums.FactionId.SOLARIS_DOMINION:
		action_feedback.emit("Invalid unit selected.", true)
		return false

	if unit.remaining_mp <= 0:
		action_feedback.emit("Unit has no Movement Points (MP) remaining this turn.", true)
		return false

	var target_tile = game_state.grid_model.get_tile(target_coord)
	if target_tile:
		var is_foreign = (target_tile.owner_faction_id != -1 and target_tile.owner_faction_id != unit.faction_id)
		if is_foreign and (target_tile.has_border_wall or (target_tile.improvement_data and target_tile.improvement_data.improvement_type == GameEnums.ImprovementType.BORDER_WALL)):
			return attack_border_wall(unit_id, target_coord)
		if is_foreign and target_tile.improvement_data and target_tile.improvement_data.improvement_type == GameEnums.ImprovementType.MILITARY_ENCAMPMENT:
			return attack_encampment(unit_id, target_coord)
		if is_foreign and target_tile.improvement_data and target_tile.improvement_data.improvement_type == GameEnums.ImprovementType.TEMPORARY_CAMP:
			return attack_temporary_camp(unit_id, target_coord)

	var enemy_city = game_state.get_city_at(target_coord)
	if enemy_city != null and enemy_city.faction_id != unit.faction_id:
		return attack_target(unit_id, target_coord)

	var occupant = game_state.get_unit_at(target_coord)
	if occupant != null:
		if occupant.faction_id != unit.faction_id:
			# Target is enemy: redirect to attack!
			return attack_target(unit_id, target_coord)
		else:
			action_feedback.emit("Tile already occupied by friendly unit.", true)
			return false

	var impassable_coords: Array[Vector2i] = []
	for y in range(game_state.grid_model.height):
		for x in range(game_state.grid_model.width):
			var c = Vector2i(x, y)
			var t = game_state.grid_model.get_tile(c)
			if t:
				var is_for = (t.owner_faction_id != -1 and t.owner_faction_id != unit.faction_id)
				if is_for and (t.has_border_wall or (t.improvement_data and t.improvement_data.improvement_type == GameEnums.ImprovementType.BORDER_WALL)):
					impassable_coords.append(c)
				elif is_for and t.improvement_data and (t.improvement_data.improvement_type == GameEnums.ImprovementType.MILITARY_ENCAMPMENT or t.improvement_data.improvement_type == GameEnums.ImprovementType.TEMPORARY_CAMP):
					impassable_coords.append(c)

	var reduction = game_state.tech_manager.get_highland_move_reduction(unit.faction_id)
	var is_naval = unit.is_naval_unit()
	var can_embark = game_state.tech_manager.can_faction_embark(unit.faction_id) if (game_state.tech_manager and game_state.tech_manager.has_method("can_faction_embark")) else false
	var reachable = game_state.pathfinding.get_reachable_tiles(unit.grid_pos, unit.remaining_mp, reduction, impassable_coords, is_naval, can_embark)

	if not reachable.has(target_coord):
		action_feedback.emit("Destination tile is beyond current MP reach.", true)
		return false

	var old_pos = unit.grid_pos
	var old_tile = game_state.grid_model.get_tile(old_pos)
	if old_tile and old_tile.unit_id == unit.instance_id:
		old_tile.unit_id = -1
	var old_city = game_state.get_city_at(old_pos)
	if old_city and old_city.garrison_unit_id == unit.instance_id:
		old_city.garrison_unit_id = -1
	unit.is_garrisoned = false

	unit.remaining_mp = reachable[target_coord]
	unit.grid_pos = target_coord
	unit.is_fortified = false
	unit.fortify_turns = 0
	unit.is_resting_heal = false

	var new_tile = game_state.grid_model.get_tile(target_coord)
	if new_tile:
		new_tile.unit_id = unit.instance_id
		var is_ocean = (new_tile.biome_data.biome_type == GameEnums.BiomeType.OCEAN)
		unit.is_embarked = (is_ocean and not is_naval)

	game_state.unit_moved.emit(unit, old_pos, target_coord)
	game_state.update_fog_of_war(unit.faction_id)

	if game_state.barbarian_camps.has(target_coord):
		_clear_barbarian_camp(unit, target_coord)
	return true

func attack_target(unit_id: int, target_coord: Vector2i) -> bool:
	if current_phase != GameEnums.TurnPhase.PLAYER_TURN or is_game_over:
		return false

	var unit = game_state.units.get(unit_id, null)
	if not unit or unit.faction_id != GameEnums.FactionId.SOLARIS_DOMINION:
		return false

	if unit.remaining_mp <= 0 or unit.has_attacked:
		action_feedback.emit("Unit has already attacked or exhausted MP.", true)
		return false

	if unit.data.get("unit_class") == GameEnums.UnitClass.CIVILIAN:
		action_feedback.emit("Civilian units cannot initiate combat!", true)
		return false

	var cur_tile = game_state.grid_model.get_tile(unit.grid_pos)
	var is_on_water = (cur_tile and cur_tile.biome_data.biome_type == GameEnums.BiomeType.OCEAN)
	var is_naval_u = unit.is_naval_unit()
	if (unit.is_embarked or is_on_water) and not is_naval_u:
		action_feedback.emit("Embarked land units cannot attack while in water!", true)
		return false

	var dist = absi(unit.grid_pos.x - target_coord.x) + absi(unit.grid_pos.y - target_coord.y)
	var max_range = unit.data.attack_range

	if dist > max_range:
		action_feedback.emit("Target is outside weapon attack range!", true)
		return false

	var target_tile = game_state.grid_model.get_tile(target_coord)
	if target_tile:
		var is_foreign = (target_tile.owner_faction_id != -1 and target_tile.owner_faction_id != unit.faction_id)
		if is_foreign and (target_tile.has_border_wall or (target_tile.improvement_data and target_tile.improvement_data.improvement_type == GameEnums.ImprovementType.BORDER_WALL)):
			return attack_border_wall(unit_id, target_coord)
		if is_foreign and target_tile.improvement_data and target_tile.improvement_data.improvement_type == GameEnums.ImprovementType.MILITARY_ENCAMPMENT:
			return attack_encampment(unit_id, target_coord)
		if is_foreign and target_tile.improvement_data and target_tile.improvement_data.improvement_type == GameEnums.ImprovementType.TEMPORARY_CAMP:
			return attack_temporary_camp(unit_id, target_coord)

	var enemy_city = game_state.get_city_at(target_coord)
	var enemy_unit = game_state.get_unit_at(target_coord)

	# Civ 6 rule: City absorbs all attacks; garrisoned unit cannot be hit directly!
	if enemy_city and enemy_city.faction_id != unit.faction_id:
		_resolve_player_city_siege(unit, enemy_city)
		check_victory_conditions()
		return true
	elif enemy_unit and enemy_unit.faction_id != unit.faction_id:
		_resolve_player_unit_combat(unit, enemy_unit)
		check_victory_conditions()
		return true

	action_feedback.emit("No valid hostile target at this tile.", true)
	return false

func _resolve_player_unit_combat(attacker: GameState.UnitInstance, defender: GameState.UnitInstance) -> void:
	if game_state.diplomacy_manager and defender.faction_id != GameEnums.FactionId.BARBARIANS:
		if not game_state.diplomacy_manager.is_at_war(attacker.faction_id, defender.faction_id):
			game_state.diplomacy_manager.declare_war(attacker.faction_id, defender.faction_id)
			action_feedback.emit("⚔ Declared WAR on %s by attacking their unit!" % game_state.faction_names.get(defender.faction_id, "Empire"), true)

	var terrain_bonus = game_state.grid_model.get_defense_bonus(defender.grid_pos)
	var def_tile = game_state.grid_model.get_tile(defender.grid_pos)
	if def_tile and def_tile.improvement_data and def_tile.improvement_data.improvement_type == GameEnums.ImprovementType.TEMPORARY_CAMP:
		terrain_bonus += 40
	if defender.is_fortified:
		terrain_bonus += 25
	var faction_bonus = game_state.tech_manager.get_combat_attack_bonus_percent(attacker.faction_id)

	var result: CombatEngine.CombatResult
	if attacker.data.is_ranged() and (attacker.grid_pos != defender.grid_pos):
		result = CombatEngine.resolve_ranged_attack(
			attacker.data.ranged_strength,
			attacker.current_health,
			defender.data.combat_strength,
			defender.current_health,
			terrain_bonus
		)
	else:
		result = CombatEngine.resolve_unit_melee(
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
	action_feedback.emit("Engaged %s! Dealt %d dmg, took %d retal." % [defender.data.unit_name, result.attacker_damage_dealt, result.defender_damage_dealt], false)

	if result.defender_died:
		action_feedback.emit("Enemy %s eliminated!" % defender.data.unit_name, false)
		var target_coord = defender.grid_pos
		game_state.remove_unit(defender.instance_id)
		# Melee units only advance if tile is not occupied by an uncaptured city!
		if not attacker.data.is_ranged() and game_state.get_city_at(target_coord) == null:
			_advance_unit_into_tile(attacker, target_coord)

	if result.attacker_died:
		action_feedback.emit("Your %s was destroyed in battle!" % attacker.data.unit_name, true)
		game_state.remove_unit(attacker.instance_id)

func _resolve_player_city_siege(attacker: GameState.UnitInstance, city: CityData) -> void:
	if game_state.diplomacy_manager and city.faction_id != GameEnums.FactionId.BARBARIANS:
		if not game_state.diplomacy_manager.is_at_war(attacker.faction_id, city.faction_id):
			game_state.diplomacy_manager.declare_war(attacker.faction_id, city.faction_id)
			action_feedback.emit("⚔ Declared WAR on %s by sieging their city!" % game_state.faction_names.get(city.faction_id, "Empire"), true)

	var is_ranged = attacker.data.is_ranged()
	var strength = attacker.data.ranged_strength if is_ranged else attacker.data.combat_strength

	var result = CombatEngine.resolve_city_siege(strength, attacker.current_health, city, is_ranged)
	attacker.current_health = result.remaining_attacker_hp
	attacker.remaining_mp = 0
	attacker.has_attacked = true

	# Emit city_attacked so views can play attack animations and red projectiles
	game_state.city_attacked.emit(attacker, city, result)
	action_feedback.emit("Bombarded %s! Fort dmg: %d, HP dmg: %d." % [city.city_name, result.fort_damage, result.city_hp_damage], false)

	if result.city_captured:
		var target_coord = city.grid_pos
		var c_name = city.city_name
		# If an enemy garrison was stationed in the captured city, eliminate it with the city
		var garrison = game_state.get_unit_at(target_coord)
		if garrison and garrison.faction_id != attacker.faction_id:
			game_state.remove_unit(garrison.instance_id)
		game_state.raze_city(city.city_id, attacker.faction_id)
		action_feedback.emit("RAZED %s! The settlement was destroyed to ashes." % c_name, false)
		if not is_ranged:
			_advance_unit_into_tile(attacker, target_coord)
		check_victory_conditions()

	if result.attacker_died:
		action_feedback.emit("Your %s was destroyed during the city assault!" % attacker.data.unit_name, true)
		game_state.remove_unit(attacker.instance_id)

## Performs ranged defensive bombardment from a walled city against an enemy unit
func city_bombard_target(city_id: int, target_coord: Vector2i) -> bool:
	if current_phase != GameEnums.TurnPhase.PLAYER_TURN or is_game_over:
		action_feedback.emit("Wait for your turn!", true)
		return false

	var city = game_state.cities.get(city_id, null)
	if not city or city.faction_id != GameEnums.FactionId.SOLARIS_DOMINION:
		return false

	if not city.has_walls:
		action_feedback.emit("City needs City Walls to fire ranged bombardment!", true)
		return false

	if city.has_bombarded_this_turn:
		action_feedback.emit("City has already fired its defensive bombardment this turn.", true)
		return false

	var dist = absi(city.grid_pos.x - target_coord.x) + absi(city.grid_pos.y - target_coord.y)
	if dist > city.bombard_range:
		action_feedback.emit("Target is outside defensive strike range (%d tiles)!" % city.bombard_range, true)
		return false

	var enemy_unit = game_state.get_unit_at(target_coord)
	if not enemy_unit or enemy_unit.faction_id == city.faction_id:
		action_feedback.emit("No hostile unit at target tile.", true)
		return false

	var terrain_bonus = game_state.grid_model.get_defense_bonus(target_coord)
	var result = CombatEngine.resolve_ranged_attack(
		city.bombard_strength,
		100,
		enemy_unit.data.combat_strength,
		enemy_unit.current_health,
		terrain_bonus
	)

	enemy_unit.current_health = result.remaining_defender_hp
	enemy_unit.is_fortified = false
	enemy_unit.fortify_turns = 0
	enemy_unit.is_resting_heal = false
	city.has_bombarded_this_turn = true

	game_state.city_bombarded.emit(city, enemy_unit, result.attacker_damage_dealt)
	action_feedback.emit("🏹 %s Wall defenses bombarded %s for %d damage!" % [city.city_name, enemy_unit.data.unit_name, result.attacker_damage_dealt], false)

	if result.defender_died:
		action_feedback.emit("Enemy %s destroyed by city defenses!" % enemy_unit.data.unit_name, false)
		game_state.remove_unit(enemy_unit.instance_id)

	check_victory_conditions()
	return true

## Performs ranged defensive bombardment from an encampment or temporary camp against an enemy unit
func fortification_bombard_target(source_coord: Vector2i, target_coord: Vector2i) -> bool:
	if current_phase != GameEnums.TurnPhase.PLAYER_TURN or is_game_over:
		action_feedback.emit("Wait for your turn!", true)
		return false

	var tile = game_state.grid_model.get_tile(source_coord)
	if not tile or not tile.improvement_data:
		action_feedback.emit("No fortification at source tile.", true)
		return false

	var imp = tile.improvement_data
	var is_encampment = (imp.improvement_type == GameEnums.ImprovementType.MILITARY_ENCAMPMENT)
	var is_camp = (imp.improvement_type == GameEnums.ImprovementType.TEMPORARY_CAMP)
	if not is_encampment and not is_camp:
		action_feedback.emit("Only encampments and fortified camps can fire bombardment.", true)
		return false

	if tile.owner_faction_id != GameEnums.FactionId.SOLARIS_DOMINION:
		action_feedback.emit("You do not own this fortification.", true)
		return false

	# Encampment requires city walls to fire bombardment
	if is_encampment and not imp.has_walls:
		action_feedback.emit("Encampment requires parent City Walls to fire bombardment!", true)
		return false

	if imp.has_bombarded_this_turn:
		action_feedback.emit("Fortification has already fired defensive bombardment this turn.", true)
		return false

	var dist = absi(source_coord.x - target_coord.x) + absi(source_coord.y - target_coord.y)
	if dist > imp.bombard_range:
		action_feedback.emit("Target is outside defensive strike range (%d tiles)!" % imp.bombard_range, true)
		return false

	var enemy_unit = game_state.get_unit_at(target_coord)
	if not enemy_unit or enemy_unit.faction_id == tile.owner_faction_id:
		action_feedback.emit("No hostile unit at target tile.", true)
		return false

	var terrain_bonus = game_state.grid_model.get_defense_bonus(target_coord)
	var result = CombatEngine.resolve_ranged_attack(
		imp.bombard_strength,
		100,
		enemy_unit.data.combat_strength,
		enemy_unit.current_health,
		terrain_bonus
	)

	enemy_unit.current_health = result.remaining_defender_hp
	enemy_unit.is_fortified = false
	enemy_unit.fortify_turns = 0
	enemy_unit.is_resting_heal = false
	imp.has_bombarded_this_turn = true

	game_state.fortification_bombarded.emit(source_coord, enemy_unit, result.attacker_damage_dealt)
	var fort_name = "Military Encampment" if is_encampment else "Fortified Outpost"
	action_feedback.emit("🏹 %s bombarded %s for %d damage!" % [fort_name, enemy_unit.data.unit_name, result.attacker_damage_dealt], false)

	if result.defender_died:
		action_feedback.emit("Enemy %s destroyed by fortification defenses!" % enemy_unit.data.unit_name, false)
		game_state.remove_unit(enemy_unit.instance_id)

	check_victory_conditions()
	return true

func found_city_command(unit_id: int, city_name: String = "") -> bool:
	var unit = game_state.units.get(unit_id, null)
	if not unit or unit.faction_id != GameEnums.FactionId.SOLARIS_DOMINION:
		return false
	if not unit.data.can_found_city:
		action_feedback.emit("Only Settlers can found cities!", true)
		return false

	var tile = game_state.grid_model.get_tile(unit.grid_pos)
	if not tile or not tile.biome_data.is_passable or tile.city_id != -1:
		action_feedback.emit("Cannot found city on this tile!", true)
		return false

	# Check distance to other cities (must be at least 2 tiles away on all sides)
	for c in game_state.cities.values():
		var dx = absi(c.grid_pos.x - unit.grid_pos.x)
		var dy = absi(c.grid_pos.y - unit.grid_pos.y)
		if dx <= 2 and dy <= 2:
			action_feedback.emit("Too close to another city (must be at least 2 tiles away on all sides).", true)
			return false

	if city_name == "":
		city_name = "Solaris Prime" if game_state.get_faction_cities(unit.faction_id).is_empty() else "New Solaris %d" % game_state.next_city_id

	var coords = unit.grid_pos
	game_state.remove_unit(unit.instance_id)
	game_state.found_city(GameEnums.FactionId.SOLARIS_DOMINION, coords, city_name)
	action_feedback.emit("Founded new city: %s!" % city_name, false)
	return true

func build_improvement_command(unit_id: int, improvement_type: GameEnums.ImprovementType) -> bool:
	var unit = game_state.units.get(unit_id, null)
	if not unit or not unit.data.can_build_improvements:
		action_feedback.emit("Only Builders can construct improvements!", true)
		return false

	if unit.build_charges <= 0:
		action_feedback.emit("Builder has exhausted all 3 build charges.", true)
		return false

	if unit.remaining_mp <= 0:
		action_feedback.emit("No MP left to build improvement.", true)
		return false

	var tile = game_state.grid_model.get_tile(unit.grid_pos)
	if not tile or tile.improvement_data != null:
		action_feedback.emit("Tile already improved or invalid.", true)
		return false

	# Must be inside friendly city borders!
	if tile.owner_faction_id != unit.faction_id:
		action_feedback.emit("Cannot build here! Must be inside your city borders. Commit your city to EXPAND BORDER.", true)
		return false

	# Validate improvement compatibility with tile resource
	if improvement_type == GameEnums.ImprovementType.FARM:
		if tile.resource_data != null:
			if tile.resource_data.id != "rice":
				action_feedback.emit("Cannot build a Farm on %s! Use the appropriate improvement." % tile.resource_data.display_name, true)
				return false
			elif not game_state.tech_manager.is_tech_researched(unit.faction_id, "agriculture"):
				action_feedback.emit("Improving Rice requires Agriculture technology!", true)
				return false
		# Bare grass/plains (no resource) can build a basic farm freely without needing agriculture!

	elif improvement_type == GameEnums.ImprovementType.PASTURE:
		if tile.resource_data == null or tile.resource_data.id != "horses":
			action_feedback.emit("Pastures can only be built on Horses!", true)
			return false
		if not game_state.tech_manager.is_tech_researched(unit.faction_id, "horse_riding"):
			action_feedback.emit("Building Pastures requires Horse Riding technology!", true)
			return false

	elif tile.resource_data != null:
		var req_tech = tile.resource_data.required_tech
		if req_tech != "" and not game_state.tech_manager.is_tech_researched(unit.faction_id, req_tech):
			var tech_title = req_tech.capitalize()
			var tech_obj = game_state.tech_manager.all_techs.get(req_tech, null)
			if tech_obj: tech_title = tech_obj.title
			action_feedback.emit("Cannot improve %s: requires %s technology!" % [tile.resource_data.display_name, tech_title], true)
			return false

	var impr_res: ImprovementData
	match improvement_type:
		GameEnums.ImprovementType.FARM:
			impr_res = load("res://resources/improvements/farm.tres")
		GameEnums.ImprovementType.MINE:
			if not game_state.tech_manager.is_tech_researched(unit.faction_id, "mining"):
				action_feedback.emit("Building Mines requires Mining technology!", true)
				return false
			impr_res = load("res://resources/improvements/mine.tres")
		GameEnums.ImprovementType.PASTURE:
			impr_res = load("res://resources/improvements/pasture.tres")
		GameEnums.ImprovementType.MILITARY_ENCAMPMENT:
			if not game_state.tech_manager.is_improvement_unlocked(unit.faction_id, "encampment"):
				action_feedback.emit("Requires Bronze Working technology!", true)
				return false
			impr_res = load("res://resources/improvements/encampment.tres")
		GameEnums.ImprovementType.SCIENCE_CAMP:
			if not game_state.tech_manager.is_improvement_unlocked(unit.faction_id, "science_camp"):
				action_feedback.emit("Requires Writing technology!", true)
				return false
			impr_res = load("res://resources/improvements/science_camp.tres")

	if impr_res:
		tile.improvement_data = impr_res
		unit.build_charges -= 1
		unit.remaining_mp = 0
		if unit.build_charges <= 0:
			action_feedback.emit("Constructed %s! Builder completed all 3 charges and retired." % impr_res.improvement_name, false)
			game_state.remove_unit(unit.instance_id)
		else:
			action_feedback.emit("Constructed %s! (%d of 3 charges remaining)" % [impr_res.improvement_name, unit.build_charges], false)
		return true
	return false

func _advance_unit_into_tile(unit: GameState.UnitInstance, target_coord: Vector2i) -> void:
	var old_pos = unit.grid_pos
	var old_tile = game_state.grid_model.get_tile(old_pos)
	if old_tile and old_tile.unit_id == unit.instance_id:
		old_tile.unit_id = -1

	unit.grid_pos = target_coord
	var new_tile = game_state.grid_model.get_tile(target_coord)
	if new_tile:
		new_tile.unit_id = unit.instance_id

	game_state.unit_moved.emit(unit, old_pos, target_coord)
	game_state.update_fog_of_war(unit.faction_id)

	if game_state.barbarian_camps.has(target_coord):
		_clear_barbarian_camp(unit, target_coord)

func _clear_barbarian_camp(unit: GameState.UnitInstance, camp_pos: Vector2i) -> void:
	game_state.barbarian_camps.erase(camp_pos)
	game_state.faction_gold[unit.faction_id] = game_state.faction_gold.get(unit.faction_id, 0) + 30
	if unit.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
		action_feedback.emit("⛺ Barbarian Encampment cleared! Plundered +30 🪙!", false)
	game_state.barbarian_camp_cleared.emit(camp_pos, unit)

func upgrade_unit_command(unit_id: int) -> bool:
	if current_phase != GameEnums.TurnPhase.PLAYER_TURN or is_game_over:
		action_feedback.emit("Wait for your turn!", true)
		return false

	var unit = game_state.units.get(unit_id, null)
	if not unit or unit.faction_id != GameEnums.FactionId.SOLARIS_DOMINION:
		action_feedback.emit("Invalid unit selected.", true)
		return false

	if unit.data.upgrade_unit_id == "":
		action_feedback.emit("This unit cannot be upgraded.", true)
		return false

	if unit.remaining_mp <= 0:
		action_feedback.emit("Unit has no Movement Points remaining to upgrade this turn.", true)
		return false

	var target_id = unit.data.upgrade_unit_id
	var cost = unit.data.upgrade_cost
	var proto: UnitData = unit_prototypes.get(target_id, null)
	if not proto:
		action_feedback.emit("Upgrade unit definition not found.", true)
		return false

	# 1. Tech check
	if proto.tech_prerequisite != "" and not game_state.tech_manager.is_tech_researched(unit.faction_id, proto.tech_prerequisite):
		var tech_title = proto.tech_prerequisite.capitalize()
		var tech_obj = game_state.tech_manager.all_techs.get(proto.tech_prerequisite, null)
		if tech_obj: tech_title = tech_obj.title
		action_feedback.emit("Upgrade requires %s technology!" % tech_title, true)
		return false

	# 2. Strategic resource check
	if proto.strategic_prerequisite != "":
		var strat_res = game_state.get_faction_strategic_resources(unit.faction_id)
		if strat_res.get(proto.strategic_prerequisite, 0) < 1:
			action_feedback.emit("Upgrade requires %s strategic resource!" % proto.strategic_prerequisite.capitalize(), true)
			return false

	# 3. Gold cost check
	var gold = game_state.faction_gold.get(unit.faction_id, 0)
	if gold < cost:
		action_feedback.emit("Insufficient gold! Requires %d 🪙 (Treasury: %d 🪙)." % [cost, gold], true)
		return false

	# Perform upgrade
	game_state.faction_gold[unit.faction_id] -= cost
	var old_name = unit.data.unit_name
	game_state.upgrade_unit(unit_id, proto)
	action_feedback.emit("⭐ Upgraded %s to %s for %d 🪙!" % [old_name, proto.unit_name, cost], false)
	return true

func _place_district_on_city_territory(city: CityData, district_id: String) -> void:
	var imp_path = "res://resources/improvements/%s.tres" % district_id
	if not ResourceLoader.exists(imp_path):
		return
	var imp_data = load(imp_path) as ImprovementData
	if not imp_data:
		return

	var target_tile_coord = city.planned_district_tiles.get(district_id, Vector2i(-1, -1))
	var is_valid_planned = false
	if target_tile_coord != Vector2i(-1, -1) and city.territory_tiles.has(target_tile_coord) and target_tile_coord != city.grid_pos:
		var tile = game_state.grid_model.get_tile(target_tile_coord)
		if tile and tile.biome_data.is_passable:
			is_valid_planned = true

	if not is_valid_planned:
		target_tile_coord = Vector2i(-1, -1)
		for coord in city.territory_tiles:
			if coord == city.grid_pos:
				continue
			var tile = game_state.grid_model.get_tile(coord)
			if tile and tile.biome_data.is_passable and tile.improvement_data == null:
				target_tile_coord = coord
				break

	if target_tile_coord == Vector2i(-1, -1):
		for coord in city.territory_tiles:
			if coord != city.grid_pos:
				target_tile_coord = coord
				break

	if target_tile_coord != Vector2i(-1, -1):
		var tile = game_state.grid_model.get_tile(target_tile_coord)
		if tile:
			tile.improvement_data = imp_data.duplicate()
			if district_id == "encampment":
				city.encampment_pos = target_tile_coord
			elif district_id == "science_camp":
				city.science_camp_pos = target_tile_coord
			elif district_id == "neighborhood":
				city.neighborhood_pos = target_tile_coord
			game_state.grid_model.tile_updated.emit(target_tile_coord)

func _place_harbor_district(city: CityData) -> void:
	var imp_path = "res://resources/improvements/harbor.tres"
	if not ResourceLoader.exists(imp_path):
		return
	var imp_data = load(imp_path) as ImprovementData
	if not imp_data:
		return

	var target_coord = city.planned_district_tiles.get("harbor", Vector2i(-1, -1))
	if target_coord != Vector2i(-1, -1):
		var t = game_state.grid_model.get_tile(target_coord)
		if not t or t.biome_data.biome_type != GameEnums.BiomeType.OCEAN or not city.territory_tiles.has(target_coord):
			target_coord = Vector2i(-1, -1)

	# Look strictly in existing territory for an available ocean tile
	if target_coord == Vector2i(-1, -1):
		for coord in city.territory_tiles:
			if coord == city.grid_pos:
				continue
			var tile = game_state.grid_model.get_tile(coord)
			if tile and tile.biome_data.biome_type == GameEnums.BiomeType.OCEAN:
				if tile.improvement_data == null or tile.improvement_data.improvement_type != GameEnums.ImprovementType.HARBOR:
					target_coord = coord
					break

	if target_coord != Vector2i(-1, -1):
		var tile = game_state.grid_model.get_tile(target_coord)
		if tile:
			tile.improvement_data = imp_data.duplicate()
			city.has_harbor = true
			city.harbor_pos = target_coord
			game_state.grid_model.tile_updated.emit(target_coord)

func attack_encampment(unit_id: int, target_coord: Vector2i) -> bool:
	var unit = game_state.units.get(unit_id, null)
	var tile = game_state.grid_model.get_tile(target_coord)
	if not unit or not tile or not tile.improvement_data:
		return false

	if unit.remaining_mp <= 0 or unit.has_attacked:
		action_feedback.emit("Unit cannot attack this turn!", true)
		return false

	if unit.data.is_civilian():
		action_feedback.emit("Civilian units cannot attack encampments!", true)
		return false

	unit.remaining_mp = 0
	unit.has_attacked = true

	# Declare war if attacking foreign encampment
	if tile.owner_faction_id != -1 and tile.owner_faction_id != GameEnums.FactionId.BARBARIANS:
		if game_state.diplomacy_manager and not game_state.diplomacy_manager.is_at_war(unit.faction_id, tile.owner_faction_id):
			game_state.diplomacy_manager.declare_war(unit.faction_id, tile.owner_faction_id)
			action_feedback.emit("⚔ Declared WAR by attacking military encampment!", true)

	var damage = maxi(25, unit.data.combat_strength)
	var owning_city: CityData = null
	if tile.city_id != -1:
		owning_city = game_state.cities.get(tile.city_id, null)
	if not owning_city:
		for c in game_state.cities.values():
			if c.territory_tiles.has(target_coord) and c.faction_id == tile.owner_faction_id:
				owning_city = c
				break

	if owning_city:
		var res = owning_city.take_encampment_damage(damage)
		tile.improvement_data.health = res.remaining_hp
		tile.improvement_data.fortification = res.remaining_fort
		if res.is_destroyed:
			owning_city.has_military_encampment = false
			owning_city.has_encampment = false
			owning_city.encampment_pos = Vector2i(-1, -1)
			tile.improvement_data = null
			game_state.grid_model.tile_updated.emit(target_coord)
			game_state.fortification_razed.emit(target_coord, unit.faction_id)
			action_feedback.emit("⚔ Military Encampment BREACHED and destroyed! Area is now clear.", false)
		else:
			game_state.grid_model.tile_updated.emit(target_coord)
			action_feedback.emit("⚔ Damaged Encampment! Fort: %d, HP: %d/100 remaining." % [res.remaining_fort, res.remaining_hp], false)
	else:
		var imp = tile.improvement_data
		if imp.fortification > 0:
			if damage <= imp.fortification:
				imp.fortification -= damage
				damage = 0
			else:
				damage -= imp.fortification
				imp.fortification = 0
		if damage > 0:
			imp.health = maxi(0, imp.health - damage)
		if imp.health <= 0:
			tile.improvement_data = null
			game_state.grid_model.tile_updated.emit(target_coord)
			game_state.fortification_razed.emit(target_coord, unit.faction_id)
			action_feedback.emit("⚔ Encampment destroyed!", false)
		else:
			game_state.grid_model.tile_updated.emit(target_coord)
			action_feedback.emit("⚔ Damaged Encampment! Fort: %d, HP: %d/100 remaining." % [imp.fortification, imp.health], false)

	if not unit.is_ranged_unit():
		var retal_dmg = 12
		unit.current_health = maxi(1, unit.current_health - retal_dmg)
		if unit.current_health <= 0:
			game_state.remove_unit(unit.instance_id)

	return true

func attack_temporary_camp(unit_id: int, target_coord: Vector2i) -> bool:
	var unit = game_state.units.get(unit_id, null)
	var tile = game_state.grid_model.get_tile(target_coord)
	if not unit or not tile or not tile.improvement_data:
		return false

	if unit.remaining_mp <= 0 or unit.has_attacked:
		action_feedback.emit("Unit cannot attack this turn!", true)
		return false

	if unit.data.is_civilian():
		action_feedback.emit("Civilian units cannot attack camps!", true)
		return false

	unit.remaining_mp = 0
	unit.has_attacked = true

	# Declare war if attacking foreign camp
	if tile.owner_faction_id != -1 and tile.owner_faction_id != GameEnums.FactionId.BARBARIANS:
		if game_state.diplomacy_manager and not game_state.diplomacy_manager.is_at_war(unit.faction_id, tile.owner_faction_id):
			game_state.diplomacy_manager.declare_war(unit.faction_id, tile.owner_faction_id)
			action_feedback.emit("⚔ Declared WAR by attacking fortified camp!", true)

	var damage = maxi(20, unit.data.combat_strength)
	var imp = tile.improvement_data
	if imp.fortification > 0:
		if damage <= imp.fortification:
			imp.fortification -= damage
			damage = 0
		else:
			damage -= imp.fortification
			imp.fortification = 0

	if damage > 0:
		imp.health = maxi(0, imp.health - damage)

	if imp.health <= 0:
		tile.improvement_data = null
		tile.owner_faction_id = -1
		game_state.grid_model.tile_updated.emit(target_coord)
		game_state.fortification_razed.emit(target_coord, unit.faction_id)
		action_feedback.emit("⛺ Fortified Camp RAZED and destroyed! Tile is now clear.", false)
	else:
		game_state.grid_model.tile_updated.emit(target_coord)
		action_feedback.emit("⚔ Damaged Fortified Camp! Fort: %d, HP: %d/100 remaining." % [imp.fortification, imp.health], false)

	if not unit.is_ranged_unit():
		var retal_dmg = 10
		unit.current_health = maxi(1, unit.current_health - retal_dmg)
		if unit.current_health <= 0:
			game_state.remove_unit(unit.instance_id)

	return true

func attack_border_wall(unit_id: int, target_coord: Vector2i) -> bool:
	var unit = game_state.units.get(unit_id, null)
	var tile = game_state.grid_model.get_tile(target_coord)
	if not unit or not tile:
		return false
	var has_wall = tile.has_border_wall or (tile.improvement_data and tile.improvement_data.improvement_type == GameEnums.ImprovementType.BORDER_WALL)
	if not has_wall:
		return false

	if unit.remaining_mp <= 0 or unit.has_attacked:
		action_feedback.emit("Unit cannot attack this turn!", true)
		return false

	if unit.data.is_civilian():
		action_feedback.emit("Civilian units cannot attack border walls!", true)
		return false

	unit.remaining_mp = 0
	unit.has_attacked = true

	# Declare war if attacking foreign wall
	if tile.owner_faction_id != -1 and tile.owner_faction_id != GameEnums.FactionId.BARBARIANS:
		if game_state.diplomacy_manager and not game_state.diplomacy_manager.is_at_war(unit.faction_id, tile.owner_faction_id):
			game_state.diplomacy_manager.declare_war(unit.faction_id, tile.owner_faction_id)
			action_feedback.emit("⚔ Declared WAR by attacking border fortification!", true)

	var damage = maxi(25, unit.data.combat_strength)
	if tile.has_border_wall:
		tile.border_wall_health -= damage
		if tile.border_wall_health <= 0:
			tile.has_border_wall = false
			game_state.grid_model.tile_updated.emit(target_coord)
			action_feedback.emit("⚔ Border Wall BREACHED and demolished! Tile is now accessible.", false)
		else:
			action_feedback.emit("⚔ Damaged Border Wall (%d/50 HP remaining)!" % tile.border_wall_health, false)
	elif tile.improvement_data:
		if not "health" in tile.improvement_data:
			tile.improvement_data.health = 50
		tile.improvement_data.health -= damage
		if tile.improvement_data.health <= 0:
			tile.improvement_data = null
			game_state.grid_model.tile_updated.emit(target_coord)
			action_feedback.emit("⚔ Border Wall BREACHED and demolished! Tile is now accessible.", false)
		else:
			action_feedback.emit("⚔ Damaged Border Wall (%d/50 HP remaining)!" % tile.improvement_data.health, false)

	return true

func pillage_tile(unit_id: int) -> Dictionary:
	if current_phase != GameEnums.TurnPhase.PLAYER_TURN or is_game_over:
		return { "success": false, "error": "Not your turn." }
	var unit = game_state.units.get(unit_id, null)
	if not unit or unit.faction_id != GameEnums.FactionId.SOLARIS_DOMINION:
		return { "success": false, "error": "Invalid unit." }
	if unit.remaining_mp <= 0:
		return { "success": false, "error": "No MP remaining." }

	var tile = game_state.grid_model.get_tile(unit.grid_pos)
	if not tile or tile.improvement_data == null:
		return { "success": false, "error": "No improvement to pillage." }

	if tile.owner_faction_id == unit.faction_id:
		return { "success": false, "error": "Cannot pillage your own improvements!" }

	# Declare war if pillaging a non-barbarian foreign tile
	if tile.owner_faction_id != -1 and tile.owner_faction_id != GameEnums.FactionId.BARBARIANS:
		if game_state.diplomacy_manager and not game_state.diplomacy_manager.is_at_war(unit.faction_id, tile.owner_faction_id):
			game_state.diplomacy_manager.declare_war(unit.faction_id, tile.owner_faction_id)
			action_feedback.emit("⚔ Declared WAR by pillaging foreign lands!", true)

	var imp_name = tile.improvement_data.improvement_name
	tile.improvement_data = null
	game_state.grid_model.tile_updated.emit(unit.grid_pos)

	# Plunder Gold (+30) and Heal Unit (+35 HP)
	var gold_gain = 30
	var heal_gain = 35
	game_state.faction_gold[unit.faction_id] = game_state.faction_gold.get(unit.faction_id, 0) + gold_gain
	var old_hp = unit.current_health
	unit.current_health = mini(unit.data.max_health, unit.current_health + heal_gain)
	var actual_healed = unit.current_health - old_hp
	unit.remaining_mp = 0

	action_feedback.emit("💥 Pillaged %s! Plundered +%d 🪙 and restored +%d HP (%d/%d HP)!" % [
		imp_name, gold_gain, actual_healed, unit.current_health, unit.data.max_health
	], false)

	return { "success": true, "gold": gold_gain, "healed": actual_healed }

func heal_unit(unit_id: int) -> Dictionary:
	if current_phase != GameEnums.TurnPhase.PLAYER_TURN or is_game_over:
		return { "success": false, "error": "Not your turn." }
	var unit = game_state.units.get(unit_id, null)
	if not unit or unit.faction_id != GameEnums.FactionId.SOLARIS_DOMINION:
		return { "success": false, "error": "Invalid unit." }
	if unit.current_health >= unit.data.max_health:
		action_feedback.emit("Unit is already at full health (100 HP)!", true)
		return { "success": false, "error": "Already at full health." }

	var tile = game_state.grid_model.get_tile(unit.grid_pos)
	var heal_amount = 15
	if game_state.get_city_at(unit.grid_pos) != null:
		heal_amount = 25 # Garrison / City Hospital
	elif tile and tile.owner_faction_id == unit.faction_id:
		heal_amount = 20 # Friendly territory supply lines
	else:
		heal_amount = 10 # Foreign / Neutral field triage

	unit.current_health = mini(unit.data.max_health, unit.current_health + heal_amount)
	unit.is_resting_heal = true
	unit.is_turn_skipped = true
	unit.remaining_mp = 0

	action_feedback.emit("🩹 %s rested & treated wounds: +%d HP (%d/%d HP)!" % [
		unit.data.unit_name, heal_amount, unit.current_health, unit.data.max_health
	], false)

	return { "success": true, "healed": heal_amount }

func skip_unit_turn(unit_id: int) -> Dictionary:
	var unit = game_state.units.get(unit_id, null)
	if not unit:
		return { "success": false }
	unit.is_turn_skipped = true
	unit.remaining_mp = 0
	action_feedback.emit("⏳ %s orders skipped for this turn." % unit.data.unit_name, false)
	return { "success": true }

func fortify_unit(unit_id: int) -> Dictionary:
	var unit = game_state.units.get(unit_id, null)
	if not unit:
		return { "success": false }
	unit.is_fortified = true
	unit.is_turn_skipped = true
	unit.remaining_mp = 0
	action_feedback.emit("🛡 %s fortified (+25%% Defense Bonus)!" % unit.data.unit_name, false)
	return { "success": true }

func get_garrisonable_city_for_unit(unit_id: int) -> CityData:
	var unit = game_state.units.get(unit_id, null)
	if not unit or unit.data.is_civilian():
		return null
	# Check if standing directly on a friendly city
	var city = game_state.get_city_at(unit.grid_pos)
	if city and city.faction_id == unit.faction_id:
		if city.garrison_unit_id == -1 or city.garrison_unit_id == unit.instance_id:
			return city
	# Check adjacent friendly cities (if city tile is unoccupied or occupied by this unit)
	for dir in game_state.grid_model.get_neighbors(unit.grid_pos):
		var adj_city = game_state.get_city_at(dir)
		if adj_city and adj_city.faction_id == unit.faction_id:
			if adj_city.garrison_unit_id == -1:
				var occ = game_state.get_unit_at(adj_city.grid_pos)
				if occ == null or occ.instance_id == unit.instance_id:
					return adj_city
	return null

func garrison_unit(unit_id: int) -> Dictionary:
	var unit = game_state.units.get(unit_id, null)
	if not unit:
		return { "success": false, "error": "Unit not found." }
	if unit.data.get("unit_class") == GameEnums.UnitClass.CIVILIAN:
		action_feedback.emit("Civilian units cannot garrison cities!", true)
		return { "success": false, "error": "Civilian units cannot garrison." }

	var city = get_garrisonable_city_for_unit(unit_id)
	if not city:
		action_feedback.emit("No friendly city nearby with available garrison slot!", true)
		return { "success": false, "error": "No friendly city nearby." }

	# If adjacent, move into the city tile
	if unit.grid_pos != city.grid_pos:
		var old_pos = unit.grid_pos
		var old_tile = game_state.grid_model.get_tile(old_pos)
		if old_tile and old_tile.unit_id == unit.instance_id:
			old_tile.unit_id = -1
		unit.grid_pos = city.grid_pos
		var new_tile = game_state.grid_model.get_tile(city.grid_pos)
		if new_tile:
			new_tile.unit_id = unit.instance_id
		game_state.unit_moved.emit(unit, old_pos, city.grid_pos)
		game_state.update_fog_of_war(unit.faction_id)

	city.garrison_unit_id = unit.instance_id
	unit.is_garrisoned = true
	unit.is_fortified = true
	unit.is_turn_skipped = true
	unit.remaining_mp = 0
	game_state.unit_moved.emit(unit, unit.grid_pos, city.grid_pos)
	action_feedback.emit("🛡️ %s garrisoned in %s (+10 City Defense, Fortified)!" % [unit.data.unit_name, city.city_name], false)
	return { "success": true, "city_id": city.city_id }

func build_border_wall(unit_id: int) -> Dictionary:
	var unit = game_state.units.get(unit_id, null)
	if not unit or not (unit.data.can_build_military_structures or unit.data.id == "military_engineer"):
		return { "success": false, "error": "Only Military Engineers can construct Border Walls." }
	if unit.build_charges <= 0 or unit.remaining_mp <= 0:
		return { "success": false, "error": "No charges or MP remaining." }

	var tile = game_state.grid_model.get_tile(unit.grid_pos)
	if not tile or tile.owner_faction_id != unit.faction_id:
		action_feedback.emit("Border Walls must be built inside your civilization's territory!", true)
		return { "success": false, "error": "Not inside territory." }
	for c in game_state.cities.values():
		if c.grid_pos == unit.grid_pos:
			action_feedback.emit("City centers already have urban defenses!", true)
			return { "success": false, "error": "City centers already have urban defenses." }
	if tile.has_border_wall:
		action_feedback.emit("Tile already has a Border Wall!", true)
		return { "success": false, "error": "Tile already has a border wall." }
	if tile.improvement_data and tile.improvement_data.improvement_type == GameEnums.ImprovementType.MILITARY_ENCAMPMENT:
		action_feedback.emit("Military Encampments are already fortified!", true)
		return { "success": false, "error": "Military Encampment is already fortified." }

	tile.has_border_wall = true
	tile.border_wall_health = 50
	tile.border_wall_max_health = 50
	game_state.grid_model.tile_updated.emit(unit.grid_pos)

	unit.build_charges -= 1
	unit.remaining_mp = 0
	action_feedback.emit("🛡️ Constructed Border Wall (+50 Fortification)! Blocks enemy passage unless destroyed.", false)
	if unit.build_charges <= 0:
		game_state.remove_unit(unit_id)

	return { "success": true }

func build_temporary_camp(unit_id: int) -> Dictionary:
	var unit = game_state.units.get(unit_id, null)
	if not unit or not (unit.data.can_build_military_structures or unit.data.id == "military_engineer"):
		return { "success": false, "error": "Only Military Engineers can construct Fortified Camps." }
	if unit.build_charges <= 0 or unit.remaining_mp <= 0:
		return { "success": false, "error": "No charges or MP remaining." }

	var tile = game_state.grid_model.get_tile(unit.grid_pos)
	if not tile or not tile.biome_data.is_passable:
		action_feedback.emit("Cannot build camp on impassable terrain!", true)
		return { "success": false, "error": "Impassable terrain." }
	if tile.owner_faction_id != unit.faction_id and tile.owner_faction_id != -1:
		action_feedback.emit("Cannot build camp inside foreign territory!", true)
		return { "success": false, "error": "Foreign territory." }
	if tile.improvement_data != null:
		action_feedback.emit("Tile already has an improvement!", true)
		return { "success": false, "error": "Tile already improved." }

	var imp_data = load("res://resources/improvements/temporary_camp.tres") as ImprovementData
	if not imp_data:
		return { "success": false, "error": "Failed to load camp data." }

	tile.improvement_data = imp_data.duplicate()
	tile.improvement_data.health = 100
	tile.improvement_data.max_health = 100
	tile.improvement_data.fortification = 50
	tile.improvement_data.max_fortification = 50
	tile.improvement_data.has_walls = true
	tile.improvement_data.bombard_strength = 15
	tile.improvement_data.bombard_range = 2
	tile.owner_faction_id = unit.faction_id
	game_state.grid_model.tile_updated.emit(unit.grid_pos)
	game_state.update_fog_of_war(unit.faction_id)

	unit.build_charges -= 1
	unit.remaining_mp = 0
	action_feedback.emit("⛺ Constructed Fortified Camp (+40%% Defense Bonus & Outpost Protection)!", false)
	if unit.build_charges <= 0:
		game_state.remove_unit(unit_id)

	return { "success": true }

# =============================================================
# DOMINATION VICTORY CONDITION VALIDATION
# =============================================================

func is_faction_alive(faction_id: int) -> bool:
	var has_cities = not game_state.get_faction_cities(faction_id).is_empty()
	var has_units = not game_state.get_faction_units(faction_id).is_empty()
	return has_cities or has_units

func check_victory_conditions() -> void:
	if is_game_over:
		return

	# Check Player defeat
	if not is_faction_alive(GameEnums.FactionId.SOLARIS_DOMINION):
		is_game_over = true
		faction_defeated.emit(GameEnums.FactionId.SOLARIS_DOMINION)
		action_feedback.emit("DEFEAT! All your forces have been crushed.", true)
		return

	# Domination check: Only ONE civilization faction holds cities and units
	var surviving_civs: Array[int] = []
	for fid in game_state.factions:
		if fid != GameEnums.FactionId.BARBARIANS and is_faction_alive(fid):
			surviving_civs.append(fid)

	if surviving_civs.size() == 1:
		var victor = surviving_civs[0]
		is_game_over = true
		winner_faction_id = victor
		domination_victory.emit(victor)
		if victor == GameEnums.FactionId.SOLARIS_DOMINION:
			action_feedback.emit("DOMINATION VICTORY! You have conquered the known world!", false)
		else:
			action_feedback.emit("%s has achieved Domination Victory!" % game_state.faction_names[victor], true)

# =============================================================
# CIV 6 STYLE AUTOMATED EXPLORATION
# =============================================================

func has_hostile_nearby(unit: GameState.UnitInstance, radius: int = 2) -> bool:
	if not unit:
		return false
	for other_id in game_state.units:
		var other = game_state.units[other_id]
		if other.faction_id == unit.faction_id:
			continue
		var dist = absi(other.grid_pos.x - unit.grid_pos.x) + absi(other.grid_pos.y - unit.grid_pos.y)
		if dist <= radius:
			if other.faction_id == GameEnums.FactionId.BARBARIANS:
				return true
			if game_state.diplomacy_manager and game_state.diplomacy_manager.is_at_war(unit.faction_id, other.faction_id):
				return true
	return false

func set_unit_automated(unit_id: int, automated: bool) -> Dictionary:
	var unit = game_state.units.get(unit_id, null)
	if not unit:
		return { "success": false, "error": "Unit not found." }
	unit.is_automated = automated
	if automated:
		action_feedback.emit("🤖 %s automated for exploration!" % unit.data.unit_name, false)
		if has_hostile_nearby(unit, 2):
			unit.is_automated = false
			action_feedback.emit("⚠️ %s spotted hostiles nearby and stopped automation!" % unit.data.unit_name, true)
			return { "success": true, "automated": false }
		if unit.remaining_mp > 0:
			while unit.remaining_mp > 0 and unit.is_automated:
				var moved = _step_automated_unit(unit)
				if not moved:
					break
				if has_hostile_nearby(unit, 2):
					unit.is_automated = false
					action_feedback.emit("⚠️ %s spotted hostiles nearby and stopped automation!" % unit.data.unit_name, true)
					break
	else:
		action_feedback.emit("🛑 %s automation canceled." % unit.data.unit_name, false)
	return { "success": true, "automated": unit.is_automated }

func process_automated_units(faction_id: int = GameEnums.FactionId.SOLARIS_DOMINION) -> void:
	var list: Array[GameState.UnitInstance] = []
	for uid in game_state.units:
		var u = game_state.units[uid]
		if u.faction_id == faction_id and u.is_automated:
			list.append(u)

	for unit in list:
		if not game_state.units.has(unit.instance_id):
			continue
		if has_hostile_nearby(unit, 2):
			unit.is_automated = false
			action_feedback.emit("⚠️ %s spotted hostiles nearby and stopped automation!" % unit.data.unit_name, true)
			continue

		var loop_guard = 0
		while unit.remaining_mp > 0 and unit.is_automated and loop_guard < 10:
			loop_guard += 1
			var moved = _step_automated_unit(unit)
			if not moved:
				break
			if has_hostile_nearby(unit, 2):
				unit.is_automated = false
				action_feedback.emit("⚠️ %s spotted hostiles nearby and stopped automation!" % unit.data.unit_name, true)
				break

func _step_automated_unit(unit: GameState.UnitInstance) -> bool:
	if not unit or unit.remaining_mp <= 0:
		return false

	var reduction = game_state.tech_manager.get_highland_move_reduction(unit.faction_id)
	var is_naval = unit.is_naval_unit()
	var can_embark = game_state.tech_manager.can_faction_embark(unit.faction_id) if (game_state.tech_manager and game_state.tech_manager.has_method("can_faction_embark")) else false
	var reachable = game_state.pathfinding.get_reachable_tiles(unit.grid_pos, unit.remaining_mp, reduction, [], is_naval, can_embark)

	var best_coord = Vector2i(-1, -1)
	var best_score = -9999.0

	for coord in reachable.keys():
		if coord == unit.grid_pos:
			continue
		var occ = game_state.get_unit_at(coord)
		if occ != null and occ.instance_id != unit.instance_id:
			continue
		var c_at = game_state.get_city_at(coord)
		if c_at and c_at.faction_id != unit.faction_id:
			continue
		var t_at = game_state.grid_model.get_tile(coord)
		if t_at:
			var is_foreign = (t_at.owner_faction_id != -1 and t_at.owner_faction_id != unit.faction_id)
			if is_foreign and (t_at.has_border_wall or (t_at.improvement_data and t_at.improvement_data.improvement_type == GameEnums.ImprovementType.BORDER_WALL)):
				continue
			if is_foreign and t_at.improvement_data and t_at.improvement_data.improvement_type == GameEnums.ImprovementType.MILITARY_ENCAMPMENT:
				continue

		var unrevealed_adjacent = 0
		for n in game_state.grid_model.get_neighbors(coord, false):
			var nt = game_state.grid_model.get_tile(n)
			if nt and not nt.revealed_by_faction.get(unit.faction_id, false):
				unrevealed_adjacent += 1

		var score = float(unrevealed_adjacent * 10) + float(reachable[coord]) + randf_range(0.1, 0.9)
		if score > best_score:
			best_score = score
			best_coord = coord

	if best_coord != Vector2i(-1, -1) and best_coord != unit.grid_pos:
		return move_unit(unit.instance_id, best_coord)

	for coord in reachable.keys():
		if coord == unit.grid_pos:
			continue
		var occ = game_state.get_unit_at(coord)
		if occ == null:
			var c_at = game_state.get_city_at(coord)
			if not (c_at and c_at.faction_id != unit.faction_id):
				return move_unit(unit.instance_id, coord)

	unit.remaining_mp = 0
	return false
