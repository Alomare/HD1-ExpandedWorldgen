-- Whole maps, built by the game's own generator (tests/game.lua) with this mod hooked in.
local game = dofile("tests/game.lua")
local grid = obsidian.module("src/grid")
local shapes = obsidian.module("src/shapes")

local T = {}
local function test(name, fn)
	T[#T + 1] = { name, function()
		if not game.available then return "skip" end
		return fn()
	end }
end

local level, baseline
local ENVS = { "desert", "forest", "snow", "lava", "city" }
local ENEMIES = { "bugs", "cyborgs", "illuminates" }

local function signature(l)
	local out = {}
	for i, e in ipairs(l.spawn_list) do
		out[i] = table.concat({ e.level_name, e.x, e.y, e.rot, tostring(e.wg_biome), tostring(e.is_edge) }, ":")
	end
	return table.concat(out, "|")
end

if game.available then
	game.install()
	-- The game's maps before the mod is there, to compare with afterwards.
	baseline = {}
	for i, env in ipairs(ENVS) do
		local seed = game.seed(10 + i, env, ENEMIES[i % 3 + 1], 4 + i)
		baseline[seed] = signature(game.build(seed, true))
	end
	level = obsidian.module("src/level")
	obsidian.hook = function(target, method, fn)
		local t = rawget(_G, target)
		if not t or not t[method] then return end
		local original = t[method]
		t[method] = function(...) return fn(original, ...) end
	end
	level.log = function(text) game.log = game.log or {}; game.log[#game.log + 1] = text end
	level.install(obsidian.hook)
end

local function with_profile(p)
	level.rules = { { owner = "test", fn = function(ctx) return type(p) == "function" and p(ctx) or p end } }
	game.log = {}
end

-- The game itself gives up on a piece that found no room in 100 tries (a wide set piece on a small
-- map), with a line in its feed. `strict` asks for none of that either.
local function no_failures(strict)
	for _, line in ipairs(game.log or {}) do
		yes(not line:find("failed", 1, true), line)
	end
	if strict then eq(#game.feed, 0, "pieces the game gave up placing") end
end

-- What every finished map has to hold, whatever made it.
local function check_map(l, what)
	local ground, edge = 0, 0
	local cells = {}
	for _, e in ipairs(l.spawn_list) do
		if not e.wg_backdrop then
			for _, c in ipairs(grid.cells(e.x, e.y, e.rot, e.size_x, e.size_y)) do cells[grid.key(c[1], c[2])] = true end
		end
	end
	for k, e in pairs(l.collision_map) do
		local x, y = grid.unkey(k)
		yes(x >= 0 and y >= 0 and x < 40 and y < 40, what .. ": inside 40 by 40 cells")
		if l.edge_map[k] then edge = edge + 1 else ground = ground + 1 end
		yes(cells[k], what .. ": every claimed cell has a piece")
	end
	yes(ground >= 16, what .. ": has ground")
	-- Ground never touches the outside: every neighbour of a ground cell, corners included, is
	-- ground or edge.
	for k in pairs(l.collision_map) do
		if not l.edge_map[k] then
			local x, y = grid.unkey(k)
			for dx = -1, 1 do
				for dy = -1, 1 do
					yes(l.collision_map[grid.key(x + dx, y + dy)], what .. ": the edge is closed at " .. (x + dx) .. "," .. (y + dy))
				end
			end
		end
	end
	local extract, objectives = 0, 0
	for _, e in ipairs(l.spawn_list) do
		for _, o in ipairs(e.objectives or {}) do
			if o.name == "mission_objective_extract" then extract = extract + 1 elseif o.name ~= "mission_objective_droppoint" then objectives = objectives + 1 end
		end
	end
	eq(extract, 1, what .. ": one extraction")
	yes(objectives >= 1, what .. ": has objectives")
	return ground, edge, objectives
end

test("without a rule, and with a profile that changes nothing, maps are the game's own", function()
	level.rules = {}
	for seed, want in pairs(baseline) do eq(signature(game.build(seed, true)), want, "seed " .. seed) end
	with_profile({ id = "plain" })
	for seed, want in pairs(baseline) do
		local l = game.build(seed, true)
		eq(l.wg, nil)
		-- The untagged pieces print as the baseline's do.
		eq(signature(l), want, "seed " .. seed)
	end
end)

test("every shape builds a closed map with objectives and an extraction, on every biome", function()
	for s, name in ipairs(shapes.names) do
		with_profile({ id = name, shape = name, size = 1.6 })
		for i, env in ipairs(ENVS) do
			for layout = 1, 3 do
				local seed = game.seed(layout * 7 + s, env, ENEMIES[(i + layout) % 3 + 1], 3 + ((s + i + layout * 3) % 10))
				local l = game.build(seed, false)
				yes(l.wg and l.wg.done, name .. " " .. env .. ": the generator ran")
				check_map(l, name .. " " .. env .. " " .. seed)
				no_failures()
			end
		end
	end
end)

test("size grows the game's own shape, and the limits hold at the largest", function()
	local seed = game.seed(5, "desert", "bugs", 12)
	level.rules = {}
	local plain = check_map(game.build(seed, false), "plain")
	with_profile({ id = "big", size = 2 })
	local big = check_map(game.build(seed, false), "big")
	yes(big > plain * 1.5, "twice the blocks gives well over half again the ground: " .. plain .. " to " .. big)
	with_profile({ id = "huge", size = 8, shape = "blob" })
	local l = game.build(seed, false)
	local huge = check_map(l, "huge")
	yes(l.wg.blocks <= 170 * 1.1, "block limit: " .. l.wg.blocks)
	yes(l.width <= 40 and l.height <= 40, "40 cells across at most")
	no_failures()
end)

test("the same seed gives the same map twice, and the briefing's map is the mission's", function()
	with_profile({ id = "all", shape = "any", size = 1.5, biomes = { "any" }, layout = "any", relief = 6, backdrop = 2,
		props = { { unit = "props/test", per_tile = { 0, 2 } } } })
	for i, env in ipairs(ENVS) do
		local seed = game.seed(40 + i, env, ENEMIES[i % 3 + 1], 6 + i)
		local a = signature(game.build(seed, true))
		local preview = signature(game.build(seed, false))
		local b = signature(game.build(seed, true))
		eq(a, b, env .. " twice")
		eq(preview, a, env .. " briefing")
		no_failures()
	end
end)

test("several biomes: each piece is loaded from its own biome, whose packages are loaded", function()
	with_profile({ id = "mix", size = 1.5, biomes = { "snow", "lava" }, layout = "patches" })
	local seed = game.seed(9, "desert", "cyborgs", 9)
	game.packages = {}
	local l = game.build(seed, true)
	check_map(l, "mix")
	no_failures()
	local paths = { ["env_desert/"] = 0, ["env_snow/"] = 0, ["env_lava/"] = 0 }
	eq(#game.levels, #l.spawn_list)
	for i, e in ipairs(l.spawn_list) do
		local path = l.wg.biomes[e.wg_biome].path
		eq(game.levels[i].path, path .. e.level_name, "the level loaded")
		eq(game.asked[i], path .. e.level_name, "the object sets asked for")
		eq(game.levels[i].data.level_path, path .. e.level_name)
		paths[path] = paths[path] + 1
	end
	for path, n in pairs(paths) do yes(n > 5, path .. " has pieces: " .. n) end
	for _, name in ipairs({ "env_desert/cyborgs", "env_snow/cyborgs", "env_lava/cyborgs", "env_desert/map", "env_snow/map", "env_lava/map", "resource_packages/race_cyborgs" }) do
		yes(game.packages[name], name .. " is loaded")
	end
	yes(l:has_loaded_resources(), "resources count as loaded")
	eq(l:get_package_size_in_bytes(), 40)
	-- Every piece is a piece of the biome it is loaded from, with that faction.
	local settings = rawget(_G, "EnvironmentSettings").mission
	for _, e in ipairs(l.spawn_list) do
		local found = false
		for _, list in pairs(settings[l.wg.biomes[e.wg_biome].name]) do
			if type(list) == "table" then
				for _, m in ipairs(list) do
					if m.name == e.level_name then
						found = true
						yes(not (m.races and m.races[2] == false), e.level_name .. " goes with cyborgs")
					end
				end
			end
		end
		yes(found, e.level_name .. " is a piece of " .. l.wg.biomes[e.wg_biome].name)
	end
	-- The map draws each piece with its biome's material.
	for _, b in ipairs(game.bitmaps) do yes(b.gui and b.gui.material, "a gui with a material") end
	local materials = {}
	for _, b in ipairs(game.bitmaps) do materials[b.gui.material] = true end
	yes(materials["env_desert/map"] and materials["env_snow/map"] and materials["env_lava/map"], "three map materials drawn")
	l:unload_resources()
	yes(not game.packages["env_snow/cyborgs"] and not game.packages["env_snow/map"], "unloaded with the level")
end)

test("several biomes on every planet and faction, every layout", function()
	local n = 0
	for i, env in ipairs(ENVS) do
		for j, enemy in ipairs(ENEMIES) do
			for k, layout in ipairs({ "split", "bands", "patches", "core" }) do
				n = n + 1
				with_profile({ id = "mix", size = 1.3, biomes = { "any", "any" }, layout = layout, shape = (n % 2 == 0) and "any" or "vanilla" })
				local l = game.build(game.seed(n, env, enemy, 2 + (n % 11)), true)
				check_map(l, env .. " " .. enemy .. " " .. layout)
				no_failures()
			end
		end
	end
end)

test("relief: pieces are lifted and tilted, wide ones as one plane, and the edge is single pieces", function()
	with_profile({ id = "hills", size = 1.5, relief = { height = 10, rough = 0.8 } })
	local lifted, tops = 0, {}
	for i, env in ipairs(ENVS) do
		local l = game.build(game.seed(20 + i, env, "bugs", 8), true)
		check_map(l, "hills " .. env)
		no_failures()
		if l.wg.relief then
			yes(l.wg.relief.top <= 10.001)
			tops[#tops + 1] = l.wg.relief.top
			for n, e in ipairs(l.spawn_list) do
				if e.is_edge then eq(e.size_x * e.size_y, 1, "edge piece of one cell") end
				local loaded = game.levels[n]
				eq(loaded.pos.z, e.wg_pos.z)
				eq(loaded.rot.w, e.wg_quat.w)
				eq(loaded.data.pos.z, e.wg_pos.z)
				-- Drawn sheared: the ground at the level's origin sits on the flat spot of that corner at
				-- the ground's height, and the prop 3 m up stands straight above its flat spot.
				local sh = e.wg_shear
				if sh then
					local g, prop = loaded.units[1].pose, loaded.units[2].pose
					near(g.t.z, l.wg.relief.height(g.t.x, g.t.y), 1e-6, "ground on the ground")
					near(g.z.x, 0, 1e-9); near(g.z.y, 0, 1e-9); near(g.z.z, 1, 1e-9, "upright")
					near(prop.t.z - l.wg.relief.height(prop.t.x, prop.t.y), 3, 1e-6, "prop 3 m above the ground under it")
					near(prop.x.x * prop.x.x + prop.x.y * prop.x.y, 1, 1e-9, "the same width across")
				end
				if e.wg_pos.z > 0.5 then lifted = lifted + 1 end
				-- The middle of the piece sits on the ground.
				local x0, y0, x1, y1 = grid.span(e.x, e.y, e.rot, e.size_x, e.size_y)
				local cx, cy = (x0 + x1 + 1) * 12, (y0 + y1 + 1) * 12
				-- Wide pieces span only cells of one slope each way.
				local a, b = l.wg.relief.slope(cx, cy)
				for x = x0, x1 do
					for y = y0, y1 do
						local a2, b2 = l.wg.relief.slope(x * 24 + 12, y * 24 + 12)
						near(a2, a, 1e-9, "one slope along x under " .. e.level_name)
						near(b2, b, 1e-9, "one slope along y under " .. e.level_name)
					end
				end
			end
			-- The camera asks for the closest position from a point on the z 0 plane each frame and moves
			-- by the difference: an answer with any other z sends it climbing without end.
			local p = l:get_closest_position_on_level(rawget(_G, "Vector3")(-50, -50, 0), nil, 0, true)
			eq(p.z, 0, "closest position keeps the z the camera asked with")
			eq(level.height(p.x, p.y), l.wg.relief.height(p.x, p.y))
		end
	end
	yes(lifted > 50, "ground above 0: " .. lifted)
	-- The height asked for is reached, or nearly: in game an 8 m profile once peaked at 3.1 m.
	local sum = 0
	for _, t in ipairs(tops) do sum = sum + t end
	yes(#tops == #ENVS and sum / #tops >= 7, "average highest ground of 10 m asked: " .. sum / math.max(1, #tops))
end)

-- A profile may only bend on borders no piece crosses; with the game's wide pieces placed anywhere
-- nearly every border was crossed and the ground came out as one or two long, nearly flat runs (in
-- game a 12 m map looked flat). The special pieces now stay between lines left free for bends.
test("relief: special pieces leave room for the ground to bend, and the ground slopes", function()
	with_profile({ id = "rugged", size = 1.6, shape = "any", relief = { height = 30, step = 4, rough = 0.8 } })
	local slope, cells, spread = 0, 0, 0
	for i, env in ipairs(ENVS) do
		for j = 1, 3 do
			local l = game.build(game.seed(60 + i * 7 + j, env, "bugs", 3 + j), true)
			check_map(l, "rugged " .. env)
			no_failures()
			local rel = l.wg.relief
			yes(rel and l.wg.strips, "relief and strips")
			-- No special piece crosses a strip line.
			for _, e in ipairs(l.spawn_list) do
				if e.wg_cat == "special" then
					local x0, y0, x1, y1 = grid.span(e.x, e.y, e.rot, e.size_x, e.size_y)
					for k = x0 + 1, x1 do yes(not l.wg.strips.x[k], e.level_name .. " crosses a line along x") end
					for k = y0 + 1, y1 do yes(not l.wg.strips.y[k], e.level_name .. " crosses a line along y") end
				end
				if not e.is_edge then
					local cx, cy = (e.x + 0.5) * 24, (e.y + 0.5) * 24
					local a, b = rel.slope(cx, cy)
					slope, cells = slope + math.sqrt(a * a + b * b) * 24, cells + 1
					local h, most = rel.height(cx, cy), 0
					for ox = -72, 72, 72 do for oy = -72, 72, 72 do most = math.max(most, math.abs(rel.height(cx + ox, cy + oy) - h)) end end
					spread = spread + most
				end
			end
		end
	end
	-- Measured with tools/relief_stats.lua: 1.3 m a cell and 4.5 m within 72 m before the strips.
	yes(slope / cells > 1.8, "average slope " .. slope / cells .. " m a cell")
	yes(spread / cells > 6, "average change within 72 m: " .. spread / cells)
end)

-- SpawnManager takes a ray hit only at the height of flat ground (-0.5 to 1 m for a spawn), so on
-- raised ground the players never dropped and the screen stayed black. A stand-in with the game's
-- check, hooked as the mod hooks the real one.
test("relief: spawns are found on raised ground and land on it", function()
	with_profile({ id = "hills", size = 1.5, relief = { height = 10, rough = 0.8 } })
	local l = game.build(game.seed(31, "desert", "bugs", 8), false)
	level.active = l
	local x, y, top = 0, 0, 0
	for _, e in ipairs(l.spawn_list) do
		local h = l.wg.relief.height(e.x * 24 + 12, e.y * 24 + 12)
		if h > top then x, y, top = e.x * 24 + 12, e.y * 24 + 12, h end
	end
	yes(top > 1.5, "a spot well above the game's window: " .. top)
	local saved = { rawget(_G, "SpawnManager"), rawget(_G, "PhysicsWorld") }
	local rays = {}
	_G.PhysicsWorld = { make_raycast = function(_, callback) rays[#rays + 1] = callback; return {} end }
	_G.SpawnManager = { queue_spawn = function(self, path, pos)
		local entry = { path = path }
		self.queued[#self.queued + 1] = entry
		PhysicsWorld.make_raycast(nil, function(hit, p)
			if hit and p.z > -0.5 and p.z <= 1 then entry.position = Vector3Aux.box({}, p) else entry.failed = true end
		end, "closest")
	end }
	level.install(function(target, method, fn)
		if target ~= "SpawnManager" then return end
		local original = SpawnManager[method]
		if original then SpawnManager[method] = function(...) return fn(original, ...) end end
	end)
	local manager = setmetatable({ queued = {} }, { __index = SpawnManager })
	manager:queue_spawn("player", Vector3(x, y, 0))
	eq(#rays, 1)
	rays[1](true, Vector3(x, y, top))
	local entry = manager.queued[1]
	eq(entry.failed, nil, "the hit on raised ground counts")
	near(entry.position.z, top, 1e-6, "and the spawn stands on it")
	eq(Vector3Aux.box({}, Vector3(1, 2, 3)).z, 3, "box is the game's again afterwards")
	-- A map without relief leaves the game's check as it was.
	l.wg.relief = nil
	manager:queue_spawn("player", Vector3(x, y, 0))
	rays[2](true, Vector3(x, y, top))
	eq(manager.queued[2].failed, true)
	_G.SpawnManager, _G.PhysicsWorld = saved[1], saved[2]
	level.active = nil
end)

-- An enemy's mover takes ground only below 2 m and at most 0.75 m above its feet; on raised ground
-- it answered 0 and enemies walked 2 to 3 m under the ground (seen in game). A stand-in with the
-- game's numbers, hooked as the mod hooks the real one.
test("relief: enemies walk on raised ground, not under it", function()
	with_profile({ id = "hills", size = 1.5, relief = { height = 10, rough = 0.8 } })
	local l = game.build(game.seed(32, "forest", "bugs", 8), false)
	level.active = l
	local rel = l.wg.relief
	local x, y, top = 0, 0, 0
	for _, e in ipairs(l.spawn_list) do
		local h = rel.height(e.x * 24 + 12, e.y * 24 + 12)
		if h > top then x, y, top = e.x * 24 + 12, e.y * 24 + 12, h end
	end
	yes(top > 3, "ground well above the mover's 2 m: " .. top)
	local saved = { rawget(_G, "NavMeshMoverComponent"), rawget(_G, "PhysicsWorld") }
	-- The real ground: a ray down hits the terrain.
	_G.PhysicsWorld = { immediate_raycast = function(_, from) return true, Vector3(from.x, from.y, rel.height(from.x, from.y)), 3, Vector3(0, 0, 1), {} end }
	_G.NavMeshMoverComponent = { move_to_ground = function(self, pos)
		local hit, p = PhysicsWorld.immediate_raycast(nil, Vector3(pos.x, pos.y, pos.z + 3), Vector3(0, 0, -1), 100)
		local z
		if hit then
			local d = p.z - pos.z
			if d < -0.75 * 0.5 then
				z = pos.z
			elseif d < 0.75 and p.z < 2 then
				z = p.z
			end
		end
		return z or 0
	end }
	level.install(function(target, method, fn)
		if target ~= "NavMeshMoverComponent" then return end
		local original = NavMeshMoverComponent[method]
		if original then NavMeshMoverComponent[method] = function(...) return fn(original, ...) end end
	end)
	local mover = setmetatable({}, { __index = NavMeshMoverComponent })
	-- Standing on the ground, and a step along it.
	near(mover:move_to_ground(Vector3(x, y, top)), top, 1e-6, "stays on the ground")
	near(mover:move_to_ground(Vector3(x + 0.3, y + 0.3, top)), rel.height(x + 0.3, y + 0.3), 1e-6, "follows it")
	-- A slit between tilted pieces: the collision has none within 5 cm of a border.
	local solid = PhysicsWorld.immediate_raycast
	PhysicsWorld.immediate_raycast = function(w, from, ...)
		local fx = from.x % 24
		if math.min(fx, 24 - fx) < 0.05 then return false end
		return solid(w, from, ...)
	end
	local bx = math.floor(x / 24) * 24 + 24
	if l.collision_map[grid.key(bx / 24, math.floor(y / 24))] then
		local h = rel.height(bx, y)
		near(mover:move_to_ground(Vector3(bx, y, h)), h, 0.2, "a ray into a slit is cast again beside it")
	end
	PhysicsWorld.immediate_raycast = solid
	local cast = PhysicsWorld.immediate_raycast
	-- Without relief the game's own rule: no ground above 2 m.
	l.wg.relief = nil
	eq(mover:move_to_ground(Vector3(x, y, top)), 0)
	eq(PhysicsWorld.immediate_raycast, cast, "the ray is the game's again")
	_G.NavMeshMoverComponent, _G.PhysicsWorld = saved[1], saved[2]
	level.active = nil
end)

test("the map texture: a wide map is drawn smaller and stays inside the texture", function()
	with_profile({ id = "wide", size = 8, shape = "rectangle", shape_opts = { aspect = 4 } })
	local l = game.build(game.seed(2, "desert", "bugs", 12), false)
	yes(math.max(l.width, l.height) + 2 > 26, "wider than the game's texture holds at 72 pixels: " .. l.width)
	yes(l.map_uv[2].x <= 1 and l.map_uv[1].y >= 0, "uv inside the texture")
	local smallest = math.huge
	for _, b in ipairs(game.bitmaps) do
		yes(b.pos.x >= 0 and b.pos.x <= 1872 and b.pos.y >= 0 and b.pos.y <= 1872, "drawn inside the texture")
		smallest = math.min(smallest, b.size.x)
	end
	yes(smallest < 72 and smallest >= 39, "smaller cells, still readable: " .. smallest)
	-- A map of the game's size is drawn as the game draws it.
	with_profile({ id = "same", shape = "blob" })
	l = game.build(game.seed(2, "desert", "bugs", 5), false)
	for _, b in ipairs(game.bitmaps) do yes(b.size.x % 72 == 0, "72 pixels a cell") end
end)

test("backdrop: rings outside the edge, off the map and off the playable ground; cull hides them", function()
	with_profile({ id = "far", backdrop = 2, cull = 100, props = { { unit = "props/rock", per_tile = 1 } } })
	local l = game.build(game.seed(3, "snow", "illuminates", 7), true)
	check_map(l, "far")
	no_failures()
	local backdrop = 0
	for _, e in ipairs(l.spawn_list) do
		if e.wg_backdrop then
			backdrop = backdrop + 1
			yes(not l.collision_map[grid.key(e.x, e.y)], "not part of the level")
			yes(e.hide_on_map and e.is_edge)
			local m
			for _, x in ipairs(l.environment.edge_fill) do
				if x.name == e.level_name then m = x end
			end
			yes(m and not m.races, "a plain cliff, never a piece with spawners")
		end
	end
	yes(backdrop > 20, "backdrop pieces: " .. backdrop)
	eq(#game.bitmaps, #l.spawn_list - backdrop, "not drawn on the map")
	-- The fake world also holds the map camera; the props are the rule's unit.
	local rocks = {}
	for _, u in ipairs(game.units) do
		if u.unit == "props/rock" then rocks[#rocks + 1] = u end
	end
	yes(#rocks >= 3, "props spawned: " .. #rocks)
	level.cull(-5000, -5000)
	for _, u in ipairs(rocks) do eq(u.shown, false) end
	for n, e in ipairs(l.spawn_list) do
		if e.wg_backdrop then eq(game.levels[n].units[1].shown, false, "backdrop hidden") else eq(game.levels[n].units[1].shown, true, "the game's pieces stay") end
	end
	level.cull(l.width * 12, l.height * 12)
	local shown = 0
	for _, u in ipairs(rocks) do
		if u.shown then shown = shown + 1 end
	end
	yes(shown > 0, "near props shown again")
end)

-- The engine holds at most 65536 units in a world; a Vast map with four rings of backdrop reached
-- about 64600 and the game hung or crashed as the player's gear spawned (seen in game).
test("unit budget: the backdrop stops where the world would pass it, every piece of the map loads", function()
	local budget, step = level.UNIT_BUDGET, level.UNIT_STEP
	yes(budget + step * 2 <= 50000, "room under the engine's 65536 for what a mission spawns")
	with_profile({ id = "wide", size = 4, shape = "ring", backdrop = 4, relief = { height = 30, step = 4 } })
	local seed = game.seed(5, "desert", "bugs", 12)
	local whole = game.build(seed, true)
	local all, rings = 0, 0
	for _, e in ipairs(whole.spawn_list) do
		all = all + 1
		if e.wg_backdrop then rings = rings + 1 end
	end
	-- Each fake level holds 2 units: a budget of the map's units and 20 backdrop pieces' worth.
	level.UNIT_BUDGET, level.UNIT_STEP = (all - rings + 20) * 2, 2
	local l = game.build(seed, true)
	level.UNIT_BUDGET, level.UNIT_STEP = budget, step
	check_map(l, "wide")
	no_failures()
	local kept = 0
	for _, e in ipairs(l.spawn_list) do
		yes(e.level, "every piece left in the list is loaded: " .. e.level_name)
		if e.wg_backdrop then kept = kept + 1 end
	end
	eq(#l.spawn_list - kept, all - rings, "every piece of the map loads")
	yes(kept >= 18 and kept <= 20, "the backdrop stops at the budget: " .. kept .. " of " .. rings)
	eq(l.wg.cut, rings - kept)
	yes(l.wg.world_units <= (all - rings + 20) * 2, "the world within the budget: " .. l.wg.world_units)
end)

-- The map's own pieces always load, so the largest maps are planned to fit: with the units each
-- piece held in game (tests/data/units.lua), no outline at size 4 on any planet, faction or
-- difficulty passes the budget before any backdrop.
test("unit budget: the largest maps of every outline and planet hold no more units than the budget", function()
	local UNITS = dofile("tests/data/units.lua")
	local FACTIONS = { "bugs", "cyborgs", "illuminates" }
	local worst, capped, grown = 0, 0, 0
	for _, shape in ipairs({ "vanilla", "blob", "ring", "cross", "strip", "islands", "maze" }) do
		for i, env in ipairs(ENVS) do
			for j = 1, 2 do
				with_profile({ id = "vast", size = 4, shape = shape, biomes = (j == 2) and { "lava" } or nil, layout = "patches",
					relief = { height = 30, step = 4 }, backdrop = 4 })
				local l = game.build(game.seed(500 + i * 7 + j, env, FACTIONS[(i + j) % 3 + 1], 13 + j), false)
				check_map(l, shape .. " " .. env)
				no_failures()
				local own = 0
				for _, e in ipairs(l.spawn_list) do
					if not e.wg_backdrop then
						local b = l.wg.biomes[e.wg_biome or 1]
						local t = UNITS[b.name] or { avg = 75 }
						own = own + (t[e.level_name] or t.avg)
					end
				end
				worst = math.max(worst, own)
				if l.wg.capped then capped = capped + 1 end
				if (l.wg.blocks or 0) > 30 then grown = grown + 1 end
			end
		end
	end
	yes(worst <= level.UNIT_BUDGET, "most units of a map's own pieces: " .. worst)
	yes(capped > 0, "the heaviest maps were planned smaller")
	yes(grown > 40, "most maps still grew: " .. grown)
end)

test("objectives: the budget scales, a filter narrows the kinds, and an empty filter is ignored", function()
	local seed = game.seed(6, "desert", "bugs", 6)
	level.rules = {}
	local _, _, plain = check_map(game.build(seed, false), "plain")
	with_profile({ id = "more", size = 2, objectives = { scale = 2, max = 12, max_unique = 12 } })
	local _, _, more = check_map(game.build(seed, false), "more")
	yes(more > plain, "more objectives: " .. plain .. " to " .. more)
	local info = rawget(_G, "GeneratedLevelSettings").mission.objective_info
	eq(info.max_objectives, 6, "the game's cap is put back")
	eq(rawget(_G, "DifficultySettings").calculate_mission_points(6), 6, "the game's budget is put back")
	with_profile({ id = "sam", objectives = { filter = function(m) return m.name:find("samsite", 1, true) ~= nil end } })
	local l = game.build(game.seed(6, "desert", "bugs", 4), false)
	for _, e in ipairs(l.spawn_list) do
		if e.wg_cat == "mission" then yes(e.level_name:find("samsite", 1, true), e.level_name) end
	end
	with_profile({ id = "none", objectives = { filter = function() return false end } })
	check_map(game.build(seed, false), "empty filter")
end)

test("open maps skip the set pieces; remix edits one level's lists and can't empty what the game needs", function()
	with_profile({ id = "open", open = true, size = 1.5 })
	local l = game.build(game.seed(8, "lava", "bugs", 9), false)
	check_map(l, "open")
	for _, e in ipairs(l.spawn_list) do
		yes(e.wg_cat ~= "unique" and e.wg_cat ~= "rare" and e.wg_cat ~= "special", e.level_name)
	end
	local before = #rawget(_G, "EnvironmentSettings").mission.desert.special
	with_profile({ id = "remix", shape = "blob", remix = function(env, biome)
		env.special = {}
		env.common = {}
		env.edge_fill = nil
	end })
	l = game.build(game.seed(8, "desert", "bugs", 9), false)
	check_map(l, "remix")
	eq(#rawget(_G, "EnvironmentSettings").mission.desert.special, before, "the game's table is untouched")
	for _, e in ipairs(l.spawn_list) do yes(e.wg_cat ~= "special", "no special pieces") end
end)

test("missions that aren't planet missions are left alone", function()
	with_profile({ id = "all", shape = "ring", size = 2, relief = 6 })
	-- A boss mission: mission type 1 in the seed's tens.
	local seed = 3 * 10000000 + 1000000 + 0 * 10000 + 0 * 100 + 20 + 5
	local l = game.build(seed, false)
	eq(l.wg, nil)
end)

test("a step of the mod that fails mid-way: the map is finished by the game, and pieces still load from their biome", function()
	with_profile({ id = "broken", size = 1.5, biomes = { "snow" }, layout = "split", remix = function(env, biome)
		if biome == "snow" then env.common = { { name = "no_size" } } end
	end })
	local l = game.build(game.seed(4, "desert", "bugs", 9), true)
	yes(l.wg.broken, "marked broken")
	local logged = false
	for _, line in ipairs(game.log) do logged = logged or line:find("common ground failed", 1, true) ~= nil end
	yes(logged, "logged")
	check_map(l, "broken")
	local snow = 0
	for i, e in ipairs(l.spawn_list) do
		eq(game.levels[i].path, l.wg.biomes[e.wg_biome or 1].path .. e.level_name)
		if (e.wg_biome or 1) == 2 then snow = snow + 1 end
	end
	yes(snow > 0, "snow pieces placed before the failure are still snow's")
end)

test("a rule whose mod the loader switched off isn't asked", function()
	local asked = 0
	level.rules = { { owner = "off", on = false, fn = function() asked = asked + 1; return { shape = "ring", size = 2 } end } }
	local seed = next(baseline)
	eq(signature(game.build(seed, true)), baseline[seed])
	eq(asked, 0)
	level.rules[1].on = true
	yes(game.build(seed, true).wg, "asked again once the mod is back on")
end)

test("the library's entry script: a rule follows the session of the mod that adds it", function()
	local listeners, cleared = {}, false
	local saved = { obsidian.hook, obsidian.on_frame, obsidian.session, obsidian.on_session, obsidian.caller }
	obsidian.hook = function() end
	obsidian.on_frame = function() end
	obsidian.caller = function() return "some.mod" end
	obsidian.session = { cleared = function() return cleared end }
	obsidian.on_session = function(fn) listeners[#listeners + 1] = fn end
	level.rules = {}
	local log = level.log
	local api = dofile("main.lua")
	level.log = log
	eq(api.rule("no"), false)
	yes(api.rule(function() return { size = 2 } end))
	eq(level.rules[1].owner, "some.mod")
	eq(level.rules[1].on, false, "off while the lobby isn't cleared for that mod")
	listeners[1](true)
	eq(level.rules[1].on, true)
	yes(#api.shapes() == #shapes.names + 1 and api.shapes()[1] == "vanilla")
	eq(api.height(10, 10), 0)
	obsidian.hook, obsidian.on_frame, obsidian.session, obsidian.on_session, obsidian.caller = saved[1], saved[2], saved[3], saved[4], saved[5]
end)

test("a rule that fails, or a step of the mod that fails, leaves the game's own map", function()
	level.rules = { { owner = "bad", fn = function() error("boom") end } }
	game.log = {}
	local seed = next(baseline)
	eq(signature(game.build(seed, true)), baseline[seed])
	yes(game.log[1] and game.log[1]:find("boom", 1, true), "logged")
end)

return T
