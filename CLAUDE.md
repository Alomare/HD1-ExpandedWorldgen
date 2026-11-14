# Rules for this repository

**Tests:** `luajit tests/run.lua` from the repository root (LuaJIT at `ProjectObsidian/ObsidianLauncher/target/luajit/luajit.exe`). `tests/test_game.lua` runs the game's own compiled generator (`tests/game.lua` loads the `.ljbc` dumps from `ObsidianLauncher/internal/research/scripts`, never committed here) with the mod hooked in; on GitHub those tests skip. After any change to `src/level.lua` or `src/shapes.lua` also run `luajit tools/soak.lua 600`: it must end with `0 with a problem`.

**How it works:** `src/level.lua` wraps the steps of `GeneratedLevel`. The mod makes the outline (`shapes.lua`), says which biome each cell is (`regions.lua`), works out heights and tilts after placement (`relief.lua`) and plans props (`props.lua`); placing objectives and set pieces and tracing the edge stay the game's functions, called on tables the mod prepared. `profile.lua` turns what a rule answered into settled, clamped choices.

**What must hold:**

- Every machine builds the same map. Nothing in a step may use `math.random`, `pairs` order over edited tables (use `grid.sorted`), time, or anything one machine alone knows. The mod's numbers come from `src/rng.lua`, forked by name per step, and a step draws the same count of numbers whatever it then does with them.
- The mod never draws from the game's `self.random`, so the game's steps take the numbers they always took.
- Shapes stay on the lattice of 2 by 2 cell blocks with no blocks joined by a corner alone: the game's edge tracing was only ever run on such areas.
- Lists the game draws from without looking (`common`, `extract`, the three `edge_*` it needs, `mission`) are never left empty.
- A failure in the mod's own part of a step is logged and marks the level `broken`; the rest of that map is then the game's.
- Without a rule, or with a profile that changes nothing, a map is the game's own, piece for piece (a test compares).

**Game facts this rests on** (build 6001293): the level tile is 24 m; positions travel as 16 bits over -1000 to 1000 m; `level_identifier` is 14 bits; the map texture is 1872 px at 72 px a cell on PC; `GeneratedLevel` steps are called one by one from `generate_all`, the briefing's `MapWidget` and the planet screen.

**Flat ground the game assumes** (found with the in-game probe, 2026-11-14), each handled in `level.lua` by telling the game positions from the terrain's height while it looks:

- `SpawnManager` takes a spawn ray's hit only between -0.5 and 1 m (group spawn points -0.2 to 1 m); without the fix the players never dropped and the mission stayed black.
- `NavMeshMoverComponent.move_to_ground` takes ground only below 2 m and at most 0.75 m above an enemy's feet, and answers 0 otherwise: enemies walked under raised ground.
- The camera calls `get_closest_position_on_level` every frame from a point at z 0 and moves by the difference: never answer it with another height.
- A tilted level covers less ground by the cosine of its tilt and shows the dark below at its borders; the ground units at a level's origin take `Unit.set_local_scale` (the engine draws it).
- Engine API tables (`PhysicsWorld`) can have fields replaced; the game's `dofile` reads its bundles, not the disk, and `loadstring` answers nothing. Logging from inside an engine callback (a raycast's) is lost.

**In-game probe** (main PC only, with the user's word; never on the notebook): `internal/probe`. `run.py begin` takes `X:\Projects\Helldivers\Helldivers 1\.game-lock` (shared with other sessions), records the real saves and purges the real library, then deploys Obsidian API, Patches, this mod (packed) and the probe mod into a throwaway data folder; `run.py redeploy [maps key=value ...]` after a change (adds Revamped Maps with options); `run.py end` restores everything and drops the lock. `drive.py <out> launch wait:... cmd:... shot:...` drives the game; `tour.py` plays one practice mission per profile. Probe commands: `profile key=value ...`, `practice time env enemy difficulty [layout]`, `state`, `relief`, `goto_high`, `goto_edge`, `enemies`, `group`, `safe`, `abort`. The probe keeps its own save (`wgprobe_<id>`). Relaunch the game every few missions (see the crash note in `internal/in-game-checks.md`).

**Not confirmed in the game yet:** see `internal/in-game-checks.md`.

**Changelog:** `CHANGELOG.md`, list items starting `- New:`, `- Changed:`, `- Fixed:` or `- Removed:`.
