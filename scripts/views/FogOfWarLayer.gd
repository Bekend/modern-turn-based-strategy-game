class_name FogOfWarLayer
extends Node2D

## Renders retro 8-bit fog of war and unexplored shroud for player civilization.

var game_state: GameState
var player_faction: int = GameEnums.FactionId.SOLARIS_DOMINION

const COLOR_SHROUD = Color(0.05, 0.07, 0.12, 1.0) # Solid dark navy/black unexplored shroud
const COLOR_FOG = Color(0.04, 0.06, 0.12, 0.52)    # Semi-transparent fog of war

func setup(p_game_state: GameState, p_faction: int = GameEnums.FactionId.SOLARIS_DOMINION) -> void:
	game_state = p_game_state
	player_faction = p_faction
	queue_redraw()

func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	if not game_state or not game_state.grid_model:
		return

	var grid = game_state.grid_model
	for y in range(grid.height):
		for x in range(grid.width):
			var coords = Vector2i(x, y)
			var tile = grid.get_tile(coords)
			if not tile:
				continue
			var px = float(x * 16)
			var py = float(y * 16)
			var is_revealed = tile.revealed_by_faction.get(player_faction, false)
			var tile_visible = tile.visible_by_faction.get(player_faction, false)

			if not is_revealed:
				draw_rect(Rect2(px, py, 16.0, 16.0), COLOR_SHROUD, true)
			elif not tile_visible:
				draw_rect(Rect2(px, py, 16.0, 16.0), COLOR_FOG, true)
