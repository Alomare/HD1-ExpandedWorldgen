-- Things a profile scatters over the map on top of what the pieces hold: where each one goes is
-- worked out from the seed, so every machine puts the same thing in the same place.
local grid = obsidian.module("src/grid")

local M = {}
local TILE = grid.TILE

M.MAX = 600 -- units a map takes at most, whatever the rules ask for

local function has(list, value)
	for i = 1, #list do
		if list[i] == value then return true end
	end
	return false
end

-- entries: the finished spawn list, each tagged by the level code with wg_cat (which step placed
-- it) and wg_biome. rules: the settled profile's props. biomes: { { env = ... }, ... }.
-- Answers { { unit, x, y, yaw, lift }, ... } in metres and radians.
function M.plan(entries, rules, biomes, rng)
	local out = {}
	for r = 1, #rules do
		local rule = rules[r]
		local stream = rng:fork("prop" .. r)
		for i = 1, #entries do
			local e = entries[i]
			local env = biomes[e.wg_biome or 1] and biomes[e.wg_biome or 1].env
			if (e.size_x or 1) == 1 and (e.size_y or 1) == 1 and has(rule.on, e.wg_cat or "") and (not rule.biomes or has(rule.biomes, env)) then
				-- The draws are made for every piece that qualifies, kept or not, so one rule's
				-- chance never moves where another piece's things land.
				local keep = stream:chance(rule.chance)
				local n = stream:int(rule.min, math.max(rule.min, rule.max))
				for _ = 1, n do
					local x = e.x * TILE + stream:range(rule.margin, TILE - rule.margin)
					local y = e.y * TILE + stream:range(rule.margin, TILE - rule.margin)
					local yaw = stream:range(0, math.pi * 2)
					if keep and #out < M.MAX then
						out[#out + 1] = { unit = rule.unit, x = x, y = y, yaw = yaw, lift = rule.lift }
					end
				end
			end
		end
	end
	return out
end

return M
