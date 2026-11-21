class_name SettlerLensLayer
extends Node2D

## Renders Civ 6 style Settler Lens:
## Available land to settle (at least 2 tiles away on all sides from all other cities) is tinted translucent green.
## Unavailable land (within 2 tiles of any city, impassable mountains/water, foreign territory) is tinted translucent background red.
## Both colors use alpha ~0.22 so resources, terrain, and science dots remain fully visible.

var game_state: GameState
var is_active: bool = false
var player_faction: int = GameEnums.FactionId.SOLARIS_DOMINION

const COLOR_SETTLEABLE_FILL = Color(0.18, 0.78, 0.35, 0.22)
const COLOR_SETTLEABLE_BORDER = Color(0.20, 0.90, 0.40, 0.45)
const COLOR_UNAVAILABLE_FILL = Color(0.85, 0.22, 0.22, 0.22)

func setup(p_game_state: GameState, p_faction: int = GameEnums.FactionId.SOLARIS_DOMINION) -> void:
	game_state = p_game_state
	player_faction = p_faction
	is_active = false
	visible = false

func show_lens() -> void:
	is_active = true
	visible = true
	queue_redraw()

func hide_lens() -> void:
	is_active = false
	visible = false
	queue_redraw()

func _draw() -> void:
	if not is_active or not game_state or not game_state.grid_model:
		return

	var grid = game_state.grid_model
	for y in range(grid.height):
		for x in range(grid.width):
			var coords = Vector2i(x, y)
			var tile = grid.get_tile(coords)
			if not tile:
				continue

			# Only draw on tiles revealed to the player
			if not tile.revealed_by_faction.get(player_faction, false):
				continue

			var px = float(x * 16)
			var py = float(y * 16)
			var rect = Rect2(px, py, 16.0, 16.0)

			# Settle check:
			# 1. Tile must be passable (no ocean or mountain)
			# 2. Tile must not be owned by a foreign faction
			# 3. Must be at least 2 tiles away on all sides from all existing cities (dx <= 2 and dy <= 2 is forbidden)
			var can_settle = tile.biome_data.is_passable and (tile.owner_faction_id == -1 or tile.owner_faction_id == player_faction)

			if can_settle:
				for city in game_state.cities.values():
					var dx = absi(city.grid_pos.x - x)
					var dy = absi(city.grid_pos.y - y)
					if dx <= 2 and dy <= 2:
						can_settle = false
						break

			if can_settle:
				draw_rect(rect, COLOR_SETTLEABLE_FILL, true)
				draw_rect(rect, COLOR_SETTLEABLE_BORDER, false, 1.0)
			else:
				draw_rect(rect, COLOR_UNAVAILABLE_FILL, true)
