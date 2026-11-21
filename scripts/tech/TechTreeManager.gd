class_name TechTreeManager
extends RefCounted

## Manages tech trees, research accumulation, and unlocks per faction

signal tech_researched(faction_id: int, tech: TechNode)

var all_techs: Dictionary = {} # tech_id -> TechNode

# Per-faction state: faction_id -> { "researched": Array[String], "current_tech_id": String, "accumulated_science": int }
var faction_tech_state: Dictionary = {}

func _init() -> void:
	_load_all_techs()

func _load_all_techs() -> void:
	var tech_files = [
		"agriculture", "mining", "archery", "bronze_working",
		"writing", "iron_working", "horse_riding",
		"sailing", "shipbuilding",
		"mathematics", "currency", "construction",
		"machinery", "chivalry", "feudalism", "espionage",
		"gunpowder", "siege_tactics", "military_science", "square_rigging", "diplomatic_service"
	]
	for tid in tech_files:
		var path = "res://resources/techs/%s.tres" % tid
		var tech: TechNode = load(path)
		if tech:
			all_techs[tid] = tech

func initialize_faction(faction_id: int) -> void:
	faction_tech_state[faction_id] = {
		"researched": ["agriculture"], # Start with Agriculture researched
		"current_tech_id": "mining",
		"accumulated_science": 0
	}

func get_researched_techs(faction_id: int) -> Array:
	if not faction_tech_state.has(faction_id):
		return []
	return faction_tech_state[faction_id]["researched"]

func is_tech_researched(faction_id: int, tech_id: String) -> bool:
	return get_researched_techs(faction_id).has(tech_id)

func unlock_tech(faction_id: int, tech_id: String) -> void:
	if not faction_tech_state.has(faction_id):
		initialize_faction(faction_id)
	if not faction_tech_state[faction_id]["researched"].has(tech_id):
		faction_tech_state[faction_id]["researched"].append(tech_id)
		var t_obj = all_techs.get(tech_id, null)
		if t_obj:
			tech_researched.emit(faction_id, t_obj)

func can_research_tech(faction_id: int, tech_id: String) -> bool:
	if is_tech_researched(faction_id, tech_id):
		return false
	var tech = all_techs.get(tech_id, null)
	if not tech:
		return false
	var researched = get_researched_techs(faction_id)
	return tech.is_unlocked_for_faction(researched)

func set_current_research(faction_id: int, tech_id: String) -> bool:
	if not can_research_tech(faction_id, tech_id):
		return false
	faction_tech_state[faction_id]["current_tech_id"] = tech_id
	return true

func add_science_yield(faction_id: int, points: int) -> TechNode:
	if not faction_tech_state.has(faction_id):
		initialize_faction(faction_id)

	var state = faction_tech_state[faction_id]
	var current_id: String = state["current_tech_id"]
	if current_id == "" or not all_techs.has(current_id):
		# Auto pick first available tech
		for tid in all_techs.keys():
			if can_research_tech(faction_id, tid):
				current_id = tid
				state["current_tech_id"] = tid
				break

	if current_id == "" or not all_techs.has(current_id):
		return null # All techs researched

	var tech = all_techs[current_id]
	state["accumulated_science"] += points

	if state["accumulated_science"] >= tech.science_cost:
		state["accumulated_science"] -= tech.science_cost
		state["researched"].append(tech.tech_id)
		state["current_tech_id"] = ""
		tech_researched.emit(faction_id, tech)
		return tech

	return null

func is_unit_unlocked(faction_id: int, unit_id: String) -> bool:
	# Check if unit requires tech
	for tid in all_techs.keys():
		var tech: TechNode = all_techs[tid]
		if tech.unlocked_units.has(unit_id):
			return is_tech_researched(faction_id, tid)
	return true # Default units without tech requirements are unlocked

func is_improvement_unlocked(faction_id: int, improvement_id: String) -> bool:
	for tid in all_techs.keys():
		var tech: TechNode = all_techs[tid]
		if tech.unlocked_improvements.has(improvement_id):
			return is_tech_researched(faction_id, tid)
	return true

func get_highland_move_reduction(faction_id: int) -> int:
	var total_reduction = 0
	for tid in get_researched_techs(faction_id):
		var tech: TechNode = all_techs.get(tid, null)
		if tech:
			total_reduction += tech.highland_move_cost_reduction
	return total_reduction

func get_combat_attack_bonus_percent(faction_id: int) -> int:
	var total = 0
	for tid in get_researched_techs(faction_id):
		var tech: TechNode = all_techs.get(tid, null)
		if tech:
			total += tech.melee_attack_bonus_percent
	return total

func can_faction_embark(faction_id: int) -> bool:
	return is_tech_researched(faction_id, "shipbuilding")

func get_spy_capacity(faction_id: int) -> int:
	var cap = 0
	if is_tech_researched(faction_id, "espionage"):
		cap += 1
	if is_tech_researched(faction_id, "diplomatic_service"):
		cap += 1
	return cap


