# Changelog

New, changed, fixed or removed features, one line each, brief and direct. The section for a release becomes the release notes.

## Next

- New: units far from the camera are hidden by their size, small ones first, so the largest maps keep their frame rate with a long view. Only the picture of each player changes.

## 0.3.0

- Fixed: the largest maps with land beyond the edge hung, went black or crashed the game as the mission started, past the 65536 units the game holds in a world.
- Changed: a map is planned no larger than the game can load, so the largest maps of lava and desert planets come out somewhat smaller than the size asked.
- Changed: rows of land beyond the edge stop where the map would load too much.

## 0.2.0

- Changed: terrain height makes hills and valleys a few hundred metres apart across the whole map, where most maps had one long, gentle tilt.
- Changed: special set pieces keep to strips between the lines where the ground bends, so a map keeps room for slopes.

## 0.1.0

- New: rules that give each planet mission a map profile, the same on every machine.
- New: map size up to eight times the standard ground, to a limit of 40 tiles across.
- New: nine map outlines besides the standard one.
- New: up to four biomes on one map, each with ground, set pieces, cliffs and map art of that biome.
- New: terrain height, with pieces lifted and tilted into slopes and plateaus.
- New: objective budget, caps and filter per profile.
- New: scattered props, extra packages, and rows of cliffs beyond the map edge.
- New: the briefing and HUD map fits maps wider than 26 tiles.
