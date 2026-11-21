## GameConfig — global singleton that carries settings from the Main Menu into the game.
## Registered as an Autoload under the name "GameConfig" in project.godot.
extends Node

## Map size presets: [width, height, label]
const MAP_SIZES: Array = [
	[28, 18, "Small"],
	[44, 28, "Standard"],
	[60, 38, "Large"],
	[80, 50, "Huge"],
]

## Index into MAP_SIZES (0 = Small ... 3 = Huge)
var map_size_index: int = 1

## Number of AI factions (1-6 in this game)
var ai_count: int = 2

## Whether this is a continued game
var is_continue: bool = false

## Multiplayer session parameters
var is_multiplayer: bool = false
var is_host: bool = true
var local_player_faction_id: int = 0
var multiplayer_player_limit: int = 4
var multiplayer_seed: int = 1337

## Audio Settings
var sfx_enabled: bool = true
var music_enabled: bool = true

const SETTINGS_FILE: String = "user://settings.cfg"

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(SETTINGS_FILE) == OK:
		sfx_enabled = cfg.get_value("audio", "sfx_enabled", true)
		music_enabled = cfg.get_value("audio", "music_enabled", true)

func save_settings() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("audio", "sfx_enabled", sfx_enabled)
	cfg.set_value("audio", "music_enabled", music_enabled)
	cfg.save(SETTINGS_FILE)

func get_map_width() -> int:
	return MAP_SIZES[map_size_index][0]

func get_map_height() -> int:
	return MAP_SIZES[map_size_index][1]

func get_map_label() -> String:
	return MAP_SIZES[map_size_index][2]

