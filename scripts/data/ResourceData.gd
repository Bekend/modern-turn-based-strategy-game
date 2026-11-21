@tool
class_name ResourceData
extends Resource

@export var id: String = "rice"
@export var display_name: String = "Rice"
@export var resource_type: GameEnums.StrategicResourceType = GameEnums.StrategicResourceType.RICE
@export var food_bonus: int = 2
@export var production_bonus: int = 0
@export var science_bonus: int = 0
@export var gold_bonus: int = 0
@export var required_tech: String = "agriculture"
@export var is_strategic: bool = false
@export var icon_color: Color = Color("e0c345")
@export var symbol_char: String = "🌾"
