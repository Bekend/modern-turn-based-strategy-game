@tool
class_name UnitData
extends Resource

## Custom Godot Resource defining base unit attributes and archetypes

@export var id: String = "scout"
@export var unit_name: String = "Scout"
@export var unit_class: GameEnums.UnitClass = GameEnums.UnitClass.RECON

@export_group("Combat Stats")
@export var combat_strength: int = 10
@export var ranged_strength: int = 0
@export var attack_range: int = 1
@export var max_movement_points: int = 3
@export var max_health: int = 100

@export_group("Production & Tech")
@export var production_cost: int = 25
@export var tech_prerequisite: String = ""
@export var strategic_prerequisite: String = "" # e.g. "iron", "horses"
@export var upgrade_unit_id: String = "" # Target unit ID to upgrade into
@export var upgrade_cost: int = 0        # Gold cost to upgrade

@export_group("Special Capabilities")
@export var can_found_city: bool = false
@export var can_build_improvements: bool = false
@export var can_build_military_structures: bool = false
@export var is_naval: bool = false
@export var sight_range: int = 2

@export_group("Visuals")
@export var color_tint: Color = Color("3895d3")
@export var icon_symbol: String = "⚡"

func is_civilian() -> bool:
	return unit_class == GameEnums.UnitClass.CIVILIAN

func is_ranged() -> bool:
	return (unit_class == GameEnums.UnitClass.RANGED or unit_class == GameEnums.UnitClass.NAVAL_RANGED or ranged_strength > 0) and attack_range >= 1

func is_naval_unit() -> bool:
	return is_naval or unit_class == GameEnums.UnitClass.NAVAL_MELEE or unit_class == GameEnums.UnitClass.NAVAL_RANGED

func get_summary() -> String:
	if is_civilian():
		return "%s (Civilian | MP: %d)" % [unit_name, max_movement_points]
	elif is_ranged():
		return "%s (Ranged Str: %d | Rng: %d | MP: %d)" % [unit_name, ranged_strength, attack_range, max_movement_points]
	else:
		return "%s (Melee Str: %d | MP: %d)" % [unit_name, combat_strength, max_movement_points]
