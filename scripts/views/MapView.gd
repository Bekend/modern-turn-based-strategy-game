class_name MapView
extends Node2D

## Visual presenter for the 2D tile map using Godot 4.3 TileMapLayer nodes

@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var feature_layer: TileMapLayer = $FeatureLayer
@onready var territory_layer: TerritoryLayer = $TerritoryLayer
@onready var overlay_layer: TileMapLayer = $OverlayLayer
@onready var fog_of_war_layer: FogOfWarLayer = $FogOfWarLayer
var science_layer: TileMapLayer
var border_wall_layer: TileMapLayer
var settler_lens_layer: SettlerLensLayer

var game_state: GameState
var grid_model: GridModel
var tileset: TileSet

func initialize(p_game_state: GameState) -> void:
	game_state = p_game_state
	grid_model = p_game_state.grid_model
	tileset = AssetHelper.create_procedural_tileset()

	terrain_layer.tile_set = tileset
	feature_layer.tile_set = tileset
	overlay_layer.tile_set = tileset

	if has_node("ScienceLayer"):
		science_layer = get_node("ScienceLayer") as TileMapLayer
	else:
		science_layer = TileMapLayer.new()
		science_layer.name = "ScienceLayer"
		add_child(science_layer)
		move_child(science_layer, feature_layer.get_index() + 1)
	science_layer.tile_set = tileset

	if has_node("BorderWallLayer"):
		border_wall_layer = get_node("BorderWallLayer") as TileMapLayer
	else:
		border_wall_layer = TileMapLayer.new()
		border_wall_layer.name = "BorderWallLayer"
		add_child(border_wall_layer)
		move_child(border_wall_layer, science_layer.get_index() + 1)
	border_wall_layer.tile_set = tileset

	if has_node("SettlerLensLayer"):
		settler_lens_layer = get_node("SettlerLensLayer") as SettlerLensLayer
	else:
		settler_lens_layer = SettlerLensLayer.new()
		settler_lens_layer.name = "SettlerLensLayer"
		add_child(settler_lens_layer)
		move_child(settler_lens_layer, overlay_layer.get_index())
	settler_lens_layer.setup(game_state)

	if territory_layer:
		territory_layer.setup(game_state)

	if fog_of_war_layer:
		fog_of_war_layer.setup(game_state)

	render_full_map()

func show_settler_lens() -> void:
	if settler_lens_layer:
		settler_lens_layer.show_lens()

func hide_settler_lens() -> void:
	if settler_lens_layer:
		settler_lens_layer.hide_lens()

func update_territory_display() -> void:
	if territory_layer:
		territory_layer.queue_redraw()

func update_fog_of_war_display() -> void:
	if fog_of_war_layer:
		fog_of_war_layer.refresh()

## Full initial render pass
func render_full_map() -> void:
	terrain_layer.clear()
	feature_layer.clear()
	if science_layer:
		science_layer.clear()
	if border_wall_layer:
		border_wall_layer.clear()
	overlay_layer.clear()

	for y in range(grid_model.height):
		for x in range(grid_model.width):
			var coords = Vector2i(x, y)
			render_tile(coords)

## Renders single tile layers
func render_tile(coords: Vector2i) -> void:
	var tile = grid_model.get_tile(coords)
	if not tile:
		return

	# 1. Terrain Base
	var atlas_coord = AssetHelper.ATLAS_PLAINS
	match tile.biome_data.biome_type:
		GameEnums.BiomeType.OCEAN:
			atlas_coord = AssetHelper.ATLAS_OCEAN
		GameEnums.BiomeType.PLAINS:
			atlas_coord = AssetHelper.ATLAS_PLAINS
		GameEnums.BiomeType.HILLS:
			atlas_coord = AssetHelper.ATLAS_HILLS
		GameEnums.BiomeType.MOUNTAINS:
			atlas_coord = AssetHelper.ATLAS_MOUNTAINS
		GameEnums.BiomeType.TUNDRA:
			atlas_coord = AssetHelper.ATLAS_TUNDRA

	terrain_layer.set_cell(coords, 0, atlas_coord)

	# 2. Features: Resources & Improvements
	feature_layer.erase_cell(coords)
	if science_layer:
		science_layer.erase_cell(coords)
		if tile.natural_science > 0:
			science_layer.set_cell(coords, 0, AssetHelper.ATLAS_SCIENCE_NODE)

	if border_wall_layer:
		border_wall_layer.erase_cell(coords)
		if tile.has_border_wall:
			border_wall_layer.set_cell(coords, 0, AssetHelper.ATLAS_BORDER_WALL_BADGE)

	if tile.improvement_data != null:
		var feat_atlas = AssetHelper.ATLAS_FARM
		match tile.improvement_data.improvement_type:
			GameEnums.ImprovementType.FARM:
				feat_atlas = AssetHelper.ATLAS_FARM
			GameEnums.ImprovementType.MINE:
				feat_atlas = AssetHelper.ATLAS_MINE
			GameEnums.ImprovementType.MILITARY_ENCAMPMENT:
				feat_atlas = AssetHelper.ATLAS_ENCAMPMENT
			GameEnums.ImprovementType.SCIENCE_CAMP:
				feat_atlas = AssetHelper.ATLAS_SCIENCE_CAMP
			GameEnums.ImprovementType.MARKET:
				feat_atlas = AssetHelper.ATLAS_MARKET
			GameEnums.ImprovementType.AQUEDUCT:
				feat_atlas = AssetHelper.ATLAS_AQUEDUCT
			GameEnums.ImprovementType.CASTLE:
				feat_atlas = AssetHelper.ATLAS_CASTLE
			GameEnums.ImprovementType.PASTURE:
				feat_atlas = AssetHelper.ATLAS_PASTURE
			GameEnums.ImprovementType.NEIGHBORHOOD:
				feat_atlas = AssetHelper.ATLAS_NEIGHBORHOOD
			GameEnums.ImprovementType.BORDER_WALL:
				feat_atlas = AssetHelper.ATLAS_BORDER_WALL
			GameEnums.ImprovementType.TEMPORARY_CAMP:
				feat_atlas = AssetHelper.ATLAS_TEMPORARY_CAMP
			GameEnums.ImprovementType.HARBOR:
				feat_atlas = AssetHelper.ATLAS_HARBOR
		feature_layer.set_cell(coords, 0, feat_atlas)
	elif tile.resource_data != null:
		var can_see_resource = true
		if tile.resource_data.is_strategic and tile.resource_data.required_tech != "" and game_state and game_state.tech_manager:
			can_see_resource = game_state.tech_manager.is_tech_researched(GameEnums.FactionId.SOLARIS_DOMINION, tile.resource_data.required_tech)

		if can_see_resource:
			var res_atlas = AssetHelper.ATLAS_RICE
			match tile.resource_data.resource_type:
				GameEnums.StrategicResourceType.RICE:
					res_atlas = AssetHelper.ATLAS_RICE
				GameEnums.StrategicResourceType.IRON:
					res_atlas = AssetHelper.ATLAS_IRON
				GameEnums.StrategicResourceType.HORSES:
					res_atlas = AssetHelper.ATLAS_HORSES
				GameEnums.StrategicResourceType.GOLD_ORE:
					res_atlas = AssetHelper.ATLAS_GOLD_ORE
				GameEnums.StrategicResourceType.GEMS:
					res_atlas = AssetHelper.ATLAS_GEMS
				GameEnums.StrategicResourceType.NITER:
					res_atlas = AssetHelper.ATLAS_NITER
			feature_layer.set_cell(coords, 0, res_atlas)
	elif tile.natural_science > 0:
		pass # Rendered as glowing top-left blue dot on science_layer

func show_district_placement_overlay(valid_tiles: Variant) -> void:
	overlay_layer.clear()
	if valid_tiles is Dictionary:
		for coord in valid_tiles.keys():
			overlay_layer.set_cell(coord, 0, AssetHelper.ATLAS_DISTRICT_VALID)
	elif valid_tiles is Array:
		for coord in valid_tiles:
			overlay_layer.set_cell(coord, 0, AssetHelper.ATLAS_DISTRICT_VALID)

func hide_district_placement_overlay() -> void:
	overlay_layer.clear()

## Clears all selection & reachable action overlays
func clear_overlays() -> void:
	overlay_layer.clear()

## Highlights reachable move tiles and attackable enemy targets
func show_action_overlays(reachable_tiles: Dictionary, attackable_tiles: Array, selected_pos: Vector2i, unit_remaining_mp: int = 2) -> void:
	overlay_layer.clear()

	# Draw movement reachable tiles with numbered MP cost indicators
	for coord in reachable_tiles.keys():
		if coord != selected_pos:
			var remaining_mp: int = reachable_tiles[coord]
			var mp_cost: int = maxi(1, unit_remaining_mp - remaining_mp)
			var cost_atlas = AssetHelper.ATLAS_REACHABLE_COST1
			if mp_cost == 2:
				cost_atlas = AssetHelper.ATLAS_REACHABLE_COST2
			elif mp_cost >= 3:
				cost_atlas = AssetHelper.ATLAS_REACHABLE_COST3
			overlay_layer.set_cell(coord, 0, cost_atlas)

	# Draw attack targets
	for coord in attackable_tiles:
		overlay_layer.set_cell(coord, 0, AssetHelper.ATLAS_ATTACK_OVERLAY)

	# Draw cursor on selected unit
	overlay_layer.set_cell(selected_pos, 0, AssetHelper.ATLAS_SELECT_CURSOR)
