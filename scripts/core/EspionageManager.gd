class_name EspionageManager
extends RefCounted

## Manages covert spy agents, clandestine assignments, foreign surveillance,
## and probability-based sabotage and rebellion operations.

signal agent_recruited(agent: SpyAgent)
signal agent_assigned(agent: SpyAgent, city_id: int)
signal agent_mission_started(agent: SpyAgent, mission_name: String)
signal agent_mission_completed(agent: SpyAgent, mission_name: String, success: bool, captured: bool)
signal surveillance_updated(observer_faction_id: int, target_faction_id: int, turns_left: int)
signal espionage_feedback(text: String, is_warning: bool)

class SpyAgent:
	var id: int
	var name: String
	var faction_id: int
	var home_city_id: int
	var current_city_id: int
	var target_faction_id: int = -1
	var state: String = "idle" # "idle", "traveling", "established", "operating"
	var current_mission: String = "none"
	var turns_remaining: int = 0
	var target_coord: Vector2i = Vector2i(-1, -1)

	func _init(p_id: int, p_name: String, p_faction: int, p_city: int) -> void:
		id = p_id
		name = p_name
		faction_id = p_faction
		home_city_id = p_city
		current_city_id = p_city
		state = "idle"

var game_state: GameState
var next_agent_id: int = 1
var spies: Dictionary = {} # faction_id -> Array[SpyAgent]
var surveillance_turns: Dictionary = {} # observer_faction -> { target_faction: turns }

const TRAVEL_TURNS: int = 3
const MISSION_TURNS: int = 3
const SURVEILLANCE_DURATION: int = 5

const AGENT_CODENAMES = [
	"Agent Shadow", "Agent Raven", "Agent Cipher", "Agent Ghost",
	"Agent Viper", "Agent Falcon", "Agent Mirage", "Agent Specter"
]

func _init(p_game_state: GameState = null) -> void:
	game_state = p_game_state

func get_spies(faction_id: int) -> Array:
	return spies.get(faction_id, [])

func get_spy_capacity(faction_id: int) -> int:
	if not game_state or not game_state.tech_manager:
		return 0
	var cap = 0
	if game_state.tech_manager.is_tech_researched(faction_id, "espionage"):
		cap += 1
	if game_state.tech_manager.is_tech_researched(faction_id, "diplomatic_service"):
		cap += 1
	return cap

func can_produce_spy(faction_id: int) -> bool:
	var cap = get_spy_capacity(faction_id)
	if cap <= 0:
		return false
	var current_count = get_spies(faction_id).size()
	var producing_count = 0
	if game_state:
		for c in game_state.get_faction_cities(faction_id):
			if c.current_production_id == "spy":
				producing_count += 1
	return (current_count + producing_count) < cap

func recruit_agent(faction_id: int, city_id: int) -> SpyAgent:
	if not spies.has(faction_id):
		spies[faction_id] = []
	var name_idx = (next_agent_id - 1) % AGENT_CODENAMES.size()
	var agent_name = "%s %d" % [AGENT_CODENAMES[name_idx], next_agent_id]
	var agent = SpyAgent.new(next_agent_id, agent_name, faction_id, city_id)
	next_agent_id += 1
	spies[faction_id].append(agent)
	agent_recruited.emit(agent)
	return agent

func travel_to_city(agent: SpyAgent, target_city_id: int) -> bool:
	if not game_state:
		return false
	var target_city = game_state.cities.get(target_city_id, null)
	if not target_city:
		return false
	agent.current_city_id = target_city_id
	agent.target_faction_id = target_city.faction_id
	agent.state = "traveling"
	agent.current_mission = "none"
	agent.turns_remaining = TRAVEL_TURNS
	agent_assigned.emit(agent, target_city_id)
	return true

func travel_to_faction(agent: SpyAgent, target_faction_id: int) -> bool:
	if not game_state:
		return false
	var target_cities = game_state.get_faction_cities(target_faction_id)
	var target_city_id = -1
	if not target_cities.is_empty():
		target_city_id = target_cities[0].city_id
	agent.current_city_id = target_city_id
	agent.target_faction_id = target_faction_id
	agent.state = "traveling"
	agent.current_mission = "none"
	agent.turns_remaining = TRAVEL_TURNS
	agent_assigned.emit(agent, target_city_id)
	return true

func start_mission(agent: SpyAgent, mission_name: String) -> bool:
	if agent.state != "established":
		return false
	var valid_missions = ["find_cities", "locate_units", "pillage_encampment", "incite_rebellion"]
	if not valid_missions.has(mission_name):
		return false

	if mission_name in ["pillage_encampment", "incite_rebellion"]:
		var enc_coord = _find_target_encampment(agent.target_faction_id)
		if enc_coord == Vector2i(-1, -1):
			return false
		agent.target_coord = enc_coord

	agent.state = "operating"
	agent.current_mission = mission_name
	agent.turns_remaining = MISSION_TURNS
	agent_mission_started.emit(agent, mission_name)
	return true

func _find_target_encampment(target_faction_id: int) -> Vector2i:
	if not game_state or not game_state.grid_model:
		return Vector2i(-1, -1)
	for y in range(game_state.grid_model.height):
		for x in range(game_state.grid_model.width):
			var pos = Vector2i(x, y)
			var tile = game_state.grid_model.get_tile(pos)
			if tile and tile.owner_faction_id == target_faction_id:
				if tile.improvement_data and tile.improvement_data.improvement_type == GameEnums.ImprovementType.MILITARY_ENCAMPMENT:
					return pos
	return Vector2i(-1, -1)

func has_active_surveillance(observer_faction_id: int, target_faction_id: int) -> bool:
	if surveillance_turns.has(observer_faction_id):
		return surveillance_turns[observer_faction_id].get(target_faction_id, 0) > 0
	return false

func process_turn() -> void:
	for obs in surveillance_turns.keys():
		for tgt in surveillance_turns[obs].keys():
			if surveillance_turns[obs][tgt] > 0:
				surveillance_turns[obs][tgt] -= 1
				surveillance_updated.emit(obs, tgt, surveillance_turns[obs][tgt])

	for fac_id in spies.keys():
		var agents_to_remove: Array = []
		for agent in spies[fac_id]:
			if agent.state == "traveling":
				agent.turns_remaining -= 1
				if agent.turns_remaining <= 0:
					agent.state = "established"
					agent.turns_remaining = 0
					if agent.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
						var cname = _get_city_name(agent.current_city_id)
						espionage_feedback.emit("🕵️ %s established intelligence network in %s!" % [agent.name, cname], false)

			elif agent.state == "operating":
				agent.turns_remaining -= 1
				if agent.turns_remaining <= 0:
					var survived = _resolve_mission(agent)
					if not survived:
						agents_to_remove.append(agent)

		for dead_agent in agents_to_remove:
			spies[fac_id].erase(dead_agent)

func _resolve_mission(agent: SpyAgent) -> bool:
	var roll = randi_range(1, 100)
	var mission = agent.current_mission
	var survived = true
	var success = false

	match mission:
		"find_cities":
			# 95% Success, 5% Failure without death
			if roll <= 95:
				success = true
				_execute_find_city(agent)
				if agent.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
					espionage_feedback.emit("🕵️ %s SUCCESS: Found an uncharted enemy city!" % agent.name, false)
			else:
				if agent.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
					espionage_feedback.emit("🕵️ %s: Operation failed to locate new cities. Agent safe." % agent.name, true)

		"locate_units":
			# 95% Success, 5% Failure without death (reveals all units for 5 turns)
			if roll <= 95:
				success = true
				if not surveillance_turns.has(agent.faction_id):
					surveillance_turns[agent.faction_id] = {}
				surveillance_turns[agent.faction_id][agent.target_faction_id] = SURVEILLANCE_DURATION
				if agent.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
					var target_name = game_state.get_faction_name(agent.target_faction_id)
					espionage_feedback.emit("🕵️ %s SUCCESS: Satellite surveillance active on %s forces for 5 turns!" % [agent.name, target_name], false)
			else:
				if agent.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
					espionage_feedback.emit("🕵️ %s: Surveillance counter-measures detected. Mission failed." % agent.name, true)

		"pillage_encampment":
			# 60% Success, 15% Death, 25% Not Succeeding
			if roll <= 60:
				success = true
				_execute_pillage_encampment(agent)
				if agent.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
					espionage_feedback.emit("🕵️ %s SUCCESS: Enemy Military Encampment sabotaged and destroyed!" % agent.name, false)
			elif roll <= 75: # 61 to 75 = 15%
				survived = false
				if agent.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
					espionage_feedback.emit("☠️ %s was captured and executed during the sabotage mission!" % agent.name, true)
			else: # 76 to 100 = 25%
				if agent.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
					espionage_feedback.emit("🕵️ %s: Sabotage thwarted by encampment guards. Agent escaped!" % agent.name, true)

		"incite_rebellion":
			# 40% Success, 25% Death, 35% Not Succeeding
			if roll <= 40:
				success = true
				_execute_incite_rebellion(agent)
				if agent.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
					espionage_feedback.emit("🔥 %s SUCCESS: Armed rebellion incited! Barbarian rebels are assaulting the encampment!" % agent.name, false)
			elif roll <= 65: # 41 to 65 = 25%
				survived = false
				if agent.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
					espionage_feedback.emit("☠️ %s was betrayed and executed by royal inquisitors!" % agent.name, true)
			else: # 66 to 100 = 35%
				if agent.faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
					espionage_feedback.emit("🕵️ %s: Rebellion was suppressed before uprising could form. Agent fled safely." % agent.name, true)

	if survived:
		agent.state = "established"
		agent.current_mission = "none"
		agent.turns_remaining = 0

	agent_mission_completed.emit(agent, mission, success, not survived)
	return survived

func _execute_find_city(agent: SpyAgent) -> void:
	if not game_state or not game_state.grid_model: return
	for c in game_state.cities.values():
		if c.faction_id == agent.target_faction_id:
			if not c.discovered_by_faction.get(agent.faction_id, false):
				c.discovered_by_faction[agent.faction_id] = true
				game_state.grid_model.reveal_tile(c.grid_pos, agent.faction_id)
				for n in game_state.grid_model.get_neighbors(c.grid_pos):
					game_state.grid_model.reveal_tile(n, agent.faction_id)
				if agent.current_city_id == -1:
					agent.current_city_id = c.city_id
				game_state.update_fog_of_war(agent.faction_id)
				break

func _execute_pillage_encampment(agent: SpyAgent) -> void:
	if not game_state or not game_state.grid_model: return
	var pos = agent.target_coord
	if pos == Vector2i(-1, -1):
		pos = _find_target_encampment(agent.target_faction_id)
	if pos != Vector2i(-1, -1):
		var tile = game_state.grid_model.get_tile(pos)
		if tile:
			tile.improvement_data = null
			game_state.grid_model.emit_tile_updated(pos)

func _execute_incite_rebellion(agent: SpyAgent) -> void:
	if not game_state or not game_state.grid_model: return
	var center = agent.target_coord
	if center == Vector2i(-1, -1):
		center = _find_target_encampment(agent.target_faction_id)
	if center == Vector2i(-1, -1):
		var c = game_state.cities.get(agent.current_city_id, null)
		if c: center = c.grid_pos
		else: return

	var target_fac = agent.target_faction_id
	var is_renaissance = game_state.tech_manager.is_tech_researched(target_fac, "gunpowder")
	var is_medieval = game_state.tech_manager.is_tech_researched(target_fac, "feudalism") or game_state.tech_manager.is_tech_researched(target_fac, "iron_working")
	var is_classical = game_state.tech_manager.is_tech_researched(target_fac, "bronze_working")

	var melee_res_id = "barbarian_raider"
	var ranged_res_id = "slinger"

	if is_renaissance:
		melee_res_id = "musketman"
		ranged_res_id = "bombard"
	elif is_medieval:
		melee_res_id = "spearman"
		ranged_res_id = "crossbowman"
	elif is_classical:
		melee_res_id = "swordsman"
		ranged_res_id = "archer"

	var spawn_queue = [melee_res_id, ranged_res_id, ranged_res_id]
	var unit_res_map = {
		"barbarian_raider": load("res://resources/units/barbarian_raider.tres"),
		"slinger": load("res://resources/units/slinger.tres"),
		"archer": load("res://resources/units/archer.tres"),
		"swordsman": load("res://resources/units/swordsman.tres"),
		"spearman": load("res://resources/units/spearman.tres"),
		"crossbowman": load("res://resources/units/crossbowman.tres"),
		"musketman": load("res://resources/units/musketman.tres"),
		"bombard": load("res://resources/units/bombard.tres"),
	}

	var candidates = game_state.grid_model.get_all_tiles_in_radius(center, 2)
	var spawned_count = 0

	for pos in candidates:
		if spawned_count >= spawn_queue.size():
			break
		if pos == center:
			continue
		var tile = game_state.grid_model.get_tile(pos)
		if not tile or not tile.biome_data.is_passable:
			continue
		if game_state.get_unit_at(pos) != null:
			continue

		var u_id = spawn_queue[spawned_count]
		var u_res = unit_res_map.get(u_id, unit_res_map["barbarian_raider"])
		var barb_u = GameState.UnitInstance.new(game_state.next_unit_id, u_res, GameEnums.FactionId.BARBARIANS, pos)
		game_state.next_unit_id += 1
		game_state.units[barb_u.instance_id] = barb_u
		game_state.unit_spawned.emit(barb_u)
		spawned_count += 1

func _get_city_name(city_id: int) -> String:
	if game_state and game_state.cities.has(city_id):
		return game_state.cities[city_id].city_name
	return "Foreign City"

func serialize() -> Dictionary:
	var spies_arr: Array = []
	for fac in spies.keys():
		for a in spies[fac]:
			spies_arr.append({
				"id": a.id,
				"name": a.name,
				"fac": a.faction_id,
				"home": a.home_city_id,
				"city": a.current_city_id,
				"tgt_fac": a.target_faction_id,
				"state": a.state,
				"mission": a.current_mission,
				"turns": a.turns_remaining,
				"coord": [a.target_coord.x, a.target_coord.y]
			})
	return {
		"next_id": next_agent_id,
		"spies": spies_arr,
		"surveillance": surveillance_turns
	}

func deserialize(data: Dictionary) -> void:
	spies.clear()
	surveillance_turns.clear()
	next_agent_id = int(data.get("next_id", 1))

	var surv_data = data.get("surveillance", {})
	for obs in surv_data.keys():
		surveillance_turns[int(obs)] = {}
		for tgt in surv_data[obs].keys():
			surveillance_turns[int(obs)][int(tgt)] = int(surv_data[obs][tgt])

	for s_data in data.get("spies", []):
		var agent = SpyAgent.new(
			int(s_data["id"]),
			str(s_data["name"]),
			int(s_data["fac"]),
			int(s_data["home"])
		)
		agent.current_city_id = int(s_data["city"])
		agent.target_faction_id = int(s_data["tgt_fac"])
		agent.state = str(s_data["state"])
		agent.current_mission = str(s_data["mission"])
		agent.turns_remaining = int(s_data["turns"])
		var c = s_data.get("coord", [-1, -1])
		agent.target_coord = Vector2i(int(c[0]), int(c[1]))

		if not spies.has(agent.faction_id):
			spies[agent.faction_id] = []
		spies[agent.faction_id].append(agent)
