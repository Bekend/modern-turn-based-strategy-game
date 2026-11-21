class_name UnitView
extends Node2D

## Visual representation of a field unit with retro 8-bit token,
## health bar, remaining MP pips, and smooth movement tweening.

const CELL_SIZE: int = 16

var unit_id: int
var faction_id: int
var grid_coords: Vector2i
var unit_instance: GameState.UnitInstance

@onready var sprite_label: Label = $Token/Glyph
@onready var token_rect: ColorRect = $Token
@onready var token_border: ColorRect = $TokenBorder
@onready var faction_dot: ColorRect = $Token/FactionDot
@onready var hp_bar_bg: ColorRect = $HPBarBg
@onready var hp_bar_fill: ColorRect = $HPBarBg/HPBarFill

var active_tween: Tween

func _ready() -> void:
	for child in find_children("*", "Control", true, false):
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

func get_target_position(coords: Vector2i) -> Vector2:
	if unit_instance and unit_instance.is_garrisoned:
		return Vector2(coords.x * CELL_SIZE + 4.0, coords.y * CELL_SIZE + 4.0)
	return Vector2(coords.x * CELL_SIZE + CELL_SIZE * 0.5, coords.y * CELL_SIZE + CELL_SIZE * 0.5)

func setup(p_instance: GameState.UnitInstance, faction_color: Color) -> void:
	unit_instance = p_instance
	unit_id = p_instance.instance_id
	faction_id = p_instance.faction_id
	grid_coords = p_instance.grid_pos

	position = get_target_position(grid_coords)
	if unit_instance.is_garrisoned:
		scale = Vector2(0.6, 0.6)
		z_index = 2
	else:
		scale = Vector2(1.0, 1.0)
		z_index = 1

	token_rect.color = faction_color
	sprite_label.text = p_instance.data.icon_symbol

	# Faction identifier dot
	if faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
		faction_dot.color = Color.WHITE
	elif faction_id == GameEnums.FactionId.BARBARIANS:
		faction_dot.color = Color("b5179e")
	else:
		faction_dot.color = Color("f1c40f")

	update_display()

func update_visibility(player_faction: int = GameEnums.FactionId.SOLARIS_DOMINION, grid_model: GridModel = null) -> void:
	if not unit_instance:
		return
	if unit_instance.faction_id == player_faction:
		visible = true
	elif grid_model:
		var tile = grid_model.get_tile(grid_coords)
		if tile:
			visible = tile.visible_by_faction.get(player_faction, false)
		else:
			visible = false

func update_view() -> void:
	update_display()

func update_display() -> void:
	if not unit_instance:
		return

	# Handle garrison scaling, z_index, and positioning
	if unit_instance.is_garrisoned:
		scale = Vector2(0.6, 0.6)
		z_index = 2
		position = Vector2(grid_coords.x * CELL_SIZE + 4.0, grid_coords.y * CELL_SIZE + 4.0)
	else:
		scale = Vector2(1.0, 1.0)
		z_index = 1

	if sprite_label and unit_instance.data:
		sprite_label.text = unit_instance.data.icon_symbol

	# Update Pixel-Art HP Bar
	var max_hp = float(maxi(1, unit_instance.data.max_health))
	var pct = clampf(float(unit_instance.current_health) / max_hp, 0.0, 1.0)
	
	if unit_instance.current_health <= 0:
		hp_bar_fill.size.x = 0.0
	else:
		hp_bar_fill.size.x = maxf(1.0, roundf(pct * 10.0))

	# HP bar color grading
	if pct > 0.5:
		hp_bar_fill.color = Color("2ecc71") # Crisp Green
	elif pct > 0.25:
		hp_bar_fill.color = Color("f1c40f") # Vivid Yellow
	else:
		hp_bar_fill.color = Color("e74c3c") # Alert Red

	# Dim unit when turn moves are exhausted
	if unit_instance.remaining_mp <= 0:
		modulate = Color(0.55, 0.55, 0.65, 0.75)
	else:
		modulate = Color(1.0, 1.0, 1.0, 1.0)

func move_to_tile(new_coords: Vector2i) -> void:
	grid_coords = new_coords
	var target_pos = get_target_position(new_coords)
	
	if active_tween and active_tween.is_valid():
		active_tween.kill()

	active_tween = create_tween()
	active_tween.tween_property(self, "position", target_pos, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	active_tween.tween_callback(update_display)

func play_attack_animation(target_coords: Vector2i, will_advance: bool = false) -> void:
	var base_pos = get_target_position(grid_coords)
	var target_pos = get_target_position(target_coords)

	if active_tween and active_tween.is_valid():
		active_tween.kill()

	# Ranged attackers NEVER advance or step into target tiles
	var is_ranged_unit = unit_instance != null and unit_instance.data.is_ranged()
	if is_ranged_unit:
		will_advance = false

	active_tween = create_tween()

	if will_advance:
		# Melee advance directly into the defeated tile and stay there
		grid_coords = target_coords
		active_tween.tween_property(self, "position", target_pos, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		active_tween.tween_callback(update_display)
	elif is_ranged_unit:
		# Ranged: brief recoil pulse on starting tile, never leave tile
		var recoil_pos = base_pos + (base_pos - target_pos).normalized() * 2.0
		active_tween.tween_property(self, "position", recoil_pos, 0.06)
		active_tween.tween_property(self, "position", base_pos, 0.08)
		active_tween.tween_callback(update_display)
	else:
		# Melee: Quick strike towards enemy and return strictly to base position
		var nudge_pos = base_pos.lerp(target_pos, 0.30)
		active_tween.tween_property(self, "position", nudge_pos, 0.08)
		active_tween.tween_property(self, "position", base_pos, 0.10)
		active_tween.tween_callback(update_display)

func play_death_animation(on_complete: Callable = Callable()) -> void:
	if active_tween and active_tween.is_valid():
		active_tween.kill()

	active_tween = create_tween()
	active_tween.tween_property(self, "modulate", Color(2.5, 0.4, 0.4, 1.0), 0.08)
	active_tween.tween_property(self, "scale", Vector2(0.1, 0.1), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	active_tween.parallel().tween_property(self, "modulate", Color(1.0, 0.2, 0.2, 0.0), 0.16)
	active_tween.tween_callback(func():
		if on_complete.is_valid():
			on_complete.call()
		queue_free()
	)

