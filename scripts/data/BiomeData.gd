@tool
class_name BiomeData
extends Resource

@export var id: String = "plains"
@export var biome_name: String = "Plains"
@export var biome_type: GameEnums.BiomeType = GameEnums.BiomeType.PLAINS
@export var move_cost: int = 1
@export var defense_bonus_percent: int = 0
@export var is_passable: bool = true
@export var yield_food: int = 2
@export var yield_production: int = 1
@export var yield_science: int = 0
@export var color_tint: Color = Color("4b8a3e")
@export var description: String = "Open fertile terrain ideal for farming and rapid maneuvering."
