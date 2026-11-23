-- Units a map would put in the world, from the counts measured in game (tests/data/units.lua):
--   luajit tools/unit_stats.lua [maps]
-- For the largest maps (size 4, every outline, difficulty 12 to 15, every biome and faction): the most
-- units of the map's own pieces, and of its backdrop.
obsidian = { log = function() end }
local loaded = {}
obsidian.module = function(name)
	if loaded[name] == nil then loaded[name] = dofile(name .. ".lua") end
	return loaded[name]
end
local game = dofile("tests/game.lua")
if not game.available then print("the game's scripts aren't here") os.exit(0) end
game.install()
local level = obsidian.module("src/level")
obsidian.hook = function(target, method, fn)
	local t = rawget(_G, target)
	if not t or not t[method] then return end
	local original = t[method]
	t[method] = function(...) return fn(original, ...) end
end
level.log = function() end
level.install(obsidian.hook)
local UNITS = dofile("tests/data/units.lua")

local function units_of(l, e)
	local b = l.wg and l.wg.biomes[e.wg_biome or 1]
	local t = UNITS[b and b.name or l.environment_name] or { avg = 40 }
	return t[e.level_name] or t.avg
end

local maps = tonumber(arg[1]) or 4
local profile
level.rules = { { owner = "stats", fn = function() return profile end } }
local ENVS = { "desert", "forest", "snow", "lava", "city" }
local FACTIONS = { "bugs", "cyborgs", "illuminates" }
local worst = {}
for _, shape in ipairs({ "vanilla", "blob", "ragged", "rectangle", "ring", "cross", "corner", "strip", "islands", "maze" }) do
	for _, biomes in ipairs({ {}, { "any", "any" } }) do
		profile = { id = "stats", size = 4, shape = shape, biomes = biomes, layout = "any", relief = { height = 30, step = 4 }, backdrop = 4 }
		for i, env in ipairs(ENVS) do
			for j = 1, maps do
				local l = game.build(game.seed(400 + i * 13 + j, env, FACTIONS[j % 3 + 1], 11 + j % 5), false)
				local own, back = 0, 0
				local cells = 0
				for _ in pairs(l.collision_map) do cells = cells + 1 end
				for _, e in ipairs(l.spawn_list) do
					if e.wg_backdrop then back = back + units_of(l, e) else own = own + units_of(l, e) end
				end
				local key = env
				if not worst[key] or own > worst[key].own then worst[key] = { own = own, back = back, shape = shape, n = #l.spawn_list, b = #biomes + 1 } end
				local r = own / math.max(1, cells)
				worst[key].per = math.max(worst[key].per or 0, r)
			end
		end
	end
end
for _, env in ipairs(ENVS) do
	local w = worst[env]
	print(string.format("%-7s most units of the map: %6d (%s, %d biomes, %d pieces), its backdrop %6d; most units a cell %.1f", env, w.own, w.shape, w.b, w.n, w.back, w.per))
end
