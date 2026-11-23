-- One mission seed through the game's generator with Revamped Maps options, offline:
--   luajit tools/repro.lua <seed> [key=value ...] [dbg=flag,flag]
-- keys as Revamped Maps: map_size, shape, biomes, biome_layout, relief, backdrop, more_objectives.
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
level.log = function(s) print("log: " .. s) end
level.install(obsidian.hook)

local seed = tonumber(arg[1])
local opts = { map_size = "vast", shape = "varied", biomes = "two", biome_layout = "varied", relief = "rugged", backdrop = 4, more_objectives = false }
local dbg = {}
for i = 2, #arg do
	local k, v = arg[i]:match("^(%w+)=(.*)$")
	if k == "dbg" then for f in v:gmatch("[^,]+") do dbg[f] = true end
	elseif k then opts[k] = tonumber(v) or (v == "true" and true) or (v == "false" and false) or v end
end
rawset(_G, "WG_DEBUG", dbg)
local rule = dofile("../../Session/RevampedMaps/src/rule.lua")
local profile = rule.profile(function(id) return opts[id] end)
level.rules = { { owner = "repro", fn = function() return profile end } }
local started = os.clock()
local ok, l = pcall(game.build, seed, true)
if not ok then print("ERROR " .. tostring(l)) os.exit(1) end
local edges, backdrop = 0, 0
for _, e in ipairs(l.spawn_list) do
	if e.is_edge and not e.wg_backdrop then edges = edges + 1 end
	if e.wg_backdrop then backdrop = backdrop + 1 end
end
print(string.format("seed %d: %d pieces (%d edge, %d backdrop), %.1f s, top %.1f, broken %s", seed, #l.spawn_list, edges, backdrop,
	os.clock() - started, l.wg and l.wg.relief and l.wg.relief.top or 0, tostring(l.wg and l.wg.broken)))
