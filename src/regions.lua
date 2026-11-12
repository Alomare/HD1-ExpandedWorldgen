-- Which biome a cell belongs to on a map of several. A layout is a few numbers picked once from the
-- seed; at(x, y) then answers for any cell, ground, edge or beyond, so every step asks the same thing.
-- Cells are asked in blocks of 2 by 2, as the ground is laid, so a border never cuts a block.
local M = {}

M.names = { "split", "bands", "patches", "core" }

local function pick_weighted(rng, weights)
	local total = 0
	for i = 1, #weights do total = total + weights[i] end
	local at = rng:float() * total
	for i = 1, #weights do
		at = at - weights[i]
		if at < 0 then return i end
	end
	return #weights
end

-- count: how many biomes. weights: one number per biome (their share of the ground), or nil.
-- box: { min_x, min_y, max_x, max_y } of the area in cells. Answers { mode, at = function(x, y) }.
function M.build(mode, count, weights, box, rng)
	local cx, cy = (box[1] + box[3] + 1) / 2, (box[2] + box[4] + 1) / 2
	local w, h = box[3] - box[1] + 1, box[4] - box[2] + 1
	local reach = math.max(w, h) / 2
	weights = weights or {}
	local total = 0
	for i = 1, count do
		weights[i] = math.max(0.05, tonumber(weights[i]) or 1)
		total = total + weights[i]
	end
	local layout = { mode = mode, count = count }
	if count <= 1 then
		layout.at = function() return 1 end
		return layout
	end

	local function block(x, y)
		return math.floor(x / 2) * 2 + 1, math.floor(y / 2) * 2 + 1
	end

	if mode == "bands" or mode == "split" then
		-- Stripes across a direction. "split" is the same with a border through the middle, which
		-- for two biomes is two halves.
		local angle = rng:range(0, math.pi)
		local dx, dy = math.cos(angle), math.sin(angle)
		local stripes = mode == "split" and count or math.max(count, rng:int(count, count + 2))
		local order, edges, acc = {}, {}, 0
		for i = 1, stripes do order[i] = (i - 1) % count + 1 end
		if mode == "bands" then rng:shuffle(order) end
		local share = 0
		for i = 1, stripes do share = share + weights[order[i]] end
		for i = 1, stripes do
			acc = acc + weights[order[i]] / share
			edges[i] = acc
		end
		layout.at = function(x, y)
			local bx, by = block(x, y)
			local t = ((bx - cx) * dx + (by - cy) * dy) / (reach * 2 * 0.8) + 0.5
			for i = 1, stripes do
				if t < edges[i] then return order[i] end
			end
			return order[stripes]
		end
	elseif mode == "core" then
		-- The first biome in the middle, the others in rings round it.
		local edges, acc = {}, 0
		for i = 1, count do
			acc = acc + weights[i] / total
			edges[i] = math.sqrt(acc)
		end
		layout.at = function(x, y)
			local bx, by = block(x, y)
			local d = math.sqrt((bx - cx) ^ 2 + (by - cy) ^ 2) / (reach * 1.1)
			for i = 1, count do
				if d < edges[i] then return i end
			end
			return count
		end
	else
		-- Patches: points dropped over the map, each of one biome; a cell takes the nearest point's.
		layout.mode = "patches"
		local points = {}
		local n = math.max(count, math.min(12, math.floor(w * h / 60) + count))
		for i = 1, n do
			-- Every biome gets a point before the weights decide the rest.
			local biome = i <= count and i or pick_weighted(rng, weights)
			points[i] = { rng:range(box[1], box[3] + 1), rng:range(box[2], box[4] + 1), biome }
		end
		layout.at = function(x, y)
			local bx, by = block(x, y)
			local best, best_d = 1, math.huge
			for i = 1, n do
				local d = (points[i][1] - bx) ^ 2 + (points[i][2] - by) ^ 2
				if d < best_d then best, best_d = points[i][3], d end
			end
			return best
		end
	end
	return layout
end

-- A layout moved by (dx, dy) cells: the game re-bases a finished map so its corner is at 0, 0.
function M.shifted(layout, dx, dy)
	local at = layout.at
	return { mode = layout.mode, count = layout.count, at = function(x, y) return at(x + dx, y + dy) end }
end

return M
