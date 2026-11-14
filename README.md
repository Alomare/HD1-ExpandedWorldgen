# Expanded Worldgen

A library for HELLDIVERS (2015) mods, for [Obsidian Launcher](https://github.com/Alomare/ObsidianLauncher).

Expanded Worldgen changes how the maps of planet missions are made: size, outline, several biomes on one map, sloped ground, scattered props and land beyond the map edge. Installed alone, the library changes nothing. A mod gives the library a rule, and the rule answers a profile for each mission.

[Revamped Maps](https://github.com/Alomare/HD1-RevampedMaps) is a mod built on the library, with every feature as an option.

## How it works

The game builds a map in steps: the outline, the objectives, the set pieces, the edge, the plain ground, then the loading of every piece. Every machine in the lobby runs those steps from the mission seed and gets the same map.

Expanded Worldgen wraps each step. The outline and the biome of each part of the ground come from the profile. The placing of objectives and set pieces and the tracing of the edge stay the code of the game, run on the ground the library prepared. Heights, props and backdrop are worked out after the game finished placing, and each piece is then loaded from the biome it belongs to, at the height and tilt the terrain gives it.

Everything is drawn from the mission seed with a random stream of the library, so the briefing map, the mission and every machine agree.

## Using it

```json
"scope": "session",
"every_player": true,
"requires": ["alomare.expandedworldgen"]
```

```lua
local worldgen = obsidian.import("alomare.expandedworldgen")

worldgen.rule(function(mission)
    -- mission: seed, layout, environment, enemy, difficulty, time_of_day, preview
    if mission.environment ~= "snow" then return nil end
    return { shape = "ring", size = 1.5, biomes = { "lava" }, relief = 6 }
end)
```

A rule runs on every machine, for the mission and for the map previews, and must answer the same profile everywhere. Decide from `mission` and from option values every player shares. `"every_player": true` is required: the loader then switches the mod off on every machine while a player is without the mod, and the library stops asking the rule. Rules are asked in the order mods added them, and the first profile answered is used. A rule that answers `nil` leaves the mission to the next rule, or to the game.

## The profile

Every field is optional. Numbers outside the limits are brought inside them.

| Field | Meaning |
| --- | --- |
| `id` | A name for the log |
| `shape` | `"vanilla"` (the outline of the game, the default), `"blob"`, `"ragged"`, `"rectangle"`, `"ring"`, `"cross"`, `"corner"`, `"strip"`, `"islands"`, `"maze"`, `"any"`, or a list to pick from |
| `size` | Ground compared with the map the game would make for the mission, 0.25 to 8. With `"vanilla"` a size above 1 grows the outline of the game |
| `across` | The most blocks of 2 by 2 tiles across, 4 to 19 |
| `max_blocks` | The most blocks of ground, up to 170 |
| `shape_opts` | Knobs of the shape: `aspect`, `width`, `parts`, `inner`, `compact`, `loops` |
| `biomes` | Biomes besides the one of the planet: `"desert"`, `"forest"`, `"snow"`, `"lava"`, `"city"`, `"any"`, or `{ env = "snow", weight = 2 }`. Up to three more |
| `own_weight` | The share of the biome of the planet, 1 by default |
| `layout` | How biomes share the map: `"split"`, `"bands"`, `"patches"`, `"core"`, `"any"` |
| `relief` | Terrain height in metres, or `{ height, step, rough }`: the range from lowest to highest ground (up to 40), the most one tile rises (up to 2), and how often the ground slopes (0 to 1) |
| `objectives` | `{ scale, max, max_unique, filter }`: a multiplier for the objective budget, the caps (6 and 10 in the game), and `filter(piece, mission)` answering whether an objective piece may be used |
| `open` | `true` leaves out the set pieces, for open ground |
| `remix` | `function(lists, biome, mission)` edits the piece lists of this one level: `mission`, `unique`, `rare`, `special`, `children`, `common`, `extract`, `droppoint`, `edge_straight`, `edge_fill`, `edge_concave`, `edge_convex` |
| `props` | Units scattered on the map: `{ unit, per_tile = { min, max }, chance, margin, on = { "common" }, biomes, lift }` |
| `packages` | Packages to load with the map, for props that are not in the packages of the mission |
| `backdrop` | Rows of cliff pieces outside the edge, 0 to 4, or `{ rings }` |
| `cull` | Distance in metres beyond which backdrop pieces and props are hidden |

A piece in `remix` is a table as in the `EnvironmentSettings` of the game: `name` (a level under the path of the biome), `size`, and what the kind of piece needs. A mod that ships levels of its own adds them here.

## Other calls

| Call | Answers |
| --- | --- |
| `worldgen.shapes()`, `layouts()`, `biomes()` | The names a profile may use |
| `worldgen.height(x, y)` | The ground height at a world position in the mission being played, 0 on a flat map |
| `worldgen.current()` | What the generator did for the mission being played: `{ profile, blocks, biomes, top }`, or `nil` for a map of the game |

## Limits

- Planet missions only. Boss missions, Retaliatory Strikes and Proving Grounds keep the maps of the game.
- A map is 40 tiles across at most, edge included (960 metres). The game sends positions as 16 bits over 1000 metres each way.
- Terrain height is the sum of one profile along each axis, because the game lays flat pieces that can be lifted and tilted but not bent. A tilted piece is slightly shorter across, which leaves a slit of a few centimetres at the borders of steep pieces.
- Only one lighting setup and one sound environment per map, those of the planet.
- A prop unit must be in a loaded package. Spawning a unit from a package that is not loaded stops the game.
- A set piece that finds no room in 100 tries is left out, as in the game. Small parts of a map with several biomes lose more of them.

## Tests

`luajit tests/run.lua` from the repository root. `tests/test_game.lua` builds whole maps by running the compiled scripts of the game on a stand-in for the engine, and is skipped where those scripts are not on the machine (`WORLDGEN_GAME_SCRIPTS` names the folder). `luajit tools/soak.lua 600 draw` builds thousands of maps and prints a sample of each kind.
