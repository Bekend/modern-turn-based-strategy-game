class_name Main
extends Node2D

## Top-level game orchestrator coordinating the decoupled simulation core,
## procedural map generator, mobile touch camera, visual layers, audio, and retro HUD.

@onready var camera: TouchCameraController = $TouchCamera
@onready var map_view: MapView = $MapView
@onready var hud: HUD = $HUD
@onready var tech_modal: TechTreeModal = $HUD/TechTreeModal
@onready var unit_container: Node2D = $Entities/Units
@onready var city_container: Node2D = $Entities/Cities
@onready var camps_container: Node2D = $Entities/Camps
@onready var audio_manager: AudioManager = (get_node_or_null("/root/GlobalAudio") as AudioManager) if get_node_or_null("/root/GlobalAudio") else ($AudioManager if has_node("AudioManager") else null)
@onready var input_controller: PlayerInputController = $PlayerInputController

var game_state: GameState
var turn_manager: TurnManager
var map_gen: MapGenerator

var unit_views: Dictionary = {} # unit_id -> UnitView
var city_views: Dictionary = {} # city_id -> CityView
var camp_markers: Dictionary = {} # Vector2i -> Node2D
var fortification_views: Dictionary = {} # Vector2i -> FortificationView
var pending_ranged_death_units: Dictionary = {} # unit_id -> UnitView

# Preloaded view scenes
var unit_view_scene: PackedScene = preload("res://scenes/views/UnitView.tscn")
var city_view_scene: PackedScene = preload("res://scenes/views/CityView.tscn")
var fortification_view_scene: PackedScene = preload("res://scenes/views/FortificationView.tscn")

func _ready() -> void:
	var _cfg: Node = get_node_or_null("/root/GameConfig")
	if _cfg and _cfg.is_continue and SaveManager.save_exists():
		_cfg.is_continue = false
		_load_saved_game()
	else:
		_initialize_fresh_game()

func _initialize_fresh_game() -> void:
	# 1. Procedurally Generate Seeded Map
	var _cfg: Node = get_node_or_null("/root/GameConfig")
	var map_width: int = _cfg.get_map_width() if _cfg else 36
	var map_height: int = _cfg.get_map_height() if _cfg else 24
	var ai_count: int = _cfg.ai_count if _cfg else 2
	var faction_count: int = ai_count + 1
	var random_seed: int = int(Time.get_unix_time_from_system()) % 100000
	if _cfg and _cfg.is_multiplayer:
		random_seed = _cfg.multiplayer_seed

	map_gen = MapGenerator.new(map_width, map_height, random_seed, faction_count)
	var gen_data = map_gen.generate_map()
	var grid_model: GridModel = gen_data["grid"]
	var start_positions: Array[Vector2i] = gen_data["start_positions"]
	var barbarian_camps: Array[Vector2i] = gen_data["barbarian_camps"]

	# 2. Instantiate Decoupled Simulation Core
	game_state = GameState.new()
	var active_factions: Array[int] = [GameEnums.FactionId.SOLARIS_DOMINION]
	for i in range(1, ai_count + 1):
		active_factions.append(i)
	active_factions.append(GameEnums.FactionId.BARBARIANS)
	game_state.factions = active_factions
	game_state.initialize(grid_model)

	turn_manager = TurnManager.new(game_state)

	# 3. Setup Presentation Layer (TileMapLayers & Camera)
	map_view.initialize(game_state)
	camera.set_map_dimensions(map_width, map_height, 16)

	# 4. Setup Input Controller & HUD
	input_controller.setup(game_state, turn_manager)
	hud.setup(game_state, turn_manager)
	tech_modal.hide()

	# 5. Connect State & View Observer Signals
	_connect_signals()

	# 6. Spawn Starting Faction Units & Camps
	_spawn_initial_forces(start_positions, barbarian_camps)

	# 7. Center Camera on Player's starting Settler
	if not start_positions.is_empty():
		camera.focus_on_tile(start_positions[0])

	_refresh_all_fortification_views()

	# 8. Start Turn 1
	turn_manager.start_game()
	SaveManager.save_game(game_state, turn_manager)

func _connect_signals() -> void:
	# Camera Touch Tap -> Input Controller
	camera.tile_tapped.connect(input_controller.on_tile_tapped)

	# Input Controller -> MapView Overlays & HUD Cards
	input_controller.unit_selected.connect(func(unit, reachable, attackable):
		map_view.show_action_overlays(reachable, attackable, unit.grid_pos, unit.remaining_mp)
		if unit.data.can_found_city:
			map_view.show_settler_lens()
		else:
			map_view.hide_settler_lens()
		hud.show_unit_card(unit)
		if audio_manager:
			audio_manager.play_ui_click()
	)
	input_controller.city_selected.connect(func(city):
		map_view.hide_settler_lens()
		if input_controller.current_attackable_tiles.is_empty():
			map_view.clear_overlays()
		else:
			map_view.show_action_overlays({}, input_controller.current_attackable_tiles, city.grid_pos)
		hud.show_city_card(city)
		if audio_manager:
			audio_manager.play_ui_click()
	)
	input_controller.fortification_selected.connect(func(coords, imp, attackable):
		map_view.hide_settler_lens()
		if attackable.is_empty():
			map_view.clear_overlays()
		else:
			map_view.show_action_overlays({}, attackable, coords)
		hud.update_fortification_card(coords, imp, attackable)
		if audio_manager:
			audio_manager.play_ui_click()
	)
	input_controller.tile_inspected.connect(func(coords, tile):
		map_view.hide_settler_lens()
		map_view.clear_overlays()
		hud.show_tile_card(coords, tile)
	)
	input_controller.selection_cleared.connect(func():
		map_view.hide_settler_lens()
		map_view.clear_overlays()
		hud.hide_bottom_card()
	)
	input_controller.district_placement_started.connect(func(_city, _district_id, valid_tiles):
		map_view.show_district_placement_overlay(valid_tiles)
		hud.show_district_placement_banner(_district_id, _city.city_name)
	)
	input_controller.district_placement_ended.connect(func():
		map_view.hide_district_placement_overlay()
		hud.hide_district_placement_banner()
	)

	# Simulation State Events -> Visual Observers
	game_state.unit_spawned.connect(_on_unit_spawned)
	game_state.unit_removed.connect(_on_unit_removed)
	game_state.unit_moved.connect(_on_unit_moved)
	game_state.unit_attacked.connect(_on_unit_attacked)
	game_state.city_attacked.connect(_on_city_attacked)
	game_state.city_bombarded.connect(_on_city_bombarded)
	game_state.fortification_bombarded.connect(_on_fortification_bombarded)
	game_state.fortification_razed.connect(_on_fortification_razed)
	game_state.city_founded.connect(_on_city_founded)
	game_state.city_captured.connect(_on_city_captured)
	game_state.city_razed.connect(_on_city_razed)
	game_state.city_borders_expanded.connect(func(_c, _claimed):
		map_view.update_territory_display()
	)
	game_state.unit_upgraded.connect(_on_unit_upgraded)
	game_state.barbarian_camp_cleared.connect(_on_barbarian_camp_cleared)
	if game_state.espionage_manager:
		game_state.espionage_manager.espionage_feedback.connect(func(text, is_warning):
			hud.show_feedback(text, is_warning)
		)
	game_state.grid_model.tile_updated.connect(func(coords):
		map_view.render_tile(coords)
		_sync_fortification_view(coords)
	)
	game_state.grid_model.tile_changed.connect(func(coords):
		map_view.render_tile(coords)
		_sync_fortification_view(coords)
	)

	# Fog of War observer
	game_state.fog_of_war_updated.connect(func():
		if map_view.fog_of_war_layer:
			map_view.fog_of_war_layer.refresh()
		_update_views_fog_visibility()
	)

	# Turn Manager Events
	turn_manager.turn_started.connect(func(t_num):
		hud.update_top_bar()
		input_controller.clear_selection()
		_refresh_all_views()
		_refresh_all_fortification_views()
		_update_views_fog_visibility()
		if audio_manager:
			audio_manager.play_turn_start()
		SaveManager.save_game(game_state, turn_manager)
	)
	turn_manager.turn_phase_changed.connect(func(_phase, _active_fac):
		hud.update_top_bar()
	)
	turn_manager.action_feedback.connect(func(text, is_warning):
		hud.show_feedback(text, is_warning)
	)
	turn_manager.domination_victory.connect(func(victor):
		hud.show_victory_screen(victor)
		if audio_manager:
			audio_manager.play_camp_cleared()
	)
	turn_manager.faction_defeated.connect(func(loser):
		if loser == GameEnums.FactionId.SOLARIS_DOMINION:
			hud.show_victory_screen(loser)
	)

	# HUD User Requests & Save / Load
	hud.save_requested.connect(func():
		var ok = SaveManager.save_game(game_state, turn_manager)
		if ok:
			hud.show_feedback("Game saved successfully!", false)
		else:
			hud.show_feedback("Failed to save game.", true)
		hud.hide_pause_menu()
	)
	hud.save_and_exit_requested.connect(func():
		SaveManager.save_game(game_state, turn_manager)
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	)

	# Unit Upgrade Request from HUD
	hud.unit_upgrade_requested.connect(func(u_id):
		var ok = turn_manager.upgrade_unit_command(u_id)
		hud.update_top_bar()
		var unit = game_state.units.get(u_id, null)
		if unit:
			hud.show_unit_card(unit)
	)

	# Found City Action
	hud.found_city_requested.connect(func(u_id):
		var ok = turn_manager.found_city_command(u_id)
		if ok:
			input_controller.clear_selection()
			hud.hide_bottom_card()
			hud.update_top_bar()
			_refresh_all_views()
	)

	# Build Improvement Action
	hud.build_improvement_requested.connect(func(u_id, impr_type):
		var ok = turn_manager.build_improvement_command(u_id, impr_type)
		if ok:
			var unit = game_state.units.get(u_id, null)
			if unit:
				hud.show_unit_card(unit)
			else:
				input_controller.clear_selection()
				hud.hide_bottom_card()
			hud.update_top_bar()
			_refresh_all_views()
	)

	# Tactical Actions (Pillage, Heal, Skip, Fortify, Military Engineer Structures)
	hud.unit_pillage_requested.connect(func(u_id):
		var res = turn_manager.pillage_tile(u_id)
		if res.get("success", false):
			var unit = game_state.units.get(u_id, null)
			if unit:
				hud.show_unit_card(unit)
				spawn_floating_text(unit.grid_pos, "+%d 🪙 PILLAGED (+%d HP)" % [res.get("gold", 30), res.get("healed", 35)], Color("f1c40f"))
			hud.update_top_bar()
			_refresh_all_views()
	)
	hud.unit_heal_requested.connect(func(u_id):
		var res = turn_manager.heal_unit(u_id)
		if res.get("success", false):
			var unit = game_state.units.get(u_id, null)
			if unit:
				hud.show_unit_card(unit)
				spawn_floating_text(unit.grid_pos, "+%d HP HEALED" % res.get("healed", 15), Color("2ecc71"))
			hud.update_top_bar()
			input_controller.clear_selection()
	)
	hud.unit_skip_requested.connect(func(u_id):
		turn_manager.skip_unit_turn(u_id)
		input_controller.clear_selection()
		hud.update_top_bar()
	)
	hud.unit_fortify_requested.connect(func(u_id):
		turn_manager.fortify_unit(u_id)
		var unit = game_state.units.get(u_id, null)
		if unit:
			spawn_floating_text(unit.grid_pos, "🛡 FORTIFIED (+25%)", Color("3498db"))
		input_controller.clear_selection()
		hud.update_top_bar()
	)
	hud.garrison_unit_requested.connect(func(u_id):
		var res = turn_manager.garrison_unit(u_id)
		if res.get("success", false):
			var unit = game_state.units.get(u_id, null)
			if unit:
				spawn_floating_text(unit.grid_pos, "🛡 GARRISONED (+10 DEF)", Color("ffd700"))
			input_controller.clear_selection()
			hud.hide_bottom_card()
			hud.update_top_bar()
			_refresh_all_views()
	)
	hud.build_border_wall_requested.connect(func(u_id):
		var res = turn_manager.build_border_wall(u_id)
		if res.get("success", false):
			var unit = game_state.units.get(u_id, null)
			if unit:
				hud.show_unit_card(unit)
			else:
				input_controller.clear_selection()
				hud.hide_bottom_card()
			hud.update_top_bar()
			_refresh_all_views()
	)
	hud.build_temporary_camp_requested.connect(func(u_id):
		var res = turn_manager.build_temporary_camp(u_id)
		if res.get("success", false):
			var unit = game_state.units.get(u_id, null)
			if unit:
				hud.show_unit_card(unit)
			else:
				input_controller.clear_selection()
				hud.hide_bottom_card()
			hud.update_top_bar()
			_refresh_all_views()
	)

	# District Placement HUD signals
	hud.start_district_placement_requested.connect(func(city, district_id):
		input_controller.start_district_placement(city, district_id)
	)
	hud.cancel_district_placement_requested.connect(func():
		input_controller.cancel_district_placement()
	)

	# Garrison Selection from City Card
	hud.select_garrisoned_unit_requested.connect(func(u_id):
		var unit = game_state.units.get(u_id, null)
		if unit:
			input_controller._select_unit(unit)
	)

	# Unit Automation
	hud.unit_automate_requested.connect(func(u_id, automated):
		turn_manager.set_unit_automated(u_id, automated)
		var unit = game_state.units.get(u_id, null)
		if unit:
			hud.show_unit_card(unit)
		hud.update_top_bar()
		_refresh_all_views()
	)

	# Cycling Units & Cities
	hud.cycle_unit_requested.connect(func():
		input_controller.cycle_next_unit()
		if input_controller.selected_unit:
			camera.focus_on_tile(input_controller.selected_unit.grid_pos)
	)
	hud.cycle_city_requested.connect(func():
		input_controller.cycle_next_city()
		if input_controller.selected_city:
			camera.focus_on_tile(input_controller.selected_city.grid_pos)
	)
	hud.select_city_requested.connect(func(city: CityData):
		input_controller.select_city(city)
		camera.focus_on_tile(city.grid_pos)
	)

	# End Turn Action
	hud.end_turn_requested.connect(func():
		turn_manager.end_player_turn()
	)

	# Change City Production
	hud.change_production_requested.connect(func(c_id, item_id):
		var city = game_state.cities.get(c_id, null)
		if city and city.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
			city.current_production_id = item_id
			hud.update_top_bar()
	)
	hud.purchase_unit_requested.connect(_on_purchase_unit_requested)

	# Tech Tree Modal
	hud.tech_tree_opened.connect(func():
		tech_modal.open(game_state.tech_manager, GameEnums.FactionId.SOLARIS_DOMINION)
	)
	tech_modal.tech_chosen.connect(func(_tid):
		hud.update_top_bar()
	)

	# Diplomacy signals from HUD
	hud.declare_war_requested.connect(func(target_fac):
		if game_state.diplomacy_manager:
			game_state.diplomacy_manager.declare_war(GameEnums.FactionId.SOLARIS_DOMINION, target_fac)
			hud.show_feedback("⚔ Declared WAR on %s!" % game_state.faction_names.get(target_fac, "Empire"), true)
	)
	hud.peace_proposed.connect(func(target_fac):
		if game_state.diplomacy_manager:
			game_state.diplomacy_manager.make_peace(GameEnums.FactionId.SOLARIS_DOMINION, target_fac)
			hud.show_feedback("🕊 Signed PEACE treaty with %s!" % game_state.faction_names.get(target_fac, "Empire"), false)
	)
	hud.trade_deal_requested.connect(func(target_fac):
		if game_state.diplomacy_manager:
			var gold = game_state.faction_gold.get(GameEnums.FactionId.SOLARIS_DOMINION, 0)
			if gold < 20:
				hud.show_feedback("Need 20 🪙 to initiate Trade Deal!", true)
				return
			game_state.faction_gold[GameEnums.FactionId.SOLARIS_DOMINION] -= 20
			game_state.diplomacy_manager.start_trade_agreement(GameEnums.FactionId.SOLARIS_DOMINION, target_fac, 10)
			hud.show_feedback("🤝 Established 10-turn Trade Agreement (+2 🪙/turn) with %s!" % game_state.faction_names.get(target_fac, "Empire"), false)
			hud.update_top_bar()
	)
	hud.resource_trade_requested.connect(func(target_fac, res_type):
		if game_state.diplomacy_manager:
			var success = game_state.diplomacy_manager.start_resource_export(GameEnums.FactionId.SOLARIS_DOMINION, target_fac, res_type, 10)
			if success:
				game_state.faction_gold[GameEnums.FactionId.SOLARIS_DOMINION] = game_state.faction_gold.get(GameEnums.FactionId.SOLARIS_DOMINION, 0) + 40
				hud.show_feedback("💰 Exported %s to %s for +40 🪙 (10-turn pact)!" % [res_type.capitalize(), game_state.faction_names.get(target_fac, "Empire")], false)
				hud.update_top_bar()
	)

	if game_state.diplomacy_manager:
		game_state.diplomacy_manager.faction_met.connect(func(fac_a, fac_b):
			if fac_a == GameEnums.FactionId.SOLARIS_DOMINION or fac_b == GameEnums.FactionId.SOLARIS_DOMINION:
				var other = fac_b if fac_a == GameEnums.FactionId.SOLARIS_DOMINION else fac_a
				var other_name = game_state.faction_names.get(other, "Foreign Empire")
				hud.show_feedback("📜 First Contact established with %s!" % other_name, false)
				if audio_manager:
					audio_manager.play_upgrade()
		)

func _is_tile_visible_to_player(coords: Vector2i) -> bool:
	if not game_state or not game_state.grid_model:
		return false
	var tile = game_state.grid_model.get_tile(coords)
	if not tile:
		return false
	return tile.visible_by_faction.get(GameEnums.FactionId.SOLARIS_DOMINION, false)

func _update_views_fog_visibility() -> void:
	for uid in unit_views.keys():
		var unit = game_state.units.get(uid, null)
		var view = unit_views[uid]
		if unit and view and view.has_method("update_visibility"):
			view.update_visibility(GameEnums.FactionId.SOLARIS_DOMINION, game_state.grid_model)
			if view.visible and unit.faction_id != GameEnums.FactionId.SOLARIS_DOMINION and unit.faction_id != GameEnums.FactionId.BARBARIANS:
				if game_state.diplomacy_manager:
					game_state.diplomacy_manager.meet_factions(GameEnums.FactionId.SOLARIS_DOMINION, unit.faction_id)
	for cid in city_views.keys():
		var city = game_state.cities.get(cid, null)
		var view = city_views[cid]
		if city and view and view.has_method("update_visibility"):
			view.update_visibility(GameEnums.FactionId.SOLARIS_DOMINION, game_state.grid_model)
			if view.visible and city.faction_id != GameEnums.FactionId.SOLARIS_DOMINION:
				if game_state.diplomacy_manager:
					game_state.diplomacy_manager.meet_factions(GameEnums.FactionId.SOLARIS_DOMINION, city.faction_id)
	for c_pos in camp_markers.keys():
		var marker = camp_markers[c_pos]
		var tile = game_state.grid_model.get_tile(c_pos)
		if tile:
			marker.visible = tile.revealed_by_faction.get(GameEnums.FactionId.SOLARIS_DOMINION, false)
	for f_pos in fortification_views.keys():
		var f_view = fortification_views[f_pos]
		if is_instance_valid(f_view):
			f_view.update_visibility(GameEnums.FactionId.SOLARIS_DOMINION, game_state.grid_model)

func _spawn_camp_marker(coords: Vector2i) -> void:
	if camp_markers.has(coords):
		return
	var marker = Node2D.new()
	marker.position = Vector2(coords.x * 16, coords.y * 16)
	var lbl = Label.new()
	lbl.text = "⛺"
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.position = Vector2(2, 0)
	lbl.z_index = 5
	marker.add_child(lbl)
	camps_container.add_child(marker)
	camp_markers[coords] = marker

func _on_barbarian_camp_cleared(coords: Vector2i, _unit: GameState.UnitInstance) -> void:
	if camp_markers.has(coords):
		camp_markers[coords].queue_free()
		camp_markers.erase(coords)
	if audio_manager:
		audio_manager.play_camp_cleared()
	spawn_floating_text(coords, "+30 🪙 CAMP CLEARED!", Color("f1c40f"))
	hud.update_top_bar()

func _on_unit_upgraded(unit: GameState.UnitInstance, _old_data: UnitData, new_data: UnitData) -> void:
	if unit_views.has(unit.instance_id):
		var view = unit_views[unit.instance_id]
		view.update_view()
	if audio_manager:
		audio_manager.play_upgrade()
	spawn_floating_text(unit.grid_pos, "⭐ UPGRADED TO %s!" % new_data.unit_name.to_upper(), Color("2ecc71"))
	hud.update_top_bar()

func _spawn_initial_forces(start_positions: Array[Vector2i], barbarian_camps: Array[Vector2i]) -> void:
	var proto_settler: UnitData = load("res://resources/units/settler.tres")
	var proto_builder: UnitData = load("res://resources/units/builder.tres")
	var proto_scout: UnitData = load("res://resources/units/scout.tres")
	var proto_slinger: UnitData = load("res://resources/units/slinger.tres")
	var proto_raider: UnitData = load("res://resources/units/barbarian_raider.tres")

	var find_free_tile = func(origin: Vector2i) -> Vector2i:
		for n in game_state.grid_model.get_neighbors(origin, true):
			if game_state.grid_model.is_passable(n) and game_state.get_unit_at(n) == null:
				return n
		return origin

	# 1. Player (Solaris Dominion)
	if start_positions.size() > 0:
		var p_pos = start_positions[0]
		game_state.spawn_unit(proto_settler, GameEnums.FactionId.SOLARIS_DOMINION, p_pos)
		var p_scout_pos = find_free_tile.call(p_pos)
		game_state.spawn_unit(proto_scout, GameEnums.FactionId.SOLARIS_DOMINION, p_scout_pos)
		var p_builder_pos = find_free_tile.call(p_pos)
		game_state.spawn_unit(proto_builder, GameEnums.FactionId.SOLARIS_DOMINION, p_builder_pos)

	# 2. Rival AI Factions (up to 6)
	var _cfg: Node = get_node_or_null("/root/GameConfig")
	var rival_count: int = _cfg.ai_count if _cfg else 2
	for i in range(1, rival_count + 1):
		if i < start_positions.size():
			var r_pos = start_positions[i]
			var fid = i
			game_state.spawn_unit(proto_settler, fid, r_pos)
			var escort_proto = proto_slinger if (i % 2 == 1) else proto_scout
			var escort_pos = find_free_tile.call(r_pos)
			game_state.spawn_unit(escort_proto, fid, escort_pos)

	# 4. Neutral Barbarian Encampments
	game_state.barbarian_camps = barbarian_camps.duplicate()
	for b_pos in barbarian_camps:
		_spawn_camp_marker(b_pos)
		game_state.spawn_unit(proto_raider, GameEnums.FactionId.BARBARIANS, b_pos)

	_update_views_fog_visibility()

# =============================================================
# VIEW OBSERVER HANDLERS
# =============================================================

func _on_unit_spawned(unit: GameState.UnitInstance) -> void:
	var view: UnitView = unit_view_scene.instantiate()
	unit_container.add_child(view)
	var color = game_state.faction_colors.get(unit.faction_id, Color.WHITE)
	view.setup(unit, color)
	unit_views[unit.instance_id] = view
	view.update_visibility(GameEnums.FactionId.SOLARIS_DOMINION, game_state.grid_model)

func _on_purchase_unit_requested(city_id: int, unit_id: String) -> void:
	var city = game_state.cities.get(city_id, null)
	if not city:
		return
	var unit = game_state.purchase_unit(city_id, unit_id)
	if unit:
		var cost = game_state.UNIT_PRODUCTION_COSTS.get(unit_id, 30) * 2
		spawn_floating_text(unit.grid_pos, "-%d 🪙 %s BOUGHT!" % [cost, unit.data.unit_name.to_upper()], Color("ffd700"))
		if audio_manager:
			audio_manager.play_ui_click()
		hud.update_top_bar()
		hud.show_production_menu(city)
		hud.show_city_card(city)
		_update_views_fog_visibility()
	else:
		hud.show_feedback("Cannot purchase %s! Insufficient gold or no spawn space." % unit_id.capitalize(), true)

func spawn_floating_text(grid_tile: Vector2i, text: String, color: Color = Color.WHITE) -> void:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.z_index = 90
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var world_pos = Vector2(grid_tile.x * 16 + 8, grid_tile.y * 16 - 2)
	label.position = world_pos - Vector2(10, 6)
	add_child(label)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 18.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.9).set_trans(Tween.TRANS_LINEAR)
	tween.chain().tween_callback(label.queue_free)

func _on_unit_removed(unit_id: int, _faction_id: int, coords: Vector2i) -> void:
	if pending_ranged_death_units.has(unit_id):
		return

	if unit_views.has(unit_id):
		var view = unit_views[unit_id]
		unit_views.erase(unit_id)
		view.queue_free()

	var tile = game_state.grid_model.get_tile(coords)
	if tile and tile.unit_id == unit_id:
		tile.unit_id = -1

func _on_unit_moved(unit: GameState.UnitInstance, _from: Vector2i, to: Vector2i) -> void:
	if unit_views.has(unit.instance_id):
		unit_views[unit.instance_id].move_to_tile(to)
	if audio_manager and unit.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
		audio_manager.play_unit_move()
	_update_views_fog_visibility()
	hud.update_top_bar()

func _on_unit_attacked(attacker: GameState.UnitInstance, defender: GameState.UnitInstance, result: CombatEngine.CombatResult) -> void:
	var is_visible = _is_tile_visible_to_player(attacker.grid_pos) or _is_tile_visible_to_player(defender.grid_pos)
	var is_ranged = attacker.data.is_ranged()
	var att_id = attacker.instance_id
	var def_id = defender.instance_id
	var att_pos = attacker.grid_pos
	var def_pos = defender.grid_pos
	var def_died = result.defender_died
	var att_died = result.attacker_died
	var dmg_to_def = result.attacker_damage_dealt
	var dmg_to_att = result.defender_damage_dealt

	if is_ranged:
		if is_visible:
			if audio_manager:
				audio_manager.play_ranged_fire()
			if def_died and unit_views.has(def_id):
				pending_ranged_death_units[def_id] = unit_views[def_id]

			_play_projectile_fx(att_pos, def_pos, func():
				if audio_manager:
					audio_manager.play_projectile_hit()
				var d_view = unit_views.get(def_id, null)
				if is_instance_valid(d_view):
					d_view.update_display()
					spawn_floating_text(def_pos, "-%d HP" % dmg_to_def, Color("e74c3c"))
					if def_died:
						d_view.queue_free()
						unit_views.erase(def_id)
						if audio_manager:
							audio_manager.play_unit_death()
				if def_died:
					pending_ranged_death_units.erase(def_id)
				var a_view = unit_views.get(att_id, null)
				if is_instance_valid(a_view):
					a_view.update_display()
			)
		else:
			# Silent resolution in fog of war
			var d_view = unit_views.get(def_id, null)
			if is_instance_valid(d_view):
				d_view.update_display()
				if def_died:
					d_view.queue_free()
					unit_views.erase(def_id)
			if def_died:
				pending_ranged_death_units.erase(def_id)
			var a_view = unit_views.get(att_id, null)
			if is_instance_valid(a_view):
				a_view.update_display()
		return

	# Melee engagement
	var att_view = unit_views.get(att_id, null)
	var def_view = unit_views.get(def_id, null)

	if is_visible:
		if audio_manager:
			audio_manager.play_attack_melee()
		if is_instance_valid(att_view):
			att_view.play_attack_animation(def_pos, def_died and not is_ranged)
		if is_instance_valid(def_view):
			def_view.play_attack_animation(att_pos, false)

		spawn_floating_text(def_pos, "-%d HP" % dmg_to_def, Color("e74c3c"))
		if dmg_to_att > 0:
			spawn_floating_text(att_pos, "-%d HP" % dmg_to_att, Color("f39c12"))

		if is_instance_valid(att_view):
			att_view.update_display()
		if is_instance_valid(def_view):
			def_view.update_display()

		if def_died and audio_manager:
			audio_manager.play_unit_death()
		elif att_died and audio_manager:
			audio_manager.play_unit_death()
	else:
		# Silent in fog of war
		if is_instance_valid(att_view):
			att_view.update_display()
		if is_instance_valid(def_view):
			def_view.update_display()
	hud.update_top_bar()

func _on_city_attacked(attacker: GameState.UnitInstance, city: CityData, result: CombatEngine.CombatResult) -> void:
	var is_visible = _is_tile_visible_to_player(attacker.grid_pos) or _is_tile_visible_to_player(city.grid_pos)
	var is_ranged = attacker.data.is_ranged()
	var att_id = attacker.instance_id
	var c_id = city.city_id
	var att_pos = attacker.grid_pos
	var c_pos = city.grid_pos
	var fort_dmg = result.fort_damage
	var hp_dmg = result.city_hp_damage
	var ret_dmg = result.defender_damage_dealt
	var att_died = result.attacker_died
	var captured = result.city_captured

	if is_ranged:
		if is_visible:
			if audio_manager:
				audio_manager.play_ranged_fire()
			_play_projectile_fx(att_pos, c_pos, func():
				if audio_manager:
					audio_manager.play_projectile_hit()
				var cv = city_views.get(c_id, null)
				if is_instance_valid(cv):
					if cv.has_method("play_hit_shake"):
						cv.play_hit_shake()
					cv.update_display()
				var av = unit_views.get(att_id, null)
				if is_instance_valid(av):
					av.update_display()
				if fort_dmg > 0:
					spawn_floating_text(c_pos, "-%d Fort" % fort_dmg, Color("3498db"))
				if hp_dmg > 0:
					spawn_floating_text(c_pos, "-%d HP" % hp_dmg, Color("e74c3c"))
			)
		else:
			# Silent in fog
			var cv = city_views.get(c_id, null)
			if is_instance_valid(cv):
				cv.update_display()
			var av = unit_views.get(att_id, null)
			if is_instance_valid(av):
				av.update_display()
		return

	# Melee city assault
	var att_view = unit_views.get(att_id, null)
	var city_view = city_views.get(c_id, null)

	if is_visible:
		if audio_manager:
			audio_manager.play_attack_melee()
		if is_instance_valid(att_view):
			att_view.play_attack_animation(c_pos, captured)
		if is_instance_valid(city_view):
			if city_view.has_method("play_hit_shake"):
				city_view.play_hit_shake()
			city_view.update_display()

		if fort_dmg > 0:
			spawn_floating_text(c_pos, "-%d Fort" % fort_dmg, Color("3498db"))
		if hp_dmg > 0:
			spawn_floating_text(c_pos, "-%d HP" % hp_dmg, Color("e74c3c"))
		if ret_dmg > 0:
			spawn_floating_text(att_pos, "-%d HP" % ret_dmg, Color("f39c12"))

		if is_instance_valid(att_view):
			att_view.update_display()

		if att_died and audio_manager:
			audio_manager.play_unit_death()
	else:
		# Silent in fog
		if is_instance_valid(city_view):
			city_view.update_display()
		if is_instance_valid(att_view):
			att_view.update_display()
	hud.update_top_bar()

func _on_city_bombarded(city: CityData, target_unit: GameState.UnitInstance, damage: int) -> void:
	var is_visible = _is_tile_visible_to_player(city.grid_pos) or _is_tile_visible_to_player(target_unit.grid_pos)
	var c_pos = city.grid_pos
	var tgt_id = target_unit.instance_id
	var tgt_pos = target_unit.grid_pos

	if is_visible:
		if audio_manager:
			audio_manager.play_ranged_fire()
		_play_projectile_fx(c_pos, tgt_pos, func():
			if audio_manager:
				audio_manager.play_projectile_hit()
			var tv = unit_views.get(tgt_id, null)
			if is_instance_valid(tv):
				tv.update_display()
			spawn_floating_text(tgt_pos, "-%d HP" % damage, Color("e74c3c"))
			if target_unit.current_health <= 0:
				if audio_manager:
					audio_manager.play_unit_death()
				if is_instance_valid(tv):
					tv.queue_free()
					unit_views.erase(tgt_id)
		)
	else:
		var tv = unit_views.get(tgt_id, null)
		if is_instance_valid(tv):
			tv.update_display()
			if target_unit.current_health <= 0:
				tv.queue_free()
				unit_views.erase(tgt_id)

func _on_fortification_bombarded(coords: Vector2i, target_unit: GameState.UnitInstance, damage: int) -> void:
	var is_visible = _is_tile_visible_to_player(coords) or _is_tile_visible_to_player(target_unit.grid_pos)
	var tgt_id = target_unit.instance_id
	var tgt_pos = target_unit.grid_pos

	if is_visible:
		if audio_manager:
			audio_manager.play_ranged_fire()
		_play_projectile_fx(coords, tgt_pos, func():
			if audio_manager:
				audio_manager.play_projectile_hit()
			var tv = unit_views.get(tgt_id, null)
			if is_instance_valid(tv):
				tv.update_display()
			spawn_floating_text(tgt_pos, "-%d HP" % damage, Color("e74c3c"))
			if target_unit.current_health <= 0:
				if audio_manager:
					audio_manager.play_unit_death()
				if is_instance_valid(tv):
					tv.queue_free()
					unit_views.erase(tgt_id)
		)
	else:
		var tv = unit_views.get(tgt_id, null)
		if is_instance_valid(tv):
			tv.update_display()
			if target_unit.current_health <= 0:
				tv.queue_free()
				unit_views.erase(tgt_id)

	_sync_fortification_view(coords)

func _on_fortification_razed(coords: Vector2i, _conqueror_faction_id: int) -> void:
	if fortification_views.has(coords):
		var v = fortification_views[coords]
		fortification_views.erase(coords)
		if is_instance_valid(v):
			v.queue_free()

	if _is_tile_visible_to_player(coords):
		spawn_floating_text(coords, "💥 FORTIFICATION RAZED!", Color("e74c3c"))
		if audio_manager:
			audio_manager.play_camp_cleared()

	if input_controller.selected_fortification == coords:
		input_controller.clear_selection()

func _sync_fortification_view(coords: Vector2i) -> void:
	if not game_state or not game_state.grid_model:
		return
	var tile = game_state.grid_model.get_tile(coords)
	if not tile or tile.improvement_data == null:
		if fortification_views.has(coords):
			var v = fortification_views[coords]
			fortification_views.erase(coords)
			if is_instance_valid(v):
				v.queue_free()
		return

	var imp = tile.improvement_data
	var is_encampment = (imp.improvement_type == GameEnums.ImprovementType.MILITARY_ENCAMPMENT)
	var is_camp = (imp.improvement_type == GameEnums.ImprovementType.TEMPORARY_CAMP)
	if not is_encampment and not is_camp:
		if fortification_views.has(coords):
			var v = fortification_views[coords]
			fortification_views.erase(coords)
			if is_instance_valid(v):
				v.queue_free()
		return

	var view = fortification_views.get(coords, null)
	if not is_instance_valid(view):
		view = fortification_view_scene.instantiate()
		fortification_views[coords] = view
		add_child(view)
		view.setup(coords, imp.improvement_type, tile.owner_faction_id)

	var cur_hp = imp.health
	var max_hp = imp.max_health
	var cur_fort = imp.fortification
	var max_fort = imp.max_fortification
	var has_walls = imp.has_walls

	if is_encampment:
		var owning_city: CityData = null
		if tile.city_id != -1:
			owning_city = game_state.cities.get(tile.city_id, null)
		if not owning_city:
			for c in game_state.cities.values():
				if c.faction_id == tile.owner_faction_id and c.encampment_pos == coords:
					owning_city = c
					break
		if owning_city:
			has_walls = owning_city.has_walls
			cur_fort = owning_city.encampment_fortification
			max_fort = owning_city.encampment_max_fortification
			cur_hp = owning_city.encampment_health
			max_hp = owning_city.encampment_max_health
			imp.has_walls = has_walls
			imp.fortification = cur_fort
			imp.max_fortification = max_fort
			imp.health = cur_hp
			imp.max_health = max_hp

	view.update_display(cur_hp, max_hp, cur_fort, max_fort, has_walls)
	view.update_visibility(GameEnums.FactionId.SOLARIS_DOMINION, game_state.grid_model)

func _refresh_all_fortification_views() -> void:
	if not game_state or not game_state.grid_model:
		return
	for y in range(game_state.grid_model.height):
		for x in range(game_state.grid_model.width):
			_sync_fortification_view(Vector2i(x, y))

func _play_projectile_fx(from_tile: Vector2i, to_tile: Vector2i, on_impact: Callable) -> void:
	var red_dot = ColorRect.new()
	red_dot.color = Color(1.0, 0.15, 0.15, 1.0)
	red_dot.size = Vector2(4, 4)
	red_dot.z_index = 80

	var start_pos = Vector2(from_tile.x * 16 + 6, from_tile.y * 16 + 6)
	var target_pos = Vector2(to_tile.x * 16 + 6, to_tile.y * 16 + 6)
	red_dot.position = start_pos
	add_child(red_dot)

	var dist = start_pos.distance_to(target_pos)
	var dur = clampf(dist / 220.0, 0.12, 0.35)

	var tween = create_tween()
	tween.tween_property(red_dot, "position", target_pos, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		if is_instance_valid(red_dot):
			red_dot.queue_free()
		if not on_impact.is_null() and on_impact.is_valid():
			on_impact.call()
	)

func _on_city_founded(city: CityData) -> void:
	var view: CityView = city_view_scene.instantiate()
	city_container.add_child(view)
	var color = game_state.faction_colors.get(city.faction_id, Color.WHITE)
	view.setup(city, color)
	city_views[city.city_id] = view
	map_view.update_territory_display()
	_update_views_fog_visibility()
	var is_visible = (city.faction_id == GameEnums.FactionId.SOLARIS_DOMINION) or _is_tile_visible_to_player(city.grid_pos)
	if audio_manager and is_visible:
		audio_manager.play_city_founded()

func _on_city_captured(city: CityData, _old_faction_id: int, new_faction_id: int) -> void:
	if city_views.has(city.city_id):
		var new_color = game_state.faction_colors.get(new_faction_id, Color.WHITE)
		city_views[city.city_id].setup(city, new_color)
	map_view.update_territory_display()

func _on_city_razed(city: CityData, _conqueror_faction_id: int) -> void:
	if city_views.has(city.city_id):
		var view = city_views[city.city_id]
		city_views.erase(city.city_id)
		view.queue_free()
	map_view.update_territory_display()

func _refresh_all_views() -> void:
	for view in unit_views.values():
		view.update_display()
	for view in city_views.values():
		view.update_display()
	map_view.render_full_map()
	map_view.update_territory_display()
	_update_views_fog_visibility()

# =============================================================
# SAVE / LOAD IMPLEMENTATION
# =============================================================

func _load_saved_game() -> void:
	var data: Dictionary = SaveManager.load_game()
	if data.is_empty():
		_initialize_fresh_game()
		return

	# 1. Reconstruct Grid Model
	var map_width = int(data["map_width"])
	var map_height = int(data["map_height"])
	var grid_model = GridModel.new()
	grid_model.initialize(map_width, map_height)

	# Biome cache
	var biomes_map = {
		GameEnums.BiomeType.PLAINS: load("res://resources/biomes/plains.tres"),
		GameEnums.BiomeType.HILLS: load("res://resources/biomes/hills.tres"),
		GameEnums.BiomeType.MOUNTAINS: load("res://resources/biomes/mountains.tres"),
		GameEnums.BiomeType.OCEAN: load("res://resources/biomes/ocean.tres"),
		GameEnums.BiomeType.TUNDRA: load("res://resources/biomes/tundra.tres"),
	}

	# Improvement cache
	var imp_map = {
		"farm": load("res://resources/improvements/farm.tres"),
		"mine": load("res://resources/improvements/mine.tres"),
		"encampment": load("res://resources/improvements/encampment.tres"),
		"science_camp": load("res://resources/improvements/science_camp.tres"),
		"market": load("res://resources/improvements/market.tres"),
		"aqueduct": load("res://resources/improvements/aqueduct.tres"),
		"castle": load("res://resources/improvements/castle.tres"),
		"pasture": load("res://resources/improvements/pasture.tres"),
		"neighborhood": load("res://resources/improvements/neighborhood.tres"),
		"border_wall": load("res://resources/improvements/border_wall.tres"),
		"temporary_camp": load("res://resources/improvements/temporary_camp.tres"),
		"harbor": load("res://resources/improvements/harbor.tres"),
	}

	# Resource cache
	var res_map = {
		"rice": load("res://resources/strategic_resources/rice.tres"),
		"iron": load("res://resources/strategic_resources/iron.tres"),
		"horses": load("res://resources/strategic_resources/horses.tres"),
		"gold_ore": load("res://resources/strategic_resources/gold_ore.tres"),
		"gems": load("res://resources/strategic_resources/gems.tres"),
		"niter": load("res://resources/strategic_resources/niter.tres"),
	}

	for t_data in data.get("tiles", []):
		var coords: Vector2i
		if t_data.has("pos"):
			coords = Vector2i(int(t_data["pos"][0]), int(t_data["pos"][1]))
		else:
			coords = Vector2i(int(t_data.get("x", 0)), int(t_data.get("y", 0)))
		var b_val = t_data.get("biome", 1)
		var b_type: GameEnums.BiomeType
		if typeof(b_val) == TYPE_STRING:
			match str(b_val).to_lower():
				"ocean": b_type = GameEnums.BiomeType.OCEAN
				"hills": b_type = GameEnums.BiomeType.HILLS
				"mountains": b_type = GameEnums.BiomeType.MOUNTAINS
				"tundra": b_type = GameEnums.BiomeType.TUNDRA
				_: b_type = GameEnums.BiomeType.PLAINS
		else:
			b_type = int(b_val) as GameEnums.BiomeType
		var b_data = biomes_map.get(b_type, biomes_map[GameEnums.BiomeType.PLAINS])
		var tile = grid_model.set_tile(coords, b_data)
		tile.elevation = float(t_data.get("elev", 0.0))
		tile.owner_faction_id = int(t_data.get("owner", -1))
		tile.city_id = int(t_data.get("city", -1))
		tile.unit_id = int(t_data.get("unit", -1))
		tile.natural_science = int(t_data.get("sci", 0))
		tile.science_tag = str(t_data.get("sci_tag", ""))
		tile.has_border_wall = bool(t_data.get("has_border_wall", false))
		tile.border_wall_health = int(t_data.get("border_wall_hp", 50))
		tile.border_wall_max_health = int(t_data.get("border_wall_max_hp", 50))

		var imp_id = str(t_data.get("imp", ""))
		if imp_id != "" and imp_map.has(imp_id):
			tile.improvement_data = imp_map[imp_id]

		var r_id = str(t_data.get("res", ""))
		if r_id != "" and res_map.has(r_id):
			tile.resource_data = res_map[r_id]

		var rev = t_data.get("rev", {})
		if rev is Dictionary:
			for k in rev.keys():
				tile.revealed_by_faction[int(k)] = bool(rev[k])

	# 2. Instantiate Decoupled Simulation Core
	game_state = GameState.new()
	var active_factions = data.get("active_factions", [])
	if not active_factions.is_empty():
		var fac_ints: Array[int] = []
		for f in active_factions:
			fac_ints.append(int(f))
		game_state.factions = fac_ints
	game_state.initialize(grid_model)
	game_state.next_unit_id = int(data.get("next_unit_id", 1))
	game_state.next_city_id = int(data.get("next_city_id", 1))
	game_state.barbarian_spawn_turn = int(data.get("barbarian_spawn_turn", 0))

	turn_manager = TurnManager.new(game_state)
	turn_manager.current_turn = int(data.get("current_turn", 1))
	turn_manager.current_phase = int(data.get("current_phase", 0)) as GameEnums.TurnPhase

	# Restore Faction Gold
	var gold_data = data.get("faction_gold", {})
	for f_str in gold_data.keys():
		game_state.faction_gold[int(f_str)] = int(gold_data[f_str])

	# Setup presentation
	map_view.initialize(game_state)
	camera.set_map_dimensions(map_width, map_height, 16)
	input_controller.setup(game_state, turn_manager)
	hud.setup(game_state, turn_manager)
	tech_modal.hide()
	_connect_signals()

	# 3. Restore Tech Research
	if data.has("tech_state"):
		for f_str in data["tech_state"].keys():
			var fac_id = int(f_str)
			var state = data["tech_state"][f_str]
			var researched: Array = []
			for t_id in state.get("researched", ["agriculture"]):
				researched.append(str(t_id))
			game_state.tech_manager.faction_tech_state[fac_id] = {
				"researched": researched,
				"current_tech_id": str(state.get("current_tech_id", "")),
				"accumulated_science": int(state.get("accumulated_science", 0))
			}

	# Restore Diplomacy Relations
	if data.has("diplomacy_relations") and game_state.diplomacy_manager:
		for a_str in data["diplomacy_relations"].keys():
			var a = int(a_str)
			if not game_state.diplomacy_manager.relations.has(a):
				game_state.diplomacy_manager.relations[a] = {}
			for b_str in data["diplomacy_relations"][a_str].keys():
				var b = int(b_str)
				var r_dict = data["diplomacy_relations"][a_str][b_str]
				game_state.diplomacy_manager.relations[a][b] = {
					"status": int(r_dict.get("status", 0)),
					"opinion": int(r_dict.get("opinion", 0)),
					"open_borders": bool(r_dict.get("open_borders", false)),
					"trade_turns": int(r_dict.get("trade_turns", 0))
				}
		var met_data = data.get("diplomacy_met", {})
		for a_str in met_data.keys():
			var a = int(a_str)
			if not game_state.diplomacy_manager.met_factions.has(a):
				game_state.diplomacy_manager.met_factions[a] = {}
			for b_str in met_data[a_str].keys():
				game_state.diplomacy_manager.met_factions[a][int(b_str)] = bool(met_data[a_str][b_str])

	# Restore Barbarian Camps
	game_state.barbarian_camps.clear()
	for cp in data.get("barbarian_camps", []):
		var c_pos = Vector2i(int(cp[0]), int(cp[1]))
		game_state.barbarian_camps.append(c_pos)
		_spawn_camp_marker(c_pos)

	# 4. Restore Cities
	for c_data in data.get("cities", []):
		var city_pos = Vector2i(int(c_data["pos"][0]), int(c_data["pos"][1]))
		var city = CityData.new()
		city.initialize(int(c_data["id"]), str(c_data["name"]), int(c_data["faction"]), city_pos)
		city.health = int(c_data["hp"])
		city.fortification = int(c_data["fort"])
		city.max_health = int(c_data["max_hp"])
		city.max_fortification = int(c_data["max_fort"])
		city.population = int(c_data["pop"])
		city.food_stored = int(c_data["food_stored"])
		city.food_needed = int(c_data["food_needed"])
		city.production_stored = int(c_data["prod_stored"])
		city.current_production_id = str(c_data.get("curr_prod", ""))
		city.production_queue.clear()
		for q_id in c_data.get("prod_queue", []):
			city.production_queue.append(str(q_id))
		city.has_walls = bool(c_data.get("has_walls", false))
		city.has_market = bool(c_data.get("has_market", false))
		city.has_aqueduct = bool(c_data.get("has_aqueduct", false))
		city.has_castle = bool(c_data.get("has_castle", false))
		city.has_harbor = bool(c_data.get("has_harbor", false))
		city.has_encampment = bool(c_data.get("has_encampment", false))
		city.has_science_camp = bool(c_data.get("has_science_camp", false))
		city.has_neighborhood = bool(c_data.get("has_neighborhood", false))
		var ep = c_data.get("encampment_pos", [-1, -1])
		city.encampment_pos = Vector2i(int(ep[0]), int(ep[1]))
		city.encampment_health = int(c_data.get("encampment_health", 100))
		city.encampment_fortification = int(c_data.get("encampment_fortification", 0))
		var scp = c_data.get("science_camp_pos", [-1, -1])
		city.science_camp_pos = Vector2i(int(scp[0]), int(scp[1]))
		var np = c_data.get("neighborhood_pos", [-1, -1])
		city.neighborhood_pos = Vector2i(int(np[0]), int(np[1]))
		var planned = c_data.get("planned_district_tiles", {})
		for d_key in planned.keys():
			city.planned_district_tiles[str(d_key)] = Vector2i(int(planned[d_key][0]), int(planned[d_key][1]))
		var hc = c_data.get("harbor_coord", [-1, -1])
		city.harbor_coord = Vector2i(int(hc[0]), int(hc[1]))
		city.housing_capacity = int(c_data.get("housing", 5))
		city.has_bombarded_this_turn = bool(c_data.get("has_bombarded", false))
		city.garrison_unit_id = int(c_data.get("garrison", -1))

		var terr: Array[Vector2i] = []
		for p in c_data.get("territory", []):
			terr.append(Vector2i(int(p[0]), int(p[1])))
		city.territory_tiles = terr

		game_state.cities[city.city_id] = city
		var c_tile = grid_model.get_tile(city.grid_pos)
		if c_tile:
			c_tile.is_city = true
		var view: CityView = city_view_scene.instantiate()
		city_container.add_child(view)
		var color = game_state.faction_colors.get(city.faction_id, Color.WHITE)
		view.setup(city, color)
		city_views[city.city_id] = view

	# 5. Restore Units
	var unit_res_map = {
		"settler": load("res://resources/units/settler.tres"),
		"builder": load("res://resources/units/builder.tres"),
		"scout": load("res://resources/units/scout.tres"),
		"slinger": load("res://resources/units/slinger.tres"),
		"archer": load("res://resources/units/archer.tres"),
		"spearman": load("res://resources/units/spearman.tres"),
		"swordsman": load("res://resources/units/swordsman.tres"),
		"horseman": load("res://resources/units/horseman.tres"),
		"catapult": load("res://resources/units/catapult.tres"),
		"crossbowman": load("res://resources/units/crossbowman.tres"),
		"knight": load("res://resources/units/knight.tres"),
		"barbarian_raider": load("res://resources/units/barbarian_raider.tres"),
		"barbarian_horseman": load("res://resources/units/barbarian_horseman.tres"),
		"military_engineer": load("res://resources/units/military_engineer.tres"),
		"galley": load("res://resources/units/galley.tres"),
		"quadrireme": load("res://resources/units/quadrireme.tres"),
		"galleass": load("res://resources/units/galleass.tres"),
		"musketman": load("res://resources/units/musketman.tres"),
		"bombard": load("res://resources/units/bombard.tres"),
		"cuirassier": load("res://resources/units/cuirassier.tres"),
		"frigate": load("res://resources/units/frigate.tres")
	}

	var first_player_unit_pos: Vector2i = Vector2i(-1, -1)
	for u_data in data.get("units", []):
		var res_key = str(u_data.get("res", "scout")).to_lower()
		var u_res = unit_res_map.get(res_key, unit_res_map["scout"])
		var u_pos = Vector2i(int(u_data["pos"][0]), int(u_data["pos"][1]))
		var unit = GameState.UnitInstance.new(int(u_data["id"]), u_res, int(u_data["faction"]), u_pos)
		unit.current_health = int(u_data.get("hp", u_res.max_health))
		unit.remaining_mp = int(u_data.get("mp", u_res.max_movement_points))
		unit.build_charges = int(u_data.get("charges", 3))
		unit.has_attacked = bool(u_data.get("attacked", false))
		unit.is_fortified = bool(u_data.get("fortified", false))
		unit.fortify_turns = int(u_data.get("fortify_turns", 0))
		unit.is_embarked = bool(u_data.get("embarked", false))
		unit.is_turn_skipped = bool(u_data.get("skipped", false))
		unit.is_resting_heal = bool(u_data.get("resting", false))
		unit.is_garrisoned = bool(u_data.get("is_garrisoned", false))
		unit.is_automated = bool(u_data.get("is_automated", false))
		game_state.units[unit.instance_id] = unit

		var view: UnitView = unit_view_scene.instantiate()
		unit_container.add_child(view)
		var color = game_state.faction_colors.get(unit.faction_id, Color.WHITE)
		view.setup(unit, color)
		unit_views[unit.instance_id] = view

		if unit.faction_id == GameEnums.FactionId.SOLARIS_DOMINION and first_player_unit_pos == Vector2i(-1, -1):
			first_player_unit_pos = u_pos

	# Restore Espionage Manager
	if data.has("espionage") and game_state.espionage_manager:
		game_state.espionage_manager.deserialize(data["espionage"])

	map_view.update_territory_display()
	game_state.update_fog_of_war(GameEnums.FactionId.SOLARIS_DOMINION)
	_refresh_all_fortification_views()
	_update_views_fog_visibility()

	if first_player_unit_pos != Vector2i(-1, -1):
		camera.focus_on_tile(first_player_unit_pos)

	hud.show_feedback("Loaded saved game: Turn %d." % turn_manager.current_turn, false)
	hud.update_top_bar()
	hud.update_faction_legend()
