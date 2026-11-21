extends SceneTree

func _init() -> void:
	print("--- Running districts_and_features test suite in Godot engine ---")
	var suite_script = load("res://tests/test_districts_and_features.gd")
	var suite = suite_script.new()
	
	var test_methods = [
		"test_district_interactive_placement",
		"test_encampment_highland_bonus_and_wall_coupling",
		"test_neighborhood_and_science_camp_adjacency",
		"test_garrison_position_and_scaling",
		"test_civ6_unit_automation_and_threat_detection",
		"test_multilayer_border_walls_and_crash_safety"
	]
	
	var passed = 0
	for m in test_methods:
		print("Running: ", m)
		suite.call(m)
		print("  -> PASSED: ", m)
		passed += 1

	print("\n--- Running audit_fixes test suite in Godot engine ---")
	var audit_suite_script = load("res://tests/test_audit_fixes.gd")
	var audit_suite = audit_suite_script.new(self)
	var audit_methods = [
		"test_combat_engine_division_guard",
		"test_unit_instance_safe_queries",
		"test_map_generator_zero_faction_guard",
		"test_espionage_signals_and_types",
		"test_lobby_manager_exit_cleanup",
		"test_military_engineer_tile_is_city_safety",
		"test_diplomacy_city_discovery_crash_safety",
		"test_fortification_dual_bars_and_wall_coupling",
		"test_fortification_ranged_bombardment",
		"test_temporary_camp_outpost_fog_vision",
		"test_fortification_blocking_and_raze_mechanics"
	]
	for m in audit_methods:
		print("Running: ", m)
		audit_suite.call(m)
		print("  -> PASSED: ", m)
		passed += 1

	print("\n--- Running production_and_districts test suite in Godot engine ---")
	var prod_suite_script = load("res://tests/test_production_and_districts.gd")
	var prod_suite = prod_suite_script.new()
	var prod_methods = [
		"test_harbor_strict_borders",
		"test_production_queue_advance",
		"test_projects_rewards",
		"test_niter_mine_and_unit_requirements"
	]
	for m in prod_methods:
		print("Running: ", m)
		prod_suite.call(m)
		print("  -> PASSED: ", m)
		passed += 1
		
	print("--- ALL %d TESTS PASSED SUCCESSFULLY! ---" % passed)
	quit(0)
