extends RefCounted

## Automated in-engine test suite for all architectural audit fixes

var tree: SceneTree = null

func _init(p_tree: SceneTree = null) -> void:
	tree = p_tree

func test_combat_engine_division_guard() -> void:
	print("Checking CombatEngine zero-defense / edge ratio protection...")
	var ce = CombatEngine.new()
	var proto = UnitData.new()
	proto.combat_strength = 10
	proto.ranged_strength = 0
	proto.attack_range = 1
	
	var attacker = GameState.UnitInstance.new(1, proto, 0, Vector2i(0, 0))
	var city = CityData.new()
	city.city_id = 1
	city.city_name = "TestCity"
	city.faction_id = 1
	city.grid_pos = Vector2i(1, 1)
	city.health = 100
	city.max_health = 100
	city.fortification = 0
	city.max_fortification = 0
	city.base_defense_strength = 0 # zero defense
	
	# Should not crash, INF, or NaN
	var res = CombatEngine.resolve_city_siege(proto.combat_strength, 100, city, false)
	assert(res != null, "Combat result should not be null")
	assert(res.attacker_damage_dealt > 0, "Attacker should deal damage")
	assert(not is_nan(float(res.attacker_damage_dealt)), "Damage should not be NaN")
	assert(not is_inf(float(res.attacker_damage_dealt)), "Damage should not be Inf")
	print("  -> PASSED: CombatEngine zero-defense division guard")

func test_unit_instance_safe_queries() -> void:
	print("Checking UnitInstance is_naval_unit() and is_ranged_unit()...")
	var proto = UnitData.new()
	proto.unit_class = GameEnums.UnitClass.MELEE
	proto.is_naval = false
	proto.combat_strength = 15
	proto.ranged_strength = 0
	proto.attack_range = 1
	
	var land_unit = GameState.UnitInstance.new(10, proto, 0, Vector2i(2, 2))
	assert(not land_unit.is_naval_unit(), "Land unit should not be naval")
	assert(not land_unit.is_ranged_unit(), "Melee unit should not be ranged")
	
	var naval_proto = UnitData.new()
	naval_proto.unit_class = GameEnums.UnitClass.NAVAL_RANGED
	naval_proto.is_naval = true
	naval_proto.ranged_strength = 12
	naval_proto.attack_range = 2
	
	var naval_unit = GameState.UnitInstance.new(11, naval_proto, 0, Vector2i(3, 3))
	assert(naval_unit.is_naval_unit(), "Naval unit should be identified as naval")
	assert(naval_unit.is_ranged_unit(), "Ranged naval unit should be identified as ranged")
	print("  -> PASSED: UnitInstance safe queries")

func test_map_generator_zero_faction_guard() -> void:
	print("Checking MapGenerator zero-faction division guard...")
	var mg = MapGenerator.new(20, 20, 1234, 0)
	var data = mg.generate_map()
	assert(data != null, "Map should generate without error even if faction_count is 0")
	print("  -> PASSED: MapGenerator zero-faction division guard")

func test_espionage_signals_and_types() -> void:
	print("Checking EspionageManager types and signals...")
	var gs = GameState.new()
	var em = EspionageManager.new(gs)
	assert(em.game_state == gs, "game_state should match GameState reference")
	
	var agent = em.recruit_agent(0, 1)
	assert(agent != null, "Should recruit agent")
	assert(agent.faction_id == 0, "Agent faction should match")
	print("  -> PASSED: EspionageManager types and signals")

func test_lobby_manager_exit_cleanup() -> void:
	print("Checking LobbyManager UDP socket cleanup...")
	var lm = LobbyManager.new()
	lm.start_discovery()
	assert(lm._udp_peer != null, "UDP peer should initialize on discovery")
	lm.leave_lobby()
	assert(lm._udp_peer == null, "UDP peer should close and clear on leave_lobby")
	print("  -> PASSED: LobbyManager UDP cleanup")

func test_military_engineer_tile_is_city_safety() -> void:
	print("Checking Military Engineer tile.is_city access and border wall actions...")
	var grid = GridModel.new()
	grid.initialize(5, 5)
	var plains = BiomeData.new()
	plains.biome_type = GameEnums.BiomeType.PLAINS
	plains.is_passable = true
	plains.move_cost = 1
	
	for y in range(5):
		for x in range(5):
			grid.set_tile(Vector2i(x, y), plains)

	var gs = GameState.new()
	gs.initialize(grid)
			
	var city = gs.found_city(0, Vector2i(2, 2), "TestCity")
	var city_tile = gs.grid_model.get_tile(Vector2i(2, 2))
	assert(city_tile.is_city == true, "City tile should have is_city = true")
	
	var terr_tile = gs.grid_model.get_tile(Vector2i(2, 1))
	assert(terr_tile.is_city == false, "Territory tile should have is_city = false")
	
	var eng_proto = load("res://resources/units/military_engineer.tres") as UnitData
	assert(eng_proto != null, "Military Engineer prototype should load")
	var engineer = gs.spawn_unit(eng_proto, 0, Vector2i(2, 1))
	assert(engineer != null, "Military Engineer should spawn")
	
	var tm = TurnManager.new(gs)
	var res = tm.build_border_wall(engineer.instance_id)
	assert(res.get("success", false) == true, "Border wall should build successfully")
	assert(terr_tile.has_border_wall == true, "Tile should now have border wall")
	print("  -> PASSED: Military Engineer tile.is_city safety and border wall construction")

func test_diplomacy_city_discovery_crash_safety() -> void:
	print("Checking CityData is_discovered_by crash prevention...")
	var city = CityData.new()
	city.initialize(1, "Alpha", 0, Vector2i(2, 2))
	assert(city.is_discovered_by(0) == true, "City should be discovered by founding faction")
	assert(city.is_discovered_by(1) == false, "City should not be discovered by unencountered rival")
	city.discovered_by_faction[1] = true
	assert(city.is_discovered_by(1) == true, "City should be discovered after flag is set")
	print("  -> PASSED: CityData is_discovered_by crash prevention")

func test_fortification_dual_bars_and_wall_coupling() -> void:
	print("Checking FortificationView dual health & fortification bars...")
	var scene = load("res://scenes/views/FortificationView.tscn") as PackedScene
	assert(scene != null, "FortificationView scene should load")
	var view = scene.instantiate()
	assert(view != null, "FortificationView should instantiate")
	if tree and tree.root:
		tree.root.add_child(view)
	else:
		view._ready()
	view.setup(Vector2i(3, 4), GameEnums.ImprovementType.TEMPORARY_CAMP, 0)
	
	# Initial full display with walls
	view.update_display(100, 100, 50, 50, true)
	assert(view.hp_bar_fill.size.x == 10.0, "Full HP bar width should be 10px")
	assert(view.fort_bar_bg.visible == true, "Wall fortification bar should be visible with walls")
	assert(view.fort_bar_fill.size.x == 10.0, "Full fort bar width should be 10px")
	
	# Display without walls
	view.update_display(80, 100, 0, 0, false)
	assert(view.fort_bar_bg.visible == false, "Fort bar should be hidden when has_walls is false")
	
	# Low HP color change
	view.update_display(20, 100, 0, 0, false)
	assert(view.hp_bar_fill.color == Color("e74c3c"), "Low HP should display red bar")
	
	# Zero HP display
	view.update_display(0, 100, 0, 0, false)
	assert(view.hp_bar_fill.size.x == 0.0, "Dead HP bar width should be 0px")
	view.queue_free()
	print("  -> PASSED: FortificationView dual bars and wall coupling")

func test_fortification_ranged_bombardment() -> void:
	print("Checking fortification ranged defensive bombardment...")
	var grid = GridModel.new()
	grid.initialize(8, 8)
	var plains = BiomeData.new()
	plains.biome_type = GameEnums.BiomeType.PLAINS
	plains.is_passable = true
	plains.move_cost = 1
	for y in range(8):
		for x in range(8):
			grid.set_tile(Vector2i(x, y), plains)

	var gs = GameState.new()
	gs.initialize(grid)
	var tm = TurnManager.new(gs)
	
	# Place friendly temporary camp at (2, 2)
	var camp_tile = gs.grid_model.get_tile(Vector2i(2, 2))
	var imp = load("res://resources/improvements/temporary_camp.tres").duplicate() as ImprovementData
	camp_tile.improvement_data = imp
	camp_tile.owner_faction_id = GameEnums.FactionId.SOLARIS_DOMINION
	imp.has_bombarded_this_turn = false
	
	# Spawn enemy unit at (2, 4) (range 2)
	var enemy_proto = UnitData.new()
	enemy_proto.unit_name = "Invader"
	enemy_proto.combat_strength = 15
	enemy_proto.max_health = 100
	var enemy_u = gs.spawn_unit(enemy_proto, 1, Vector2i(2, 4))
	assert(enemy_u != null, "Enemy unit should spawn")
	
	# Bombard target
	var hit = tm.fortification_bombard_target(Vector2i(2, 2), Vector2i(2, 4))
	assert(hit == true, "Bombardment should succeed against enemy unit within range 2")
	assert(enemy_u.current_health < 100, "Defender should take damage from bombardment")
	assert(imp.has_bombarded_this_turn == true, "Fortification should be marked as bombarded")
	
	# Second bombardment attempt in same turn should fail
	var hit2 = tm.fortification_bombard_target(Vector2i(2, 2), Vector2i(2, 4))
	assert(hit2 == false, "Fortification cannot bombard twice in the same turn")
	print("  -> PASSED: Fortification ranged defensive bombardment")

func test_temporary_camp_outpost_fog_vision() -> void:
	print("Checking Temporary Camp outpost fog of war vision (2-tile radius)...")
	var grid = GridModel.new()
	grid.initialize(10, 10)
	var plains = BiomeData.new()
	plains.biome_type = GameEnums.BiomeType.PLAINS
	plains.is_passable = true
	plains.move_cost = 1
	for y in range(10):
		for x in range(10):
			grid.set_tile(Vector2i(x, y), plains)

	var gs = GameState.new()
	gs.initialize(grid)
	
	# Place friendly temporary camp at (5, 5)
	var camp_tile = gs.grid_model.get_tile(Vector2i(5, 5))
	var imp = load("res://resources/improvements/temporary_camp.tres").duplicate() as ImprovementData
	camp_tile.improvement_data = imp
	camp_tile.owner_faction_id = GameEnums.FactionId.SOLARIS_DOMINION
	
	gs.update_fog_of_war(GameEnums.FactionId.SOLARIS_DOMINION)
	
	var tile_r1 = gs.grid_model.get_tile(Vector2i(5, 6))
	var tile_r2 = gs.grid_model.get_tile(Vector2i(5, 7))
	var tile_r3 = gs.grid_model.get_tile(Vector2i(5, 8))
	
	assert(tile_r1.visible_by_faction.get(GameEnums.FactionId.SOLARIS_DOMINION, false) == true, "Radius 1 should be visible")
	assert(tile_r2.visible_by_faction.get(GameEnums.FactionId.SOLARIS_DOMINION, false) == true, "Radius 2 should be visible")
	assert(tile_r3.visible_by_faction.get(GameEnums.FactionId.SOLARIS_DOMINION, false) == false, "Radius 3 should remain hidden in fog")
	print("  -> PASSED: Temporary Camp outpost fog of war vision")

func test_fortification_blocking_and_raze_mechanics() -> void:
	print("Checking fortification impassability and raze-on-defeat mechanics...")
	var grid = GridModel.new()
	grid.initialize(8, 8)
	var plains = BiomeData.new()
	plains.biome_type = GameEnums.BiomeType.PLAINS
	plains.is_passable = true
	plains.move_cost = 1
	for y in range(8):
		for x in range(8):
			grid.set_tile(Vector2i(x, y), plains)

	var gs = GameState.new()
	gs.initialize(grid)
	var tm = TurnManager.new(gs)
	
	# Foreign camp at (3, 3)
	var target_tile = gs.grid_model.get_tile(Vector2i(3, 3))
	var imp = load("res://resources/improvements/temporary_camp.tres").duplicate() as ImprovementData
	imp.health = 25
	imp.max_health = 100
	imp.fortification = 10
	imp.max_fortification = 50
	target_tile.improvement_data = imp
	target_tile.owner_faction_id = 1 # Foreign rival
	
	# Friendly unit at (3, 2)
	var att_proto = UnitData.new()
	att_proto.unit_name = "Warrior"
	att_proto.unit_class = GameEnums.UnitClass.MELEE
	att_proto.max_health = 100
	att_proto.combat_strength = 20
	att_proto.max_movement_points = 3
	att_proto.attack_range = 1
	var att_u = gs.spawn_unit(att_proto, GameEnums.FactionId.SOLARIS_DOMINION, Vector2i(3, 2))
	att_u.remaining_mp = 3
	
	# Try to move unit into (3, 3). Because it has an enemy camp with HP > 0, move_unit intercepts to attack!
	var moved = tm.move_unit(att_u.instance_id, Vector2i(3, 3))
	assert(moved == true, "move_unit should execute attack against enemy camp")
	assert(att_u.grid_pos == Vector2i(3, 2), "Unit should not step onto camp while HP > 0")
	assert(imp.fortification == 0, "Fortification should be absorbed first")
	assert(imp.health == 15, "Remaining damage should pierce camp HP (25 - 10 = 15)")
	
	# Attack again with lethal damage to raze camp
	var razed_box = [false]
	var razed_handler = func(c, _fac):
		if c == Vector2i(3, 3):
			razed_box[0] = true
	gs.fortification_razed.connect(razed_handler)
	
	att_u.remaining_mp = 2
	att_u.has_attacked = false
	var attack2 = tm.attack_temporary_camp(att_u.instance_id, Vector2i(3, 3))
	assert(attack2 == true, "Second attack should succeed")
	assert(razed_box[0] == true, "fortification_razed signal should be emitted upon camp defeat")
	assert(target_tile.improvement_data == null, "Camp improvement should be deleted upon raze")
	assert(target_tile.owner_faction_id == -1, "Tile ownership should clear")
	
	# Now that camp is razed, unit can step into tile!
	att_u.remaining_mp = 2
	var move2 = tm.move_unit(att_u.instance_id, Vector2i(3, 3))
	assert(move2 == true, "Unit should now be able to step onto razed tile")
	assert(att_u.grid_pos == Vector2i(3, 3), "Unit should now occupy (3, 3)")
	print("  -> PASSED: Fortification impassability and raze-on-defeat mechanics")


