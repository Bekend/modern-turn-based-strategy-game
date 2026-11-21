@tool
class_name ImprovementData
extends Resource

@export var id: String = "farm"
@export var improvement_name: String = "Farm"
@export var improvement_type: GameEnums.ImprovementType = GameEnums.ImprovementType.FARM
@export var food_bonus: int = 2
@export var production_bonus: int = 0
@export var science_bonus: int = 0
@export var gold_bonus: int = 0
@export var defense_bonus_percent: int = 0
@export var adds_defensive_range: int = 0
@export var trains_advanced_units: bool = false
@export var build_turns: int = 2
@export var required_tech: String = "agriculture"
@export var valid_biomes: Array[GameEnums.BiomeType] = [GameEnums.BiomeType.PLAINS]
@export var icon_color: Color = Color("98b832")
@export var health: int = 50
@export var max_health: int = 50
@export var fortification: int = 0
@export var max_fortification: int = 0
@export var has_walls: bool = false
@export var bombard_strength: int = 16
@export var bombard_range: int = 2
@export var has_bombarded_this_turn: bool = false

