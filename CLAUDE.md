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

**Not confirmed in the game yet:** see `internal/in-game-checks.md`.

**Changelog:** `CHANGELOG.md`, list items starting `- New:`, `- Changed:`, `- Fixed:` or `- Removed:`.
