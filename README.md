 # Microbe Mayhem — Immune System Defense

 An educational Love2D (LÖVE) tower-defense prototype where immune cells defend a bloodstream. Place innate and adaptive cells, manage nutrients, and survive pathogen waves.

 ## Run the game

 1. Install LÖVE 11.x from https://love2d.org
 2. Clone or download this repository
 3. Run it:
		- Windows: double-click `run-game.bat` (or run `love .` in a terminal)
		- macOS/Linux: in the project folder run `love .`

 ## Controls

 - Mouse: left-click to place a cell; right-click toggles Resting (faster nutrient gain)
 - Keyboard:
	 - `1` Macrophage (innate)
	 - `2` Neutrophil (innate)
	 - `3` T-cell (adaptive; unlocks after ~25s)
	 - `4` B-cell (adaptive; unlocks after ~25s)
	 - `5` Cytotoxic T (adaptive)
	 - `6` NK (innate)
	 - `Space` Spawn wave
	 - `R` Restart
	 - `T` Spawn a tumor enemy (debug); `Shift+T` spawns five

 ## HUD & Info

 - Bottom HUD shows Time, Nutrients, Wave, Health, Resting status, selection, and key help.
 - Right-side panel shows selected cell type details (Cost, Range, Rate, Damage, and specials like Engulf, Durability, Buff/Suppress). Cytotoxic T and NK are marked as able to damage tumor enemies.

 ## Gameplay

 - Nutrients generate over time; Resting increases the rate.
 - The pathogen path is rendered as a bloodstream corridor. Tower placement is blocked within the corridor.
 - Enemies follow an orthogonal winding path along grid-aligned waypoints.
 - If enemies reach the goal, the player loses health. Win by clearing waves.

 ## Immune Cells (towers)

 - Macrophage: engulfs low-HP pathogens (small heal + nutrient gain), applies local AoE slow.
 - Neutrophil: fast burst shooter with limited durability.
 - T-cell: strong projectile (adaptive).
 - B-cell: produces antibody particle projectiles (adaptive).
 - Cytotoxic T: required for killing tumor enemies (adaptive).
 - NK: can kill tumor enemies without prior sensitization (innate).

 Scaffolds (defined, behaviors to expand): Eosinophil, Dendritic, Helper T, Regulatory T.

 ## Tips

 - Use Resting early to build nutrients, then place a mix of innate cells.
 - After ~25s, adaptive cells unlock. Cytotoxic T or NK are needed to handle tumors.
 - Placement is grid-based; avoid the visible path corridor.

 ## Notes

 - Core gameplay resides in `main.lua`; window config in `conf.lua`.
 - The dev container may not support GUI; run locally with LÖVE installed.

Run

Install Love2D (https://love2d.org/) and run from the repository root:

```bash
love .
```

Files added
- `main.lua` — main game prototype
- `conf.lua` — window configuration

Design notes
- Innate towers (macrophage, neutrophil) are available immediately.
- Adaptive towers (T-cell, B-cell) unlock with time to illustrate immune timing.
- Nutrients simulate resource generation; resting increases nutrient gain.
- Pathogens (bacteria, viruses, fungi) vary in health and speed.

Next steps (suggestions)
- Add sound effects and sprites
- Add tutorial overlay explaining innate vs adaptive
- Implement better pathfinding & multiple lanes
- Add scoring and level progression
