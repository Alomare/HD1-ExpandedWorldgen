-- Builds many maps with the game's own generator and this mod, and reports what went wrong:
--   luajit tools/soak.lua [maps] [draw]
-- Needs the game's scripts (tests/game.lua). With `draw`, prints the last map of each profile:
-- capital letters are ground by biome (A the planet's own), lower case the edge, digits objectives'
-- pieces, + the extraction.
obsidian = { log = function() end }
local loaded = {}
obsidian.module = function(name)
	if loaded[name] == nil then loaded[name] = dofile(name .. ".lua") end
	return loaded[name]
end

local game = dofile("tests/game.lua")
if not game.available then
	print("the game's scripts aren't here")
	os.exit(0)
end
game.install()
local grid = obsidian.module("src/grid")
local level = obsidian.module("src/level")
obsidian.hook = function(target, method, fn)
	local t = rawget(_G, target)
	if not t or not t[method] then return end
	local original = t[method]
	t[method] = function(...) return fn(original, ...) end
end
local log = {}
level.log = function(text) log[#log + 1] = text end
level.install(obsidian.hook)

local maps = tonumber(arg[1]) or 600
local draw = arg[2] == "draw"
local ENVS = { "desert", "forest", "snow", "lava", "city" }
local ENEMIES = { "bugs", "cyborgs", "illuminates" }
local PROFILES = {
	{ id = "game" },
	{ id = "big", size = 2 },
	{ id = "shapes", shape = "any", size = 1.5 },
	{ id = "small shapes", shape = "any", size = 0.5 },
	{ id = "huge", shape = "any", size = 6 },
	{ id = "mixed", biomes = { "any" }, layout = "any", size = 1.5 },
	{ id = "three biomes", biomes = { "any", "any" }, layout = "any", shape = "any", size = 2 },
	{ id = "hills", relief = { height = 10, rough = 0.8 }, size = 1.5, shape = "any" },
	{ id = "everything", shape = "any", size = 2.5, biomes = { "any", "any" }, layout = "any", relief = 8, backdrop = 2,
		objectives = { scale = 1.5, max = 9 }, props = { { unit = "props/x", per_tile = { 0, 2 } } } },
}

local function picture(l)
	local rows = {}
	for y = l.height + 1, -1, -1 do
		local row = {}
		for x = -1, l.width + 1 do
			local e = l.collision_map[grid.key(x, y)]
			local c = " "
			if e then
				local b = e.wg_biome or 1
				if l.edge_map[grid.key(x, y)] then
					c = string.char(96 + b)
				elseif e.objectives then
					c = e.objectives[1].name == "mission_objective_extract" and "+" or tostring(#e.objectives)
				else
					c = string.char(64 + b)
				end
			end
			row[#row + 1] = c
		end
		rows[#rows + 1] = table.concat(row)
	end
	return table.concat(rows, "\n")
end

local total, bad = 0, 0
for _, p in ipairs(PROFILES) do
	level.rules = { { owner = "soak", fn = function() return p end } }
	if p.id == "game" then level.rules = {} end
	local stats = { maps = 0, errors = 0, open = 0, gave_up = 0, ground = 0, objectives = 0, no_extract = 0, widest = 0, pieces = 0, failed = 0 }
	local last
	for n = 1, maps do
		local env, enemy = ENVS[n % 5 + 1], ENEMIES[n % 3 + 1]
		local seed = game.seed(n % 215, env, enemy, n % 12 + 1, n % 4)
		log = {}
		local ok, l = xpcall(game.build, debug.traceback, seed, n % 2 == 0)
		stats.maps = stats.maps + 1
		if not ok then
			stats.errors = stats.errors + 1
			if stats.errors <= 2 then print(p.id, seed, l) end
		else
			last = l
			for _, line in ipairs(log) do
				if line:find("failed", 1, true) then
					stats.failed = stats.failed + 1
					if stats.failed <= 2 then print(p.id, seed, line) end
				end
			end
			stats.gave_up = stats.gave_up + #game.feed
			stats.pieces = stats.pieces + #l.spawn_list
			stats.widest = math.max(stats.widest, l.width, l.height)
			local open, extract = false, 0
			for k in pairs(l.collision_map) do
				if not l.edge_map[k] then
					stats.ground = stats.ground + 1
					local x, y = grid.unkey(k)
					for dx = -1, 1 do
						for dy = -1, 1 do
							if not l.collision_map[grid.key(x + dx, y + dy)] then open = true end
						end
					end
				end
			end
			for _, e in ipairs(l.spawn_list) do
				for _, o in ipairs(e.objectives or {}) do
					if o.name == "mission_objective_extract" then extract = extract + 1 elseif o.name ~= "mission_objective_droppoint" then stats.objectives = stats.objectives + 1 end
				end
			end
			if open then
				stats.open = stats.open + 1
				if stats.open <= 1 then print(p.id, seed, "open edge\n" .. picture(l)) end
			end
			if extract ~= 1 then stats.no_extract = stats.no_extract + 1 end
		end
	end
	total = total + stats.maps
	bad = bad + stats.errors + stats.open + stats.no_extract + stats.failed
	print(("%-14s maps %d  errors %d  mod steps failed %d  open edges %d  no extraction %d  pieces given up %d  ground %.0f  objectives %.1f  pieces %.0f  widest %d"):format(
		p.id, stats.maps, stats.errors, stats.failed, stats.open, stats.no_extract, stats.gave_up, stats.ground / stats.maps,
		stats.objectives / stats.maps, stats.pieces / stats.maps, stats.widest))
	if draw and last then print(picture(last)) end
end
print(total .. " maps, " .. bad .. " with a problem")
os.exit(bad == 0 and 0 or 1)
