class_name SaveManager
extends RefCounted

## Manages saving and loading game state to user://savegame.dat

const SAVE_PATH: String = "user://savegame.dat"

static func save_exists() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

static func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

static func save_game(game_state: GameState, turn_manager: TurnManager) -> bool:
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		push_error("Failed to open save file for writing: " + SAVE_PATH)
		return false

	var cfg = Engine.get_main_loop().root.get_node_or_null("/root/GameConfig")

	var data: Dictionary = {
		"version": 2,
		"current_turn": turn_manager.current_turn,
		"current_phase": turn_manager.current_phase,
		"map_width": game_state.grid_model.width,
		"map_height": game_state.grid_model.height,
		"map_size_choice": cfg.map_size_index if cfg else 1,
		"ai_count": cfg.ai_count if cfg else 2,
		"active_factions": game_state.factions,
		"next_unit_id": game_state.next_unit_id,
		"next_city_id": game_state.next_city_id,
	}

	# Serialize Tiles
	var tiles_data: Array = []
	for y in range(game_state.grid_model.height):
		for x in range(game_state.grid_model.width):
			var pos = Vector2i(x, y)
			var tile = game_state.grid_model.get_tile(pos)
			if tile:
				var r_id = ""
				if tile.resource_data:
					r_id = tile.resource_data.resource_name.to_lower().replace(" ", "_")

				var i_id = ""
				if tile.improvement_data:
					match tile.improvement_data.improvement_type:
						GameEnums.ImprovementType.FARM: i_id = "farm"
						GameEnums.ImprovementType.MINE: i_id = "mine"
						GameEnums.ImprovementType.PASTURE: i_id = "pasture"
						GameEnums.ImprovementType.MILITARY_ENCAMPMENT: i_id = "encampment"
						GameEnums.ImprovementType.SCIENCE_CAMP: i_id = "science_camp"
						GameEnums.ImprovementType.MARKET: i_id = "market"
						GameEnums.ImprovementType.AQUEDUCT: i_id = "aqueduct"
						GameEnums.ImprovementType.CASTLE: i_id = "castle"
						GameEnums.ImprovementType.NEIGHBORHOOD: i_id = "neighborhood"
						GameEnums.ImprovementType.BORDER_WALL: i_id = "border_wall"
						GameEnums.ImprovementType.TEMPORARY_CAMP: i_id = "temporary_camp"
						GameEnums.ImprovementType.HARBOR: i_id = "harbor"

				tiles_data.append({
					"x": x, "y": y,
					"pos": [x, y],
					"biome": int(tile.biome_data.biome_type),
					"elev": float(tile.elevation),
					"res": r_id,
					"imp": i_id,
					"owner": tile.owner_faction_id,
					"city": tile.city_id,
					"unit": tile.unit_id,
					"sci": tile.natural_science,
					"sci_tag": tile.science_tag,
					"has_border_wall": tile.has_border_wall,
					"border_wall_hp": tile.border_wall_health,
					"border_wall_max_hp": tile.border_wall_max_health,
					"rev": tile.revealed_by_faction
				})
	data["tiles"] = tiles_data

	# Serialize Units
	var units_data: Array = []
	# Supported unit IDs: settler, builder, scout, slinger, archer, swordsman, horseman, catapult, musketman, bombard
	for u in game_state.units.values():
		var u_res = u.data.id if (u.data and u.data.id != "") else u.data.unit_name.to_lower().replace(" ", "_")

		units_data.append({
			"id": u.instance_id,
			"res": u_res,
			"faction": u.faction_id,
			"pos": [u.grid_pos.x, u.grid_pos.y],
			"hp": u.current_health,
			"mp": u.remaining_mp,
			"charges": u.build_charges,
			"attacked": u.has_attacked,
			"fortified": u.is_fortified,
			"fortify_turns": u.fortify_turns,
			"embarked": u.is_embarked,
			"skipped": u.is_turn_skipped,
			"resting": u.is_resting_heal,
			"is_garrisoned": u.is_garrisoned,
			"is_automated": u.is_automated
		})
	data["units"] = units_data

	# Serialize Cities
	var cities_data: Array = []
	for c in game_state.cities.values():
		var terr_coords: Array = []
		for t in c.territory_tiles:
			terr_coords.append([t.x, t.y])

		var planned_dict: Dictionary = {}
		for p_k in c.planned_district_tiles.keys():
			var p_v = c.planned_district_tiles[p_k]
			planned_dict[str(p_k)] = [p_v.x, p_v.y]

		cities_data.append({
			"id": c.city_id,
			"faction": c.faction_id,
			"name": c.city_name,
			"pos": [c.grid_pos.x, c.grid_pos.y],
			"hp": c.health,
			"fort": c.fortification,
			"max_hp": c.max_health,
			"max_fort": c.max_fortification,
			"pop": c.population,
			"food_stored": c.food_stored,
			"food_needed": c.food_needed,
			"prod_stored": c.production_stored,
			"curr_prod": c.current_production_id,
			"prod_queue": c.production_queue,
			"has_walls": c.has_walls,
			"has_market": c.has_market,
			"has_aqueduct": c.has_aqueduct,
			"has_castle": c.has_castle,
			"has_harbor": c.has_harbor,
			"has_encampment": c.has_encampment,
			"has_science_camp": c.has_science_camp,
			"has_neighborhood": c.has_neighborhood,
			"encampment_pos": [c.encampment_pos.x, c.encampment_pos.y],
			"encampment_health": c.encampment_health,
			"encampment_fortification": c.encampment_fortification,
			"science_camp_pos": [c.science_camp_pos.x, c.science_camp_pos.y],
			"neighborhood_pos": [c.neighborhood_pos.x, c.neighborhood_pos.y],
			"planned_district_tiles": planned_dict,
			"harbor_coord": [c.harbor_coord.x, c.harbor_coord.y],
			"has_bombarded": c.has_bombarded_this_turn,
			"housing": c.housing_capacity,
			"territory": terr_coords,
			"garrison": c.garrison_unit_id
		})
	data["cities"] = cities_data

	# Serialize Faction Gold & Camps
	data["faction_gold"] = game_state.faction_gold
	data["barbarian_spawn_turn"] = game_state.barbarian_spawn_turn
	var camps_arr: Array = []
	for cp in game_state.barbarian_camps:
		camps_arr.append([cp.x, cp.y])
	data["barbarian_camps"] = camps_arr

	# Serialize Tech Manager
	if game_state.tech_manager:
		data["tech_state"] = game_state.tech_manager.faction_tech_state

	# Serialize Diplomacy Manager
	if game_state.diplomacy_manager:
		data["diplomacy_relations"] = game_state.diplomacy_manager.relations
		data["diplomacy_met"] = game_state.diplomacy_manager.met_factions
		data["diplomacy_deals"] = game_state.diplomacy_manager.active_export_deals

	# Serialize Espionage Manager
	if game_state.espionage_manager:
		data["espionage"] = game_state.espionage_manager.serialize()

	file.store_string(JSON.stringify(data))
	file.close()
	return true

static func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return {}
	var json_str = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(json_str)
	if parsed is Dictionary:
		return parsed
	return {}
