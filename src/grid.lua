-- Cell keys as the game's GeneratedLevel makes them (its local fn_8 and fn_9), so the tables this
-- mod fills are the ones the game's own steps read: area_map, collision_map, edge_map.
local M = {}

M.TILE = 24 -- metres across one cell

function M.key(x, y)
	return (x + 1000) + ((y + 1000) * 2000)
end

function M.unkey(k)
	local y = math.floor(k / 2000) - 1000
	return (k % 2000) - 1000, y
end

-- The game's rotation of a cell offset inside a piece (its fn_7): rot 0 to 3, quarter turns.
function M.rotate(dx, dy, rot)
	if rot == 3 then return dy, -dx end
	if rot == 2 then return -dx, -dy end
	if rot == 1 then return -dy, dx end
	return dx, dy
end

-- The cells a placed piece covers: { {x, y}, ... }, skipping the cells its `blocked` mask leaves
-- open (false there means the cell isn't part of the piece). An entry of the spawn list carries
-- size_x and size_y; a module carries size.
function M.cells(x, y, rot, size_x, size_y, blocked)
	local out = {}
	for dx = 0, size_x - 1 do
		for dy = 0, size_y - 1 do
			if not blocked or blocked[dx + dy * size_x + 1] ~= false then
				local rx, ry = M.rotate(dx, dy, rot)
				out[#out + 1] = { x + rx, y + ry }
			end
		end
	end
	return out
end

-- The box of cells a piece spans, mask ignored: min_x, min_y, max_x, max_y.
function M.span(x, y, rot, size_x, size_y)
	local ax, ay = M.rotate(size_x - 1, size_y - 1, rot)
	return math.min(x, x + ax), math.min(y, y + ay), math.max(x, x + ax), math.max(y, y + ay)
end

-- The bounds of a map of keys: min_x, min_y, max_x, max_y, count. nil for an empty map.
function M.bounds(map)
	local x0, y0, x1, y1, n = math.huge, math.huge, -math.huge, -math.huge, 0
	for k in pairs(map) do
		local x, y = M.unkey(k)
		if x < x0 then x0 = x end
		if y < y0 then y0 = y end
		if x > x1 then x1 = x end
		if y > y1 then y1 = y end
		n = n + 1
	end
	if n == 0 then return nil end
	return x0, y0, x1, y1, n
end

-- Keys in a fixed order (by row, then column): pairs() over a table of number keys isn't an order
-- two machines can be trusted to share once the table has been edited differently along the way.
function M.sorted(map)
	local out = {}
	for k in pairs(map) do out[#out + 1] = k end
	table.sort(out)
	return out
end

return M
