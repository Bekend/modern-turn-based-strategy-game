@tool
class_name TechNode
extends Resource

## Data class representing a technology node in the tech tree

@export var tech_id: String = "agriculture"
@export var title: String = "Agriculture"
@export_multiline var description: String = "Allows farming and basic food surplus collection."
@export var science_cost: int = 20
@export var tier: int = 1
@export var era: String = "Ancient"

## Array of prerequisite tech IDs that must be researched first
@export var prerequisites: Array[String] = []

## Unlocks
@export var unlocked_units: Array[String] = [] # e.g. ["slinger", "swordsman"]
@export var unlocked_improvements: Array[String] = [] # e.g. ["farm", "military_encampment", "science_camp"]
@export var reveals_strategic_resource: String = "" # e.g. "iron", "horses"

## Movement / Combat Perks
@export var highland_move_cost_reduction: int = 0 # If 1, highlands cost 1 MP instead of 2
@export var melee_attack_bonus_percent: int = 0
@export var defense_bonus_percent: int = 0

## UI Tree Positioning (for Visual Tech Tree Modal)
@export var tree_column: int = 0 # X position in tech graph
@export var tree_row: int = 0    # Y position in tech graph

func is_unlocked_for_faction(researched_tech_ids: Array) -> bool:
	for req_id in prerequisites:
		if not researched_tech_ids.has(req_id):
			return false
	return true
