-- How much ground each outline and size gives, against the game's own maps:
--   luajit tools/size_stats.lua [maps]
-- Prints the average count of playable cells (the collision map) and of pieces, per outline and size.
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
local level = obsidian.module("src/level")
obsidian.hook = function(target, method, fn)
	local t = rawget(_G, target)
	if not t or not t[method] then return end
	local original = t[method]
	t[method] = function(...) return fn(original, ...) end
end
level.log = function() end
level.install(obsidian.hook)

local maps = tonumber(arg[1]) or 30
local ENVS = { "desert", "forest", "snow", "lava", "city" }
local profile
level.rules = { { owner = "stats", fn = function() return profile end } }

local function measure(p)
	profile = p
	local cells, pieces, blocks = 0, 0, 0
	for i = 1, maps do
		local l = game.build(game.seed(300 + i, ENVS[i % 5 + 1], "bugs", 3 + i % 10), true)
		for _ in pairs(l.collision_map or {}) do cells = cells + 1 end
		pieces = pieces + #l.spawn_list
		blocks = blocks + (l.wg and l.wg.blocks or 0)
	end
	return cells / maps, pieces / maps, blocks / maps
end

local c, n, b = measure(nil)
print(string.format("%-10s %4s  cells %6.1f  pieces %6.1f", "game", "", c, n))
for _, shape in ipairs({ "vanilla", "blob", "ragged", "rectangle", "ring", "cross", "corner", "strip", "islands", "maze" }) do
	for _, size in ipairs({ 1, 1.6, 2.5, 4 }) do
		c, n, b = measure({ id = "stats", size = size, shape = shape })
		print(string.format("%-10s x%-3.1f  cells %6.1f  pieces %6.1f  blocks %5.1f", shape, size, c, n, b))
	end
end
