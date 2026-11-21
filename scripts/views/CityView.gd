class_name CityView
extends Node2D

## Visual representation of a founded City, displaying faction banners,
## City Fortification barrier bar, and core health.

const CELL_SIZE: int = 16

var city_data: CityData

@onready var faction_roof: ColorRect = $CastleIcon/FactionRoof
@onready var hp_bar_bg: ColorRect = $HPBarBg
@onready var hp_bar_fill: ColorRect = $HPBarBg/HPBarFill
@onready var fort_bar_bg: ColorRect = $FortBarBg
@onready var fort_bar_fill: ColorRect = $FortBarBg/FortBarFill
@onready var walls_border: ColorRect = $WallsBorder

func _ready() -> void:
	for child in find_children("*", "Control", true, false):
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup(p_city: CityData, faction_color: Color) -> void:
	city_data = p_city
	position = Vector2(p_city.grid_pos.x * CELL_SIZE + CELL_SIZE * 0.5, p_city.grid_pos.y * CELL_SIZE + CELL_SIZE * 0.5)
	faction_roof.color = faction_color
	update_display()

func update_display() -> void:
	if not city_data:
		return

	# Update Pixel-Art City HP Bar
	var max_hp = float(maxi(1, city_data.max_health))
	var hp_pct = clampf(float(city_data.health) / max_hp, 0.0, 1.0)
	if city_data.health <= 0:
		hp_bar_fill.size.x = 0.0
	else:
		hp_bar_fill.size.x = maxf(1.0, roundf(hp_pct * 10.0))

	if hp_pct > 0.5:
		hp_bar_fill.color = Color("2ecc71") # Green
	elif hp_pct > 0.25:
		hp_bar_fill.color = Color("f1c40f") # Yellow
	else:
		hp_bar_fill.color = Color("e74c3c") # Red

	# Update Fortification Barrier Bar (Only displayed if city has constructed City Walls)
	if not city_data.has_walls or city_data.max_fortification <= 0:
		fort_bar_bg.hide()
	else:
		var max_fort = float(maxi(1, city_data.max_fortification))
		var fort_pct = clampf(float(city_data.fortification) / max_fort, 0.0, 1.0)
		fort_bar_bg.show()
		fort_bar_fill.size.x = maxf(0.0, roundf(fort_pct * 10.0))

	# Show fortified stone walls if built
	if walls_border:
		walls_border.visible = city_data.has_walls

var active_tween: Tween = null

func play_hit_shake() -> void:
	if not city_data:
		return
	var base_pos = Vector2(city_data.grid_pos.x * CELL_SIZE + CELL_SIZE * 0.5, city_data.grid_pos.y * CELL_SIZE + CELL_SIZE * 0.5)
	if active_tween and active_tween.is_valid():
		active_tween.kill()

	active_tween = create_tween()
	active_tween.tween_property(self, "position", base_pos + Vector2(2, 0), 0.04)
	active_tween.tween_property(self, "position", base_pos - Vector2(2, 0), 0.04)
	active_tween.tween_property(self, "position", base_pos + Vector2(1, 0), 0.04)
	active_tween.tween_property(self, "position", base_pos, 0.04)

func update_visibility(player_faction: int, grid_model: GridModel) -> void:
	if not city_data:
		return
	# Friendly player city is always visible
	if city_data.faction_id == player_faction:
		visible = true
		modulate = Color.WHITE
		if hp_bar_bg: hp_bar_bg.show()
		return

	# Rival/hostile city:
	var tile = grid_model.get_tile(city_data.grid_pos) if grid_model else null
	if not tile:
		visible = false
		return

	var is_revealed = tile.revealed_by_faction.get(player_faction, false)
	var tile_is_visible = tile.visible_by_faction.get(player_faction, false)
	var is_discovered = city_data.discovered_by_faction.get(player_faction, false)

	if tile_is_visible:
		# In active player sight: reveal and discover
		city_data.discovered_by_faction[player_faction] = true
		visible = true
		modulate = Color.WHITE
		if hp_bar_bg: hp_bar_bg.show()
	elif is_revealed and is_discovered:
		# In explored Fog of War, previously discovered: visible but dimmed, HP bars hidden
		visible = true
		modulate = Color(0.65, 0.65, 0.7, 0.65)
		if hp_bar_bg: hp_bar_bg.hide()
		if fort_bar_bg: fort_bar_bg.hide()
	else:
		# Undiscovered or in dark shroud
		visible = false

