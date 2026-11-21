@tool
extends "res://addons/godot_ai/testing/test_suite.gd"

func suite_name() -> String:
	return "districts_and_features"

func _create_test_environment() -> Dictionary:
	var grid = GridModel.new()
	grid.initialize(12, 12)
	var plains_data = load("res://resources/biomes/plains.tres") as BiomeData
	var hills_data = load("res://resources/biomes/hills.tres") as BiomeData
	var mtn_data = load("res://resources/biomes/mountains.tres") as BiomeData

	for y in range(12):
		for x in range(12):
			grid.set_tile(Vector2i(x, y), plains_data)

	# Add some hills and mountains
	grid.set_tile(Vector2i(5, 6), hills_data)
	grid.set_tile(Vector2i(6, 5), mtn_data)

	var game_state = GameState.new()
	game_state.initialize(grid)

	var turn_manager = TurnManager.new(game_state)
	var input_ctrl = PlayerInputController.new()
	input_ctrl.setup(game_state, turn_manager)

	return {
		"grid": grid,
		"game_state": game_state,
		"turn_manager": turn_manager,
		"input_ctrl": input_ctrl
	}

func test_district_interactive_placement() -> void:
	var env = _create_test_environment()
	var game_state: GameState = env["game_state"]
	var input_ctrl: PlayerInputController = env["input_ctrl"]

	var city = game_state.found_city(GameEnums.FactionId.SOLARIS_DOMINION, Vector2i(5, 5), "Solaris Prime")
	assert_true(city != null, "City should be created")

	# Start placement mode
	input_ctrl.start_district_placement(city, "encampment")
	assert_true(input_ctrl.is_placing_district, "Should be in district placement mode")
	assert_eq(input_ctrl.placement_district_id, "encampment", "Placement district ID should match")

	# Check valid tiles: territory tiles except city center (5, 5)
	var valid_tiles = input_ctrl.valid_district_tiles
	assert_false(valid_tiles.has(Vector2i(5, 5)), "City center should not be a valid district placement tile")
	assert_true(valid_tiles.has(Vector2i(5, 6)), "Adjacent territory tile (5, 6) should be valid")

	# Tap valid tile to place
	input_ctrl.on_tile_tapped(Vector2i(5, 6))
	assert_false(input_ctrl.is_placing_district, "Should exit district placement mode after valid selection")
	assert_eq(city.planned_district_tiles.get("encampment", Vector2i(-1, -1)), Vector2i(5, 6), "Planned tile should be recorded")
	assert_eq(city.current_production_id, "encampment", "City production should switch to encampment")

func test_encampment_highland_bonus_and_wall_coupling() -> void:
	var env = _create_test_environment()
	var game_state: GameState = env["game_state"]
	var turn_manager: TurnManager = env["turn_manager"]

	var city = game_state.found_city(GameEnums.FactionId.SOLARIS_DOMINION, Vector2i(5, 5), "Highland City")
	city.planned_district_tiles["encampment"] = Vector2i(5, 6) # Hills tile!
	city.current_production_id = "encampment"

	# Build encampment
	turn_manager._place_district_on_city_territory(city, "encampment")
	city.has_military_encampment = true
	city.has_encampment = true

	var tile = game_state.grid_model.get_tile(Vector2i(5, 6))
	assert_true(tile.improvement_data != null, "Encampment improvement should be placed on tile")
	assert_eq(city.encampment_pos, Vector2i(5, 6), "City encampment_pos should match planned tile")

	# Verify Highland Production bonus (+3 Production)
	var yields = game_state.calculate_city_yields(city)
	assert_true(yields["production"] >= 5, "City yields should include base + encampment + 3 Highland bonus")

	# Check Encampment Wall coupling with City Walls
	assert_eq(city.encampment_health, 100, "Encampment should start with 100 HP")
	assert_eq(city.encampment_fortification, 0, "Encampment should have 0 Fortification without City Walls")

	# Produce city walls
	city.has_walls = true
	city.encampment_fortification = 50
	assert_eq(city.encampment_fortification, 50, "Encampment should have 50 Fortification when City has walls")

	# Damage Encampment: absorbs into fortification first
	var res = city.take_encampment_damage(30)
	assert_eq(res.remaining_fort, 20, "Fortification should absorb 30 damage, leaving 20")
	assert_eq(res.remaining_hp, 100, "Encampment HP should remain at 100 while fortified")

	# Further damage: breaks fortification and damages HP
	res = city.take_encampment_damage(30)
	assert_eq(res.remaining_fort, 0, "Fortification should be broken")
	assert_eq(res.remaining_hp, 90, "Remaining 10 damage should affect HP (100 - 10 = 90)")

func test_neighborhood_and_science_camp_adjacency() -> void:
	var env = _create_test_environment()
	var game_state: GameState = env["game_state"]
	var turn_manager: TurnManager = env["turn_manager"]

	var city = game_state.found_city(GameEnums.FactionId.SOLARIS_DOMINION, Vector2i(5, 5), "Metropolis")

	# 1. Science Campus next to mountain at (6, 5)
	city.planned_district_tiles["science_camp"] = Vector2i(5, 4)
	turn_manager._place_district_on_city_territory(city, "science_camp")
	city.has_science_camp = true
	city.science_camp_pos = Vector2i(5, 4)

	# Tile (5, 4) is adjacent to mountain (6, 5), giving +3 bonus
	var yields = game_state.calculate_city_yields(city)
	assert_true(yields["science"] >= 6, "Science Campus adjacent to mountain should grant +3 extra Science")

	# 2. Neighborhood adjacent to food tile
	var farm_tile = game_state.grid_model.get_tile(Vector2i(4, 5))
	var farm_imp = load("res://resources/improvements/farm.tres") as ImprovementData
	farm_tile.improvement_data = farm_imp

	city.planned_district_tiles["neighborhood"] = Vector2i(4, 6) # Adjacent to farm at (4, 5)
	turn_manager._place_district_on_city_territory(city, "neighborhood")
	city.has_neighborhood = true
	city.neighborhood_pos = Vector2i(4, 6)

	var housing = game_state.calculate_city_housing(city)
	# Base (4.0) + Farm (0.5) + Neighborhood (4.0) + Food Adjacency Bonus (2.0) = 10
	assert_true(housing >= 10, "Neighborhood adjacent to food improvement should provide +2 Housing bonus")

func test_garrison_position_and_scaling() -> void:
	var env = _create_test_environment()
	var game_state: GameState = env["game_state"]
	var turn_manager: TurnManager = env["turn_manager"]

	var city = game_state.found_city(GameEnums.FactionId.SOLARIS_DOMINION, Vector2i(5, 5), "Fortress City")
	var warrior_data = load("res://resources/units/swordsman.tres") as UnitData
	var unit = game_state.spawn_unit(warrior_data, GameEnums.FactionId.SOLARIS_DOMINION, Vector2i(5, 5))

	turn_manager.garrison_unit(unit.instance_id)
	assert_true(unit.is_garrisoned, "Unit should be marked as garrisoned")
	assert_eq(city.garrison_unit_id, unit.instance_id, "City garrison slot should hold unit ID")

	# Test target position computation in UnitView
	var u_view = UnitView.new()
	track(u_view)
	u_view.unit_instance = unit
	var target_pos = u_view.get_target_position(Vector2i(5, 5))
	assert_eq(target_pos, Vector2(5 * 16 + 4.0, 5 * 16 + 4.0), "Garrisoned unit should be offset to top-left corner")

func test_civ6_unit_automation_and_threat_detection() -> void:
	var env = _create_test_environment()
	var game_state: GameState = env["game_state"]
	var turn_manager: TurnManager = env["turn_manager"]

	var scout_data = load("res://resources/units/scout.tres") as UnitData
	var scout = game_state.spawn_unit(scout_data, GameEnums.FactionId.SOLARIS_DOMINION, Vector2i(2, 2))

	# Automate unit
	turn_manager.set_unit_automated(scout.instance_id, true)
	assert_true(scout.is_automated, "Unit should be marked automated")

	# Verify unmoved units list skips automated unit
	var unmoved = game_state.get_unmoved_units(GameEnums.FactionId.SOLARIS_DOMINION)
	assert_false(unmoved.has(scout), "Automated unit should not block turn completion")

	# Threat detection: spawn barbarian 2 tiles away at (3, 3)
	var barb_data = load("res://resources/units/barbarian_raider.tres") as UnitData
	var barb = game_state.spawn_unit(barb_data, GameEnums.FactionId.BARBARIANS, Vector2i(3, 3))
	assert_true(turn_manager.has_hostile_nearby(scout, 2), "Hostile should be detected within 2 tiles")

	# Process automation: should cancel automation immediately
	turn_manager.process_automated_units(GameEnums.FactionId.SOLARIS_DOMINION)
	assert_false(scout.is_automated, "Unit should wake up and stop automation when hostile is nearby")

func test_multilayer_border_walls_and_crash_safety() -> void:
	var env = _create_test_environment()
	var game_state: GameState = env["game_state"]
	var turn_manager: TurnManager = env["turn_manager"]

	# Verify ImprovementData health export prevents runtime crash
	var imp_data = load("res://resources/improvements/border_wall.tres") as ImprovementData
	assert_eq(imp_data.health, 50, "ImprovementData must have export health: int = 50")

	# Set up a tile with a Farm and territory ownership
	var coord = Vector2i(3, 3)
	var tile = game_state.grid_model.get_tile(coord)
	tile.owner_faction_id = GameEnums.FactionId.SOLARIS_DOMINION
	var farm_imp = load("res://resources/improvements/farm.tres") as ImprovementData
	tile.improvement_data = farm_imp

	# Spawn Military Engineer on the tile
	var eng_data = load("res://resources/units/military_engineer.tres") as UnitData
	var eng = game_state.spawn_unit(eng_data, GameEnums.FactionId.SOLARIS_DOMINION, coord)

	# Build border wall on the improved tile
	var res = turn_manager.build_border_wall(eng.instance_id)
	assert_true(res.get("success", false), "Military Engineer should be able to build Border Wall on improved tile")
	assert_true(tile.has_border_wall, "Tile must have has_border_wall set to true")
	assert_eq(tile.border_wall_health, 50, "Border Wall health must be 50")
	assert_eq(tile.improvement_data.improvement_type, GameEnums.ImprovementType.FARM, "Underlying Farm must NOT be destroyed")

	# Hostile unit attacks Border Wall
	var barb_data = load("res://resources/units/barbarian_raider.tres") as UnitData
	var barb = game_state.spawn_unit(barb_data, GameEnums.FactionId.BARBARIANS, Vector2i(3, 4))
	turn_manager.attack_border_wall(barb.instance_id, coord)
	assert_true(tile.border_wall_health < 50, "Border wall should take damage from attack")
