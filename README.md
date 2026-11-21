# ⚔️ Modern Turn-Based Strategy Game (4X Tactical Engine)
> **Engine:** Godot Engine 4.x (GL Compatibility)  
> **Language:** GDScript  
> **Platforms:** Desktop (Windows/Linux/macOS) & WebAssembly (HTML5)

A comprehensive, decoupled 4X turn-based tactical grand strategy game built from the ground up in **Godot 4**. The game features procedural biome map generation, utility-based AI factions with autonomous diplomacy, a deep tech tree progression system, fog of war, and tactical military unit combat.

---

## 🌟 Key Architecture & Features

### 1. Decoupled Simulation & Core Architecture
- **State Separation:** Simulation logic is strictly isolated from visual presentation (`GameState.gd`, `GridModel.gd`, `CombatEngine.gd`).
- **Headless Testing Support:** Complete standalone test runner suite (`tests/`) capable of running game loop logic, crash assertions, and map generation checks headlessly in CI/CD.

### 2. Procedural Map & Biome Generation
- Dynamic world generator (`MapGenerator.gd`) supporting scalable grid dimensions:
  - Small (28 × 18)
  - Standard (44 × 28)
  - Large (60 × 38)
  - Huge (80 × 50)
- Procedural placement of biomes (Grassland, Plains, Desert, Tundra, Mountains, Oceans), fresh water river networks, strategic luxury resources, and barbarian camps.

### 3. Utility AI & Dynamic Diplomacy
- **Autonomous AI Factions (`SimpleUtilityAI.gd`):** Evaluates utility scores for economic growth, scientific research, territorial expansion, and military defense.
- **Diplomacy & Espionage Engines (`DiplomacyManager.gd`, `EspionageManager.gd`):** Multi-tier relationships (Allied, Friendly, Neutral, Hostile, War) with trade negotiations, border treaties, and spy operations.

### 4. Tactical Gameplay Systems
- **Fog of War & Vision (`FogOfWarLayer.gd`):** True tactical line-of-sight tracking per unit with exploration persistence.
- **Tech Tree Progression (`TechTreeManager.gd`):** Tiered technological eras unlocking advanced military units, naval vessels, and city buildings.
- **Settlement & Borders (`TerritoryLayer.gd`, `CityView.gd`):** Border expansion based on cultural output and population growth.
- **Mobile & Touch-Optimized Camera (`TouchCameraController.gd`):** Smooth inertia pan, pinch-to-zoom, and responsive HUD design.

---

## 🏗️ Directory Structure

```
├── project.godot               # Godot 4 configuration
├── scenes/
│   ├── Main.tscn               # Core game scene orchestrator
│   └── MainMenu.tscn           # Setup menu & map size selector
├── scripts/
│   ├── core/                   # State, Grid, Combat, Diplomacy, MapGen
│   ├── ai/                     # Utility AI decision engine
│   ├── tech/                   # Technology tree logic
│   ├── controllers/            # Camera & player touch/mouse input
│   ├── views/                  # MapView, FogOfWar, Territory, Units
│   └── ui/                     # Reactive HUD, Modals, Tech Tree
└── tests/                      # Automated unit tests & standalone runner
```

---

## 🚀 How to Run

1. Download or clone this repository:
   ```bash
   git clone https://github.com/Bekend/modern-turn-based-strategy-game.git
   ```
2. Open **Godot Engine 4.x**.
3. Click **Import**, navigate to this directory, and select `project.godot`.
4. Press **F5** (or Run Project) to play!

---

## 👤 Author
**Seyed Shahabeddin Hosseini Bay**
- Portfolio: [shahab-hb.ir](https://shahab-hb.ir)
- GitHub: [@Bekend](https://github.com/Bekend)
- Email: [shahabhosseinibay@gmail.com](mailto:shahabhosseinibay@gmail.com)
