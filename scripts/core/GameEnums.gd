class_name GameEnums
extends RefCounted

## Core enumerations for the 4X Strategy Game

enum FactionId {
	SOLARIS_DOMINION = 0,   # Human Player / Faction 0 (Blue)
	IRONFANG_EMPIRE = 1,    # Rival AI Faction 1 (Red)
	VERDANT_KINGDOM = 2,    # Rival AI Faction 2 (Green)
	OBSIDIAN_CONCLAVE = 3,  # Rival AI Faction 3 (Purple)
	CELESTIAL_SHOGUNATE = 4,# Rival AI Faction 4 (Gold/Amber)
	FROSTVEIN_CLAN = 5,     # Rival AI Faction 5 (Teal/Cyan)
	GOLDEN_EMIRATE = 6,     # Rival AI Faction 6 (Orange)
	BARBARIANS = 99         # Neutral Hostile Raider faction (Dark Crimson)
}

enum TurnPhase {
	PLAYER_TURN,
	AI_FACTIONS_TURN,
	BARBARIAN_TURN,
	TURN_RESOLUTION
}

enum BiomeType {
	OCEAN,
	PLAINS,
	HILLS,
	MOUNTAINS,
	TUNDRA
}

enum StrategicResourceType {
	NONE,
	RICE,
	IRON,
	HORSES,
	GOLD_ORE,
	GEMS,
	NITER
}

enum ImprovementType {
	NONE,
	FARM,
	MINE,
	PASTURE,
	MILITARY_ENCAMPMENT,
	SCIENCE_CAMP,
	MARKET,
	AQUEDUCT,
	CASTLE,
	NEIGHBORHOOD,
	BORDER_WALL,
	TEMPORARY_CAMP,
	HARBOR
}

enum UnitClass {
	CIVILIAN,
	MELEE,
	RANGED,
	RECON,
	CAVALRY,
	NAVAL_MELEE,
	NAVAL_RANGED
}

enum CommandType {
	MOVE,
	ATTACK,
	RANGED_ATTACK,
	FOUND_CITY,
	BUILD_IMPROVEMENT,
	FORTIFY,
	SKIP_TURN
}
