class_name TerritoryLayer
extends Node2D

## Renders faction territory borders and territory fill tinting on the map.

var game_state: GameState

func setup(p_game_state: GameState) -> void:
	game_state = p_game_state
	queue_redraw()

func _draw() -> void:
	if not game_state:
		return

	var player_faction = GameEnums.FactionId.SOLARIS_DOMINION
	var grid = game_state.grid_model

	for city in game_state.cities.values():
		var is_player = (city.faction_id == player_faction)
		if not is_player and not city.discovered_by_faction.get(player_faction, false):
			continue # Undiscovered enemy city territory is completely hidden

		var fac_color = game_state.faction_colors.get(city.faction_id, Color.WHITE)
		var fill_color = Color(fac_color.r, fac_color.g, fac_color.b, 0.12)
		var border_color = Color(fac_color.r, fac_color.g, fac_color.b, 0.95)
		var line_width = 2.0

		for t in city.territory_tiles:
			if not is_player and grid:
				var t_state = grid.get_tile(t)
				if not t_state or not t_state.revealed_by_faction.get(player_faction, false):
					continue # Do not draw territory in dark shroud

			var px = float(t.x * 16)
			var py = float(t.y * 16)

			# 1. Subtle territory tint
			draw_rect(Rect2(px, py, 16.0, 16.0), fill_color, true)

			# 2. Outer perimeter border lines (check 4 neighbors)
			var n = Vector2i(t.x, t.y - 1)
			if not city.territory_tiles.has(n):
				draw_line(Vector2(px, py + 1.0), Vector2(px + 16.0, py + 1.0), border_color, line_width)

			var s = Vector2i(t.x, t.y + 1)
			if not city.territory_tiles.has(s):
				draw_line(Vector2(px, py + 15.0), Vector2(px + 16.0, py + 15.0), border_color, line_width)

			var w = Vector2i(t.x - 1, t.y)
			if not city.territory_tiles.has(w):
				draw_line(Vector2(px + 1.0, py), Vector2(px + 1.0, py + 16.0), border_color, line_width)

			var e = Vector2i(t.x + 1, t.y)
			if not city.territory_tiles.has(e):
				draw_line(Vector2(px + 15.0, py), Vector2(px + 15.0, py + 16.0), border_color, line_width)
