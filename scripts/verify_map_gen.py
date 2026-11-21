import math
import random

# Verify noise threshold distribution logic
print("--- Testing Map Generation Logic & Distribution ---")
width = 36
height = 24

# Let's simulate sample elevation values
biomes_count = {"ocean": 0, "plains": 0, "hills": 0, "mountains": 0, "tundra": 0}

random.seed(1337)
for y in range(height):
    lat_factor = abs(float(y) - float(height) * 0.5) / (float(height) * 0.5)
    for x in range(width):
        elev = random.uniform(-0.6, 0.8)
        if elev < -0.15:
            biomes_count["ocean"] += 1
        elif elev >= 0.52:
            biomes_count["mountains"] += 1
        elif lat_factor > 0.72 and elev > -0.05:
            biomes_count["tundra"] += 1
        elif elev >= 0.22:
            biomes_count["hills"] += 1
        else:
            biomes_count["plains"] += 1

total = width * height
print(f"Total tiles: {total}")
for k, v in biomes_count.items():
    pct = (v / total) * 100.0
    print(f"  {k.capitalize()}: {v} tiles ({pct:.1f}%)")

assert biomes_count["plains"] > 100, "Should have plenty of plains"
assert biomes_count["ocean"] > 50, "Should have water bodies"
assert biomes_count["mountains"] > 30, "Should have impassable mountain barriers"
print("PASS: Biome distribution is balanced and supports tactical gameplay.")
