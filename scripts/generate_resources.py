import os

base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

biomes = {
    "ocean.tres": {
        "script": "res://scripts/data/BiomeData.gd",
        "class": "BiomeData",
        "fields": {
            "id": '"ocean"',
            "biome_name": '"Ocean"',
            "biome_type": 0, # OCEAN
            "move_cost": 999,
            "defense_bonus_percent": 0,
            "is_passable": "false",
            "yield_food": 1,
            "yield_production": 0,
            "yield_science": 0,
            "color_tint": "Color(0.18, 0.38, 0.72, 1)",
            "description": '"Deep water. Impassable without naval vessels."'
        }
    },
    "plains.tres": {
        "script": "res://scripts/data/BiomeData.gd",
        "class": "BiomeData",
        "fields": {
            "id": '"plains"',
            "biome_name": '"Plains"',
            "biome_type": 1, # PLAINS
            "move_cost": 1,
            "defense_bonus_percent": 0,
            "is_passable": "true",
            "yield_food": 2,
            "yield_production": 1,
            "yield_science": 0,
            "color_tint": "Color(0.29, 0.54, 0.24, 1)",
            "description": '"Open fertile grasslands ideal for farming and quick maneuver."'
        }
    },
    "hills.tres": {
        "script": "res://scripts/data/BiomeData.gd",
        "class": "BiomeData",
        "fields": {
            "id": '"hills"',
            "biome_name": '"Highlands/Hills"',
            "biome_type": 2, # HILLS
            "move_cost": 2,
            "defense_bonus_percent": 25,
            "is_passable": "true",
            "yield_food": 1,
            "yield_production": 2,
            "yield_science": 0,
            "color_tint": "Color(0.48, 0.44, 0.31, 1)",
            "description": '"Elevated rolling hills. Costs 2 MP, grants +25% defense."'
        }
    },
    "mountains.tres": {
        "script": "res://scripts/data/BiomeData.gd",
        "class": "BiomeData",
        "fields": {
            "id": '"mountains"',
            "biome_name": '"Mountains"',
            "biome_type": 3, # MOUNTAINS
            "move_cost": 999,
            "defense_bonus_percent": 50,
            "is_passable": "false",
            "yield_food": 0,
            "yield_production": 3,
            "yield_science": 1,
            "color_tint": "Color(0.40, 0.40, 0.45, 1)",
            "description": '"Impassable peaks. Provides defensive obstruction and raw ores."'
        }
    },
    "tundra.tres": {
        "script": "res://scripts/data/BiomeData.gd",
        "class": "BiomeData",
        "fields": {
            "id": '"tundra"',
            "biome_name": '"Tundra"',
            "biome_type": 4, # TUNDRA
            "move_cost": 1,
            "defense_bonus_percent": 0,
            "is_passable": "true",
            "yield_food": 1,
            "yield_production": 1,
            "yield_science": 0,
            "color_tint": "Color(0.68, 0.76, 0.82, 1)",
            "description": '"Frigid subpolar permafrost."'
        }
    }
}

resources = {
    "rice.tres": {
        "script": "res://scripts/data/ResourceData.gd",
        "class": "ResourceData",
        "fields": {
            "id": '"rice"',
            "display_name": '"Rice"',
            "resource_type": 1, # RICE
            "food_bonus": 2,
            "production_bonus": 0,
            "science_bonus": 0,
            "required_tech": '""',
            "is_strategic": "false",
            "icon_color": "Color(0.88, 0.76, 0.27, 1)",
            "symbol_char": '"🌾"'
        }
    },
    "iron.tres": {
        "script": "res://scripts/data/ResourceData.gd",
        "class": "ResourceData",
        "fields": {
            "id": '"iron"',
            "display_name": '"Iron"',
            "resource_type": 2, # IRON
            "food_bonus": 0,
            "production_bonus": 2,
            "science_bonus": 0,
            "required_tech": '"iron_working"',
            "is_strategic": "true",
            "icon_color": "Color(0.65, 0.25, 0.25, 1)",
            "symbol_char": '"⛏"'
        }
    },
    "horses.tres": {
        "script": "res://scripts/data/ResourceData.gd",
        "class": "ResourceData",
        "fields": {
            "id": '"horses"',
            "display_name": '"Horses"',
            "resource_type": 3, # HORSES
            "food_bonus": 1,
            "production_bonus": 1,
            "science_bonus": 0,
            "required_tech": '"horse_riding"',
            "is_strategic": "true",
            "icon_color": "Color(0.6, 0.4, 0.2, 1)",
            "symbol_char": '"🐎"'
        }
    }
}

improvements = {
    "farm.tres": {
        "script": "res://scripts/data/ImprovementData.gd",
        "class": "ImprovementData",
        "fields": {
            "id": '"farm"',
            "improvement_name": '"Farm"',
            "improvement_type": 1,
            "food_bonus": 2,
            "production_bonus": 0,
            "science_bonus": 0,
            "defense_bonus_percent": 0,
            "adds_defensive_range": 0,
            "trains_advanced_units": "false",
            "build_turns": 2,
            "required_tech": '"agriculture"',
            "icon_color": "Color(0.6, 0.72, 0.2, 1)"
        }
    },
    "mine.tres": {
        "script": "res://scripts/data/ImprovementData.gd",
        "class": "ImprovementData",
        "fields": {
            "id": '"mine"',
            "improvement_name": '"Mine"',
            "improvement_type": 2,
            "food_bonus": 0,
            "production_bonus": 2,
            "science_bonus": 0,
            "defense_bonus_percent": 0,
            "adds_defensive_range": 0,
            "trains_advanced_units": "false",
            "build_turns": 2,
            "required_tech": '"mining"',
            "icon_color": "Color(0.45, 0.42, 0.38, 1)"
        }
    },
    "encampment.tres": {
        "script": "res://scripts/data/ImprovementData.gd",
        "class": "ImprovementData",
        "fields": {
            "id": '"encampment"',
            "improvement_name": '"Military Encampment"',
            "improvement_type": 4,
            "food_bonus": 0,
            "production_bonus": 2,
            "science_bonus": 0,
            "defense_bonus_percent": 25,
            "adds_defensive_range": 1,
            "trains_advanced_units": "true",
            "build_turns": 3,
            "required_tech": '"bronze_working"',
            "icon_color": "Color(0.85, 0.25, 0.25, 1)"
        }
    },
    "science_camp.tres": {
        "script": "res://scripts/data/ImprovementData.gd",
        "class": "ImprovementData",
        "fields": {
            "id": '"science_camp"',
            "improvement_name": '"Science Camp"',
            "improvement_type": 5,
            "food_bonus": 0,
            "production_bonus": 0,
            "science_bonus": 3,
            "defense_bonus_percent": 0,
            "adds_defensive_range": 0,
            "trains_advanced_units": "false",
            "build_turns": 3,
            "required_tech": '"writing"',
            "icon_color": "Color(0.25, 0.65, 0.9, 1)"
        }
    }
}

units = {
    "settler.tres": {
        "script": "res://scripts/data/UnitData.gd",
        "class": "UnitData",
        "fields": {
            "id": '"settler"',
            "unit_name": '"Settler"',
            "unit_class": 0, # CIVILIAN
            "combat_strength": 0,
            "ranged_strength": 0,
            "attack_range": 1,
            "max_movement_points": 2,
            "max_health": 100,
            "production_cost": 50,
            "tech_prerequisite": '""',
            "strategic_prerequisite": '""',
            "can_found_city": "true",
            "can_build_improvements": "false",
            "sight_range": 2,
            "color_tint": "Color(0.9, 0.9, 0.3, 1)",
            "icon_symbol": '"🏛"'
        }
    },
    "builder.tres": {
        "script": "res://scripts/data/UnitData.gd",
        "class": "UnitData",
        "fields": {
            "id": '"builder"',
            "unit_name": '"Builder"',
            "unit_class": 0, # CIVILIAN
            "combat_strength": 0,
            "ranged_strength": 0,
            "attack_range": 1,
            "max_movement_points": 2,
            "max_health": 100,
            "production_cost": 30,
            "tech_prerequisite": '""',
            "strategic_prerequisite": '""',
            "can_found_city": "false",
            "can_build_improvements": "true",
            "sight_range": 2,
            "color_tint": "Color(0.8, 0.5, 0.2, 1)",
            "icon_symbol": '"🔨"'
        }
    },
    "scout.tres": {
        "script": "res://scripts/data/UnitData.gd",
        "class": "UnitData",
        "fields": {
            "id": '"scout"',
            "unit_name": '"Scout"',
            "unit_class": 3, # RECON
            "combat_strength": 10,
            "ranged_strength": 0,
            "attack_range": 1,
            "max_movement_points": 3,
            "max_health": 100,
            "production_cost": 25,
            "tech_prerequisite": '""',
            "strategic_prerequisite": '""',
            "can_found_city": "false",
            "can_build_improvements": "false",
            "sight_range": 3,
            "color_tint": "Color(0.3, 0.75, 0.4, 1)",
            "icon_symbol": '"👁"'
        }
    },
    "slinger.tres": {
        "script": "res://scripts/data/UnitData.gd",
        "class": "UnitData",
        "fields": {
            "id": '"slinger"',
            "unit_name": '"Slinger"',
            "unit_class": 2, # RANGED
            "combat_strength": 8,
            "ranged_strength": 15,
            "attack_range": 2,
            "max_movement_points": 2,
            "max_health": 100,
            "production_cost": 35,
            "tech_prerequisite": '"archery"',
            "strategic_prerequisite": '""',
            "can_found_city": "false",
            "can_build_improvements": "false",
            "sight_range": 2,
            "color_tint": "Color(0.85, 0.65, 0.2, 1)",
            "icon_symbol": '"🏹"'
        }
    },
    "swordsman.tres": {
        "script": "res://scripts/data/UnitData.gd",
        "class": "UnitData",
        "fields": {
            "id": '"swordsman"',
            "unit_name": '"Swordsman"',
            "unit_class": 1, # MELEE
            "combat_strength": 28,
            "ranged_strength": 0,
            "attack_range": 1,
            "max_movement_points": 2,
            "max_health": 100,
            "production_cost": 65,
            "tech_prerequisite": '"iron_working"',
            "strategic_prerequisite": '"iron"',
            "can_found_city": "false",
            "can_build_improvements": "false",
            "sight_range": 2,
            "color_tint": "Color(0.2, 0.45, 0.85, 1)",
            "icon_symbol": '"⚔"'
        }
    },
    "barbarian_raider.tres": {
        "script": "res://scripts/data/UnitData.gd",
        "class": "UnitData",
        "fields": {
            "id": '"barbarian_raider"',
            "unit_name": '"Barbarian Raider"',
            "unit_class": 1, # MELEE
            "combat_strength": 16,
            "ranged_strength": 0,
            "attack_range": 1,
            "max_movement_points": 2,
            "max_health": 100,
            "production_cost": 35,
            "tech_prerequisite": '""',
            "strategic_prerequisite": '""',
            "can_found_city": "false",
            "can_build_improvements": "false",
            "sight_range": 2,
            "color_tint": "Color(0.7, 0.15, 0.15, 1)",
            "icon_symbol": '"💀"'
        }
    }
}

techs = {
    "agriculture.tres": {
        "script": "res://scripts/data/TechNode.gd",
        "class": "TechNode",
        "fields": {
            "tech_id": '"agriculture"',
            "title": '"Agriculture"',
            "description": '"Foundational farming knowledge. Unlocks Farms to boost city growth."',
            "science_cost": 15,
            "tier": 1,
            "prerequisites": '[]',
            "unlocked_units": '[]',
            "unlocked_improvements": '["farm"]',
            "reveals_strategic_resource": '""',
            "highland_move_cost_reduction": 0,
            "melee_attack_bonus_percent": 0,
            "defense_bonus_percent": 0,
            "tree_column": 0,
            "tree_row": 0
        }
    },
    "mining.tres": {
        "script": "res://scripts/data/TechNode.gd",
        "class": "TechNode",
        "fields": {
            "tech_id": '"mining"',
            "title": '"Mining"',
            "description": '"Allows excavation of mineral wealth and production-boosting Mines."',
            "science_cost": 25,
            "tier": 2,
            "prerequisites": '["agriculture"]',
            "unlocked_units": '[]',
            "unlocked_improvements": '["mine"]',
            "reveals_strategic_resource": '""',
            "highland_move_cost_reduction": 0,
            "melee_attack_bonus_percent": 0,
            "defense_bonus_percent": 0,
            "tree_column": 1,
            "tree_row": 0
        }
    },
    "archery.tres": {
        "script": "res://scripts/data/TechNode.gd",
        "class": "TechNode",
        "fields": {
            "tech_id": '"archery"',
            "title": '"Archery"',
            "description": '"Enables ranged ballistic weaponry. Unlocks Slinger units."',
            "science_cost": 30,
            "tier": 2,
            "prerequisites": '["agriculture"]',
            "unlocked_units": '["slinger"]',
            "unlocked_improvements": '[]',
            "reveals_strategic_resource": '""',
            "highland_move_cost_reduction": 0,
            "melee_attack_bonus_percent": 0,
            "defense_bonus_percent": 0,
            "tree_column": 1,
            "tree_row": 1
        }
    },
    "bronze_working.tres": {
        "script": "res://scripts/data/TechNode.gd",
        "class": "TechNode",
        "fields": {
            "tech_id": '"bronze_working"',
            "title": '"Bronze Working"',
            "description": '"Advanced metallurgy. Unlocks Military Encampments that bolster defense."',
            "science_cost": 45,
            "tier": 3,
            "prerequisites": '["mining"]',
            "unlocked_units": '[]',
            "unlocked_improvements": '["encampment"]',
            "reveals_strategic_resource": '""',
            "highland_move_cost_reduction": 0,
            "melee_attack_bonus_percent": 5,
            "defense_bonus_percent": 5,
            "tree_column": 2,
            "tree_row": 0
        }
    },
    "writing.tres": {
        "script": "res://scripts/data/TechNode.gd",
        "class": "TechNode",
        "fields": {
            "tech_id": '"writing"',
            "title": '"Writing"',
            "description": '"Record keeping and scientific observation. Unlocks Science Camps."',
            "science_cost": 40,
            "tier": 3,
            "prerequisites": '["agriculture"]',
            "unlocked_units": '[]',
            "unlocked_improvements": '["science_camp"]',
            "reveals_strategic_resource": '""',
            "highland_move_cost_reduction": 0,
            "melee_attack_bonus_percent": 0,
            "defense_bonus_percent": 0,
            "tree_column": 2,
            "tree_row": 1
        }
    },
    "iron_working.tres": {
        "script": "res://scripts/data/TechNode.gd",
        "class": "TechNode",
        "fields": {
            "tech_id": '"iron_working"',
            "title": '"Iron Working"',
            "description": '"Reveals Iron resources and unlocks devastating Swordsman shock infantry."',
            "science_cost": 65,
            "tier": 4,
            "prerequisites": '["bronze_working"]',
            "unlocked_units": '["swordsman"]',
            "unlocked_improvements": '[]',
            "reveals_strategic_resource": '"iron"',
            "highland_move_cost_reduction": 1, # Perk: highland move cost reduction
            "melee_attack_bonus_percent": 15,
            "defense_bonus_percent": 10,
            "tree_column": 3,
            "tree_row": 0
        }
    },
    "horse_riding.tres": {
        "script": "res://scripts/data/TechNode.gd",
        "class": "TechNode",
        "fields": {
            "tech_id": '"horse_riding"',
            "title": '"Horse Riding"',
            "description": '"Domesticates horses, reveals Horse resources, and unlocks swift cavalry maneuvers."',
            "science_cost": 55,
            "tier": 4,
            "prerequisites": '["archery"]',
            "unlocked_units": '[]',
            "unlocked_improvements": '["pasture"]',
            "reveals_strategic_resource": '"horses"',
            "highland_move_cost_reduction": 0,
            "melee_attack_bonus_percent": 10,
            "defense_bonus_percent": 0,
            "tree_column": 3,
            "tree_row": 1
        }
    }
}

def write_tres(rel_path, data):
    full_path = os.path.join(base_dir, rel_path)
    os.makedirs(os.path.dirname(full_path), exist_ok=True)
    content = f'''[gd_resource type="Resource" script_class="{data['class']}" load_steps=2 format=3]

[ext_resource type="Script" path="{data['script']}" id="1_res"]

[resource]
script = ExtResource("1_res")
'''
    for k, v in data["fields"].items():
        content += f"{k} = {v}\n"
    with open(full_path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"Wrote {full_path}")

for fname, item in biomes.items():
    write_tres(f"resources/biomes/{fname}", item)

for fname, item in resources.items():
    write_tres(f"resources/strategic_resources/{fname}", item)

for fname, item in improvements.items():
    write_tres(f"resources/improvements/{fname}", item)

for fname, item in units.items():
    write_tres(f"resources/units/{fname}", item)

for fname, item in techs.items():
    write_tres(f"resources/techs/{fname}", item)

print("All .tres resources written successfully.")
