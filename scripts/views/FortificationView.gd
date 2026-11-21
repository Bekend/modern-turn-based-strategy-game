class_name FortificationView
extends Node2D

## Visual component displaying dual pixel-art health & wall fortification bars
## for Military Encampments and Temporary Military Outpost Camps.

const CELL_SIZE: float = 16.0

@onready var fort_bar_bg: ColorRect = $FortBarBg
@onready var fort_bar_fill: ColorRect = $FortBarBg/FortBarFill
@onready var hp_bar_bg: ColorRect = $HPBarBg
@onready var hp_bar_fill: ColorRect = $HPBarBg/HPBarFill

var coords: Vector2i = Vector2i(-1, -1)
var fortification_type: GameEnums.ImprovementType = GameEnums.ImprovementType.NONE
var faction_id: int = -1
var active_tween: Tween = null

func _ready() -> void:
	z_index = 4
	for child in find_children("*", "Control", true, false):
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup(p_coords: Vector2i, p_type: GameEnums.ImprovementType, p_faction_id: int) -> void:
	coords = p_coords
	fortification_type = p_type
	faction_id = p_faction_id
	position = Vector2(coords.x * CELL_SIZE + CELL_SIZE * 0.5, coords.y * CELL_SIZE + CELL_SIZE * 0.5)

func _ensure_nodes() -> void:
	if fort_bar_bg == null:
		fort_bar_bg = get_node_or_null("FortBarBg")
	if fort_bar_fill == null and fort_bar_bg:
		fort_bar_fill = fort_bar_bg.get_node_or_null("FortBarFill")
	if hp_bar_bg == null:
		hp_bar_bg = get_node_or_null("HPBarBg")
	if hp_bar_fill == null and hp_bar_bg:
		hp_bar_fill = hp_bar_bg.get_node_or_null("HPBarFill")

func update_display(current_hp: int, max_hp: int, current_fort: int, max_fort: int, has_walls: bool) -> void:
	_ensure_nodes()
	if not hp_bar_fill:
		return
	# 1. Update Core HP Bar
	var m_hp = float(maxi(1, max_hp))
	var hp_pct = clampf(float(current_hp) / m_hp, 0.0, 1.0)
	if current_hp <= 0:
		hp_bar_fill.size.x = 0.0
	else:
		hp_bar_fill.size.x = maxf(1.0, roundf(hp_pct * 10.0))

	if hp_pct > 0.5:
		hp_bar_fill.color = Color("2ecc71") # Green
	elif hp_pct > 0.25:
		hp_bar_fill.color = Color("f1c40f") # Yellow
	else:
		hp_bar_fill.color = Color("e74c3c") # Red

	# 2. Update Wall Fortification Bar (hidden if no walls or 0 max fort)
	if not has_walls or max_fort <= 0:
		fort_bar_bg.hide()
	else:
		var m_fort = float(maxi(1, max_fort))
		var fort_pct = clampf(float(current_fort) / m_fort, 0.0, 1.0)
		fort_bar_bg.show()
		fort_bar_fill.size.x = maxf(0.0, roundf(fort_pct * 10.0))

func play_hit_shake() -> void:
	var base_pos = Vector2(coords.x * CELL_SIZE + CELL_SIZE * 0.5, coords.y * CELL_SIZE + CELL_SIZE * 0.5)
	if active_tween and active_tween.is_valid():
		active_tween.kill()

	active_tween = create_tween()
	active_tween.tween_property(self, "position", base_pos + Vector2(2, 0), 0.04)
	active_tween.tween_property(self, "position", base_pos - Vector2(2, 0), 0.04)
	active_tween.tween_property(self, "position", base_pos + Vector2(1, 0), 0.04)
	active_tween.tween_property(self, "position", base_pos, 0.04)

func update_visibility(player_faction: int, grid_model: GridModel) -> void:
	if faction_id == player_faction:
		visible = true
		return
	if grid_model:
		var tile = grid_model.get_tile(coords)
		if tile:
			visible = tile.visible_by_faction.get(player_faction, false) or tile.revealed_by_faction.get(player_faction, false)
			return
	visible = false
