-- How much of the asked height the relief reaches, over many maps:
--   luajit tools/relief_stats.lua [height] [rough] [size] [maps]
-- Prints the average and lowest highest ground, overall and on playable cells (the edge left out),
-- and the share of playable cells at a quarter of the height or more.
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

local height, rough, size, maps = tonumber(arg[1]) or 8, tonumber(arg[2]) or 0.55, tonumber(arg[3]) or 1.6, tonumber(arg[4]) or 60
level.rules = { { owner = "stats", fn = function() return { id = "stats", size = size, shape = "any", relief = { height = height, rough = rough } } end } }
local ENVS = { "desert", "forest", "snow", "lava", "city" }
local sum, low, psum, plow, quarter, cells = 0, math.huge, 0, math.huge, 0, 0
local n = 0
for i = 1, maps do
	local l = game.build(game.seed(100 + i, ENVS[i % 5 + 1], "bugs", 3 + i % 10), true)
	local rel = l.wg and l.wg.relief
	if rel then
		n = n + 1
		sum, low = sum + rel.top, math.min(low, rel.top)
		local ptop = 0
		for _, e in ipairs(l.spawn_list) do
			if not e.is_edge and e.wg_pos then
				local h = rel.height((e.x + 0.5) * 24, (e.y + 0.5) * 24)
				ptop = math.max(ptop, h)
				cells = cells + 1
				if h >= height / 4 then quarter = quarter + 1 end
			end
		end
		psum, plow = psum + ptop, math.min(plow, ptop)
	end
end
print(string.format("height %.1f rough %.2f size %.1f: %d maps with relief of %d", height, rough, size, n, maps))
print(string.format("highest ground: average %.1f, lowest %.1f", sum / n, low))
print(string.format("highest playable ground: average %.1f, lowest %.1f", psum / n, plow))
print(string.format("playable pieces at a quarter of the height or more: %.0f%%", 100 * quarter / math.max(1, cells)))
