-- How much of the asked height the relief reaches, over many maps:
--   luajit tools/relief_stats.lua [height] [rough] [size] [maps] [step]
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
local grid = obsidian.module("src/grid")
obsidian.hook = function(target, method, fn)
	local t = rawget(_G, target)
	if not t or not t[method] then return end
	local original = t[method]
	t[method] = function(...) return fn(original, ...) end
end
level.log = function() end
level.install(obsidian.hook)

local height, rough, size, maps, step = tonumber(arg[1]) or 8, tonumber(arg[2]) or 0.55, tonumber(arg[3]) or 1.6, tonumber(arg[4]) or 60, tonumber(arg[5])
level.rules = { { owner = "stats", fn = function() return { id = "stats", size = size, shape = "any", relief = { height = height, rough = rough, step = step } } end } }
local ENVS = { "desert", "forest", "snow", "lava", "city" }
local sum, low, psum, plow, quarter, cells, tilt, spread = 0, math.huge, 0, math.huge, 0, 0, 0, 0
local n = 0
for i = 1, maps do
	local l = game.build(game.seed(100 + i, ENVS[i % 5 + 1], "bugs", 3 + i % 10), true)
	local rel = l.wg and l.wg.relief
	if rel then
		n = n + 1
		sum, low = sum + rel.top, math.min(low, rel.top)
		if arg[6] == "locks" then
			local by, all = {}, {}
			for _, e in ipairs(l.spawn_list) do
				local x0, _, x1 = grid.span(e.x, e.y, e.rot or 0, e.size_x or 1, e.size_y or 1)
				for k = x0 + 1, x1 do by[e.wg_cat or "?"] = by[e.wg_cat or "?"] or {}; by[e.wg_cat or "?"][k] = true; all[k] = true end
			end
			local line = {}
			for c, set in pairs(by) do local m = 0; for _ in pairs(set) do m = m + 1 end; line[#line + 1] = c .. "=" .. m end
			local m = 0; for _ in pairs(all) do m = m + 1 end
			print(string.format("x borders %d..%d (%d), locked %d: %s", rel.box[1] + 1, rel.box[3], rel.box[3] - rel.box[1], m, table.concat(line, " ")))
		end
		if arg[6] == "show" and n == 1 then
			local row = {}
			for k = rel.box[1], rel.box[3] + 1 do row[#row + 1] = string.format("%.1f", rel.fx[k]) end
			print("fx: " .. table.concat(row, " "))
		end
		local ptop = 0
		for _, e in ipairs(l.spawn_list) do
			if not e.is_edge and e.wg_pos then
				local h = rel.height((e.x + 0.5) * 24, (e.y + 0.5) * 24)
				ptop = math.max(ptop, h)
				cells = cells + 1
				if h >= height / 4 then quarter = quarter + 1 end
				local a, b = rel.slope((e.x + 0.5) * 24, (e.y + 0.5) * 24)
				tilt = tilt + math.sqrt(a * a + b * b) * 24
				-- The most the ground differs within 3 cells around (what one screen shows).
				local most = 0
				for dx = -3, 3, 3 do for dy = -3, 3, 3 do most = math.max(most, math.abs(rel.height((e.x + 0.5 + dx) * 24, (e.y + 0.5 + dy) * 24) - h)) end end
				spread = spread + most
			end
		end
		psum, plow = psum + ptop, math.min(plow, ptop)
	end
end
print(string.format("height %.1f rough %.2f size %.1f: %d maps with relief of %d", height, rough, size, n, maps))
print(string.format("highest ground: average %.1f, lowest %.1f", sum / n, low))
print(string.format("highest playable ground: average %.1f, lowest %.1f", psum / n, plow))
print(string.format("playable pieces at a quarter of the height or more: %.0f%%", 100 * quarter / math.max(1, cells)))
print(string.format("average slope %.2f m a cell; average most height change within 3 cells (72 m) %.1f m", tilt / math.max(1, cells), spread / math.max(1, cells)))
