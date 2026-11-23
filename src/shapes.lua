-- The outline of a map: which cells are ground. Shapes are made of blocks of 2 by 2 cells on an
-- even lattice, as the game's own areas are, so that the game's edge step, which this mod keeps,
-- meets only what it meets on a map of the game: every gap and every hole is at least 2 cells wide.
--
-- Everything here is plain Lua on plain tables: a shape is a set of block keys (grid.key(bx, by)).
local grid = obsidian.module("src/grid")

local M = {}

local key, unkey = grid.key, grid.unkey
local NEIGHBOURS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- The most blocks across a map: 19 blocks are 38 cells, 40 with the edge, 960 metres. The game
-- sends positions as 16 bits over -1000 to 1000 metres, and a map starts at 0.
M.MAX_ACROSS = 19

local function inside(bx, by, half)
	return bx >= -half and bx < half and by >= -half and by < half
end

local function count(set)
	local n = 0
	for _ in pairs(set) do n = n + 1 end
	return n
end
M.count = count

-- The cells a map of n blocks covers with its edge, about INNER n + EDGE sqrt(n): fitted on maps
-- of 10 to 60 blocks (tools/size_stats.lua; the game's own are about 10 blocks, 106 cells).
M.INNER, M.EDGE = 3, 25
local function footprint(n) return M.INNER * n + M.EDGE * math.sqrt(n) end

-- The blocks that give size times the footprint of a map of n0 blocks: the size of a map is the
-- ground it covers on the map screen, edge and all. Growing only the blocks inside made a map of
-- size 4 cover 2.4 times the game's ground.
-- The cells a set of blocks covers with the game's edge, which runs two cells wide around the
-- ground (the game's own maps: 39 cells of ground, about 105 with the edge).
function M.footprint_cells(set)
	local cells = {}
	for k in pairs(set) do
		local bx, by = unkey(k)
		for dx = -2, 3 do
			for dy = -2, 3 do cells[key(bx * 2 + dx, by * 2 + dy)] = true end
		end
	end
	return count(cells)
end

-- The most blocks whose footprint stays within the given cells.
function M.most_blocks(cells)
	if cells <= footprint(1) then return 1 end
	local root = (-M.EDGE + math.sqrt(M.EDGE * M.EDGE + 4 * M.INNER * cells)) / (2 * M.INNER)
	return math.max(1, math.floor(root * root))
end

function M.blocks_for(n0, size)
	-- Smaller than the game's: the blocks shrink as they did, so the extraction still finds room.
	if size <= 1 then return math.floor(n0 * size + 0.5) end
	local target = footprint(n0) * size
	local root = (-M.EDGE + math.sqrt(M.EDGE * M.EDGE + 4 * M.INNER * target)) / (2 * M.INNER)
	return math.floor(root * root + 0.5)
end

local function filled_neighbours(set, bx, by)
	local n = 0
	for i = 1, 4 do
		if set[key(bx + NEIGHBOURS[i][1], by + NEIGHBOURS[i][2])] then n = n + 1 end
	end
	return n
end

-- Grows `set` to n blocks, a block at a time from its border. compact (0 to 1) favours blocks with
-- more neighbours, which rounds the shape; 0 leaves it ragged.
function M.grow(set, n, rng, half, compact)
	compact = compact or 0.5
	local have = count(set)
	if have == 0 then
		set[key(0, 0)] = true
		have = 1
	end
	local frontier, listed = {}, {}
	local function offer(bx, by)
		local k = key(bx, by)
		if not set[k] and not listed[k] and inside(bx, by, half) then
			listed[k] = true
			frontier[#frontier + 1] = k
		end
	end
	for _, k in ipairs(grid.sorted(set)) do
		local bx, by = unkey(k)
		for i = 1, 4 do offer(bx + NEIGHBOURS[i][1], by + NEIGHBOURS[i][2]) end
	end
	while have < n and #frontier > 0 do
		-- Two candidates, the better connected one wins as often as `compact` says.
		local i = rng:int(1, #frontier)
		if compact > 0 and #frontier > 1 and rng:chance(compact) then
			local j = rng:int(1, #frontier)
			local ax, ay = unkey(frontier[i])
			local bx, by = unkey(frontier[j])
			if filled_neighbours(set, bx, by) > filled_neighbours(set, ax, ay) then i = j end
		end
		local k = frontier[i]
		frontier[i] = frontier[#frontier]
		frontier[#frontier] = nil
		listed[k] = nil
		set[k] = true
		have = have + 1
		local bx, by = unkey(k)
		for d = 1, 4 do offer(bx + NEIGHBOURS[d][1], by + NEIGHBOURS[d][2]) end
	end
	return set
end

local function fill_rect(set, x0, y0, x1, y1, half)
	for bx = x0, x1 do
		for by = y0, y1 do
			if inside(bx, by, half) then set[key(bx, by)] = true end
		end
	end
end

local function round(v)
	return math.floor(v + 0.5)
end

local builders = {}

function builders.blob(n, rng, half, o)
	return M.grow({}, n, rng, half, o.compact or 0.6)
end

function builders.ragged(n, rng, half)
	return M.grow({}, n, rng, half, 0)
end

function builders.rectangle(n, rng, half, o)
	local aspect = o.aspect or rng:range(1, 2.4)
	local w = math.max(2, math.min(half * 2, round(math.sqrt(n * aspect))))
	local h = math.max(2, math.min(half * 2, round(n / w)))
	if rng:chance(0.5) and not o.aspect then w, h = h, w end
	local set = {}
	fill_rect(set, -math.floor(w / 2), -math.floor(h / 2), -math.floor(w / 2) + w - 1, -math.floor(h / 2) + h - 1, half)
	return set
end

-- A band of ground around a hole. The hole is at least 2 blocks across.
function builders.ring(n, rng, half, o)
	local inner = o.inner or 0.5
	local outer = math.sqrt(n / (math.pi * (1 - inner * inner)))
	outer = math.min(outer, half - 0.5)
	local hole = math.max(1.2, outer * inner)
	local sx = o.aspect or rng:range(0.8, 1.25)
	local set = {}
	for bx = -half, half - 1 do
		for by = -half, half - 1 do
			local cx, cy = (bx + 0.5) / sx, (by + 0.5) * sx
			local d = math.sqrt(cx * cx + cy * cy)
			if d <= outer and d >= hole then set[key(bx, by)] = true end
		end
	end
	return set
end

function builders.cross(n, rng, half, o)
	local w = o.width or math.max(2, round(math.sqrt(n / 6)))
	local len = math.min(half * 2, math.max(w + 2, round((n + w * w) / (2 * w))))
	local set = {}
	local a, b = -math.floor(w / 2), -math.floor(len / 2)
	fill_rect(set, b, a, b + len - 1, a + w - 1, half)
	fill_rect(set, a, b, a + w - 1, b + len - 1, half)
	return set
end

-- Two arms meeting at a corner.
function builders.corner(n, rng, half, o)
	local w = o.width or math.max(2, round(math.sqrt(n / 5)))
	local len = math.min(half * 2, math.max(w + 2, round((n + w * w) / (2 * w))))
	local set = {}
	local b = -math.floor(len / 2)
	fill_rect(set, b, b, b + len - 1, b + w - 1, half)
	fill_rect(set, b, b, b + w - 1, b + len - 1, half)
	return set
end

-- A long, narrow run of ground that wanders: a canyon floor.
function builders.strip(n, rng, half, o)
	local w = o.width or math.max(2, round(math.sqrt(n / 9)))
	local set = {}
	local horizontal = rng:chance(0.5)
	local along, across = -half, -math.floor(w / 2)
	local drift = 0
	while count(set) < n and along < half do
		if rng:chance(0.45) then
			drift = drift + rng:int(-1, 1)
			drift = math.max(-1, math.min(1, drift))
			across = math.max(-half, math.min(half - w, across + drift))
		end
		for i = 0, w - 1 do
			local bx, by = along, across + i
			if not horizontal then bx, by = by, bx end
			if inside(bx, by, half) then set[key(bx, by)] = true end
		end
		along = along + 1
	end
	return set
end

-- Several fields joined by paths one block wide.
function builders.islands(n, rng, half, o)
	local parts = o.parts or rng:int(3, 5)
	local reach = math.min(half - 2, math.max(3, round(math.sqrt(n) * 0.75)))
	local turn = rng:range(0, math.pi * 2)
	local set, centres = {}, {}
	for i = 1, parts do
		local a = turn + (i - 1) * math.pi * 2 / parts
		centres[i] = { round(math.cos(a) * reach), round(math.sin(a) * reach) }
	end
	-- Paths first, each to the next field round the circle, so the fields can't end up apart.
	for i = 1, parts do
		local from, to = centres[i], centres[i % parts + 1]
		if parts == 2 and i == 2 then break end
		local bx, by = from[1], from[2]
		while bx ~= to[1] or by ~= to[2] do
			if inside(bx, by, half) then set[key(bx, by)] = true end
			if bx ~= to[1] and (by == to[2] or rng:chance(0.5)) then
				bx = bx + (to[1] > bx and 1 or -1)
			else
				by = by + (to[2] > by and 1 or -1)
			end
		end
	end
	local each = math.max(2, math.floor((n - count(set)) / parts))
	for i = 1, parts do
		local field = { [key(centres[i][1], centres[i][2])] = true }
		M.grow(field, each, rng, half, 0.8)
		for k in pairs(field) do set[k] = true end
	end
	return set
end

-- Corridors one block wide between rooms on every other block, with a few ways round.
function builders.maze(n, rng, half, o)
	local reach = math.floor((half - 1) / 2)
	local set = { [key(0, 0)] = true }
	local stack = { { 0, 0 } }
	local visited = { [key(0, 0)] = true }
	local blocks = 1
	while #stack > 0 and blocks < n do
		local at = stack[rng:chance(0.7) and #stack or rng:int(1, #stack)]
		local ways = {}
		for i = 1, 4 do
			local rx, ry = at[1] + NEIGHBOURS[i][1], at[2] + NEIGHBOURS[i][2]
			if math.abs(rx) <= reach and math.abs(ry) <= reach and not visited[key(rx, ry)] then ways[#ways + 1] = i end
		end
		if #ways == 0 then
			for i = 1, #stack do
				if stack[i] == at then
					table.remove(stack, i)
					break
				end
			end
		else
			local d = NEIGHBOURS[ways[rng:int(1, #ways)]]
			local rx, ry = at[1] + d[1], at[2] + d[2]
			visited[key(rx, ry)] = true
			set[key(at[1] * 2 + d[1], at[2] * 2 + d[2])] = true
			set[key(rx * 2, ry * 2)] = true
			blocks = blocks + 2
			stack[#stack + 1] = { rx, ry }
		end
	end
	-- Ways round: a wall between two rooms that both exist comes down now and then.
	local loops = o.loops or 0.12
	for _, k in ipairs(grid.sorted(set)) do
		local bx, by = unkey(k)
		if bx % 2 == 0 and by % 2 == 0 then
			for i = 1, 3, 2 do
				local d = NEIGHBOURS[i]
				if set[key(bx + d[1] * 2, by + d[2] * 2)] and not set[key(bx + d[1], by + d[2])] and rng:chance(loops) then
					set[key(bx + d[1], by + d[2])] = true
				end
			end
		end
	end
	return set
end

M.names = { "blob", "ragged", "rectangle", "ring", "cross", "corner", "strip", "islands", "maze" }

-- Two blocks that touch only at a corner, with the other two of the four empty, leave the edge a
-- knot the game's maps don't have. One of the empty two is filled.
function M.unpinch(set, rng, half)
	local changed = true
	while changed do
		changed = false
		for _, k in ipairs(grid.sorted(set)) do
			local bx, by = unkey(k)
			for sx = -1, 1, 2 do
				if set[key(bx + sx, by + 1)] and not set[key(bx + sx, by)] and not set[key(bx, by + 1)] then
					local fx, fy = bx + sx, by
					if rng:chance(0.5) or not inside(fx, fy, half) then fx, fy = bx, by + 1 end
					if not inside(fx, fy, half) then fx, fy = bx + sx, by end
					set[key(fx, fy)] = true
					changed = true
				end
			end
		end
	end
	return set
end

-- The part of `set` joined to its biggest piece; the rest is dropped.
function M.connected(set)
	local seen, best, best_n = {}, nil, 0
	for _, k in ipairs(grid.sorted(set)) do
		if not seen[k] then
			local part, queue, n = { [k] = true }, { k }, 1
			seen[k] = true
			local at = 1
			while at <= #queue do
				local bx, by = unkey(queue[at])
				at = at + 1
				for i = 1, 4 do
					local nk = key(bx + NEIGHBOURS[i][1], by + NEIGHBOURS[i][2])
					if set[nk] and not seen[nk] then
						seen[nk] = true
						part[nk] = true
						queue[#queue + 1] = nk
						n = n + 1
					end
				end
			end
			if n > best_n then best, best_n = part, n end
		end
	end
	return best or {}
end

-- A shape by name with about n blocks. opts: the shape's own knobs (aspect, width, parts, inner,
-- compact, loops) and across, the most blocks across (MAX_ACROSS at most).
function M.build(name, n, rng, opts)
	opts = opts or {}
	local across = math.max(4, math.min(M.MAX_ACROSS, math.floor(opts.across or M.MAX_ACROSS)))
	local half = math.floor(across / 2)
	n = math.max(4, math.min(math.floor(n), half * half * 4))
	local build = builders[name] or builders.blob
	local set = build(n, rng, half, opts)
	set = M.connected(M.unpinch(set, rng, half))
	-- A shape that came out short (a rectangle clipped by the limit, a maze out of room) is topped
	-- up from its border; one that came out long stays as it is.
	local short = (name == "ring" or name == "maze") and 0.4 or 0.85
	if count(set) < math.max(4, n * short) then
		M.grow(set, n, rng, half, 0.7)
		set = M.connected(M.unpinch(set, rng, half))
	end
	return set
end

-- Blocks to the game's tables. area: { [cell key] = true }; lookup: the same cells as a list, in a
-- fixed order. Answers min_x, max_x, min_y, max_y of the first cell of each block, which is what the
-- game's area steps answer (GeneratedLevel.generate_area adds 2 for the width).
function M.to_area(set, area, lookup)
	local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
	for _, k in ipairs(grid.sorted(set)) do
		local bx, by = unkey(k)
		local x, y = bx * 2, by * 2
		for dx = 0, 1 do
			for dy = 0, 1 do
				local ck = key(x + dx, y + dy)
				if not area[ck] then
					area[ck] = true
					lookup[#lookup + 1] = ck
				end
			end
		end
		if x < x0 then x0 = x end
		if x > x1 then x1 = x end
		if y < y0 then y0 = y end
		if y > y1 then y1 = y end
	end
	return x0, x1 + 1, y0, y1 + 1
end

-- The blocks of an area the game made, or nil when the area isn't on the even lattice (the one cell
-- of a Retaliatory Strike map, say), which this mod then leaves alone.
function M.from_area(area)
	local set = {}
	for k in pairs(area) do
		local x, y = unkey(k)
		local bx, by = math.floor(x / 2), math.floor(y / 2)
		set[key(bx, by)] = true
	end
	for k in pairs(set) do
		local bx, by = unkey(k)
		for dx = 0, 1 do
			for dy = 0, 1 do
				if not area[key(bx * 2 + dx, by * 2 + dy)] then return nil end
			end
		end
	end
	return set
end

return M
