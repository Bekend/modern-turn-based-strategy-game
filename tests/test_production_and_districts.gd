@tool
extends "res://addons/godot_ai/testing/test_suite.gd"

func suite_name() -> String:
	return "production_and_districts"

func _create_test_environment() -> Dictionary:
	var grid = GridModel.new()
	grid.initialize(12, 12)
	var plains_data = load("res://resources/biomes/plains.tres") as BiomeData
	var ocean_data = load("res://resources/biomes/ocean.tres") as BiomeData

	for y in range(12):
		for x in range(12):
			grid.set_tile(Vector2i(x, y), plains_data)

	# Place some ocean tiles: (5, 6) inside territory, (5, 8) outside territory
	grid.set_tile(Vector2i(5, 6), ocean_data)
	grid.set_tile(Vector2i(5, 8), ocean_data)

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

func test_harbor_strict_borders() -> void:
	var env = _create_test_environment()
	var game_state: GameState = env["game_state"]
	var input_ctrl: PlayerInputController = env["input_ctrl"]

	var city = game_state.found_city(GameEnums.FactionId.SOLARIS_DOMINION, Vector2i(5, 5), "Port City")
	assert_true(city != null, "City founded")

	# (5, 6) is inside territory (1-ring radius around 5,5). (5, 8) is outside.
	assert_true(city.territory_tiles.has(Vector2i(5, 6)), "Tile (5, 6) should be inside territory")
	assert_false(city.territory_tiles.has(Vector2i(5, 8)), "Tile (5, 8) should be outside territory")

	var valid_tiles = input_ctrl.get_valid_district_placement_tiles(city, "harbor")
	assert_true(valid_tiles.has(Vector2i(5, 6)), "Ocean tile inside territory must be valid for harbor")
	assert_false(valid_tiles.has(Vector2i(5, 8)), "Ocean tile outside territory must NOT be valid for harbor")
	assert_false(valid_tiles.has(Vector2i(5, 5)), "City center must not be valid for harbor")

func test_production_queue_advance() -> void:
	var env = _create_test_environment()
	var game_state: GameState = env["game_state"]
	var turn_manager: TurnManager = env["turn_manager"]

	var city = game_state.found_city(GameEnums.FactionId.SOLARIS_DOMINION, Vector2i(2, 2), "Queue Town")
	city.current_production_id = "scout"
	city.queue_production("archer")
	city.queue_production("harvest_project")

	assert_eq(city.current_production_id, "scout", "Current production should be scout")
	assert_eq(city.production_queue.size(), 2, "Queue should contain 2 items")
	assert_eq(city.production_queue[0], "archer", "First queued item should be archer")
	assert_eq(city.production_queue[1], "harvest_project", "Second queued item should be harvest_project")

	# Finish scout with enough production (cost 25)
	var completed = city.add_production(30, func(id): return 25 if id == "scout" else 50)
	assert_eq(completed, "scout", "Scout should be completed")
	assert_eq(city.current_production_id, "archer", "Archer should automatically become current production")
	assert_eq(city.production_queue.size(), 1, "Queue should now have 1 item")
	assert_eq(city.production_stored, 5, "Excess production overflow (5) should be carried over")

	# Remove item from queue
	city.remove_from_queue_at(0)
	assert_true(city.production_queue.is_empty(), "Queue should now be empty")

func test_projects_rewards() -> void:
	var env = _create_test_environment()
	var game_state: GameState = env["game_state"]
	var turn_manager: TurnManager = env["turn_manager"]

	var city = game_state.found_city(GameEnums.FactionId.SOLARIS_DOMINION, Vector2i(8, 8), "Gold Coast")
	var initial_gold = game_state.faction_gold.get(GameEnums.FactionId.SOLARIS_DOMINION, 0)
	var initial_food = city.food_stored

	# Test commercial project completion
	city.current_production_id = "commercial_project"
	city.production_stored = 0
	# Produce 30 to complete commercial project (cost is 30)
	# Simulate TurnManager process turn
	var yield_lookup = func(id): return 30
	var done = city.add_production(30, yield_lookup)
	assert_eq(done, "commercial_project", "Commercial project should be completed")

	# Test food harvest project completion
	city.current_production_id = "harvest_project"
	city.production_stored = 0
	var done_food = city.add_production(30, yield_lookup)
	assert_eq(done_food, "harvest_project", "Harvest project should be completed")

func test_niter_mine_and_unit_requirements() -> void:
	var env = _create_test_environment()
	var grid: GridModel = env["grid"]
	var game_state: GameState = env["game_state"]
	var input_ctrl: PlayerInputController = env["input_ctrl"]

	var city = game_state.found_city(GameEnums.FactionId.SOLARIS_DOMINION, Vector2i(3, 3), "Salt Town")
	assert_true(city != null, "City founded")

	# Place niter resource on tile (3, 4) in city territory
	var niter_res = load("res://resources/strategic_resources/niter.tres") as ResourceData
	var tile = grid.get_tile(Vector2i(3, 4))
	tile.resource_data = niter_res

	# Verify initially no strategic niter available
	var strat_res_before = game_state.get_faction_strategic_resources(GameEnums.FactionId.SOLARIS_DOMINION)
	assert_eq(strat_res_before.get("niter", 0), 0, "Unimproved niter should not provide strategic resources")

	# Build a mine on niter tile
	var mine_imp = load("res://resources/improvements/mine.tres") as ImprovementData
	tile.improvement_data = mine_imp

	# Research gunpowder to harness niter
	if game_state.tech_manager.has_method("unlock_tech"):
		game_state.tech_manager.unlock_tech(GameEnums.FactionId.SOLARIS_DOMINION, "gunpowder")
	else:
		if not game_state.tech_manager.faction_tech_state.has(GameEnums.FactionId.SOLARIS_DOMINION):
			game_state.tech_manager.initialize_faction(GameEnums.FactionId.SOLARIS_DOMINION)
		game_state.tech_manager.faction_tech_state[GameEnums.FactionId.SOLARIS_DOMINION]["researched"].append("gunpowder")

	# Verify improved niter provides strategic niter
	var strat_res_after = game_state.get_faction_strategic_resources(GameEnums.FactionId.SOLARIS_DOMINION)
	assert_true(strat_res_after.get("niter", 0) >= 1, "Improved niter tile must provide strategic niter")

	# Test purchase_unit checks niter for musketman
	game_state.faction_gold[GameEnums.FactionId.SOLARIS_DOMINION] = 1000
	city.population = 4

	# If niter count is less than req_amount (2 without encampment), purchase_unit should return null
	# Currently we have 1 niter and no encampment, so req is 2
	var req_amount = game_state.get_required_resource_amount_for_city(city)
	assert_eq(req_amount, 2, "Req amount without encampment should be 2")
	var unit_fail = game_state.purchase_unit(city.city_id, "musketman")
	assert_true(unit_fail == null, "Cannot purchase musketman with insufficient niter (1 < 2)")

	# Add encampment to city -> req becomes 1
	city.has_encampment = true
	var req_encamp = game_state.get_required_resource_amount_for_city(city)
	assert_eq(req_encamp, 1, "Req amount with encampment should be 1")
	var unit_ok = game_state.purchase_unit(city.city_id, "musketman")
	assert_true(unit_ok != null, "Can purchase musketman when niter satisfies encampment requirement (1 >= 1)")
