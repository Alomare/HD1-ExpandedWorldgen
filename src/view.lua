-- How far the units of a map are drawn. The engine draws every unit in the camera's view however far
-- or small it is, and a map four times the standard one holds about eight times the units: with a
-- long view the frame rate fell to a third (probe, 2026-11-26). Hidden units cost next to nothing.
--
-- Each unit is drawn up to a distance that grows with its size: base + per_metre * radius, times the
-- player's scale. Small stones go first, the ground and cliffs last, as models fade with distance.
-- Distances are from the camera to the nearest point of the piece's cells, so a unit never goes
-- missing at the near side of a wide piece. Units the game tracks (entities: objectives, doors,
-- destructibles) are never touched, and only this player's picture changes: nothing is sent and
-- nothing about the map changes.
--
-- A piece keeps its units sorted by size, largest first; the units drawn are always the first n.
local grid = obsidian.module("src/grid")

local M = {}

M.BASE = 40       -- metres every unit is drawn, at scale 1
M.PER_METRE = 20  -- metres more for each metre of a unit's radius
M.MARGIN = 6      -- metres a unit is kept past its distance before it goes, so it doesn't flicker
M.MIN_SCALE, M.MAX_SCALE = 0.5, 8

-- A piece's record. cells: x0, y0, x1, y1 (inclusive, cells of the map); units: { unit, ... };
-- radii: { radius, ... } in the same order. Answers the record, units sorted largest first.
function M.piece(x0, y0, x1, y1, units, radii)
	local order = {}
	for i = 1, #units do order[i] = i end
	table.sort(order, function(a, b)
		if radii[a] ~= radii[b] then return radii[a] > radii[b] end
		return a < b
	end)
	local p = { x0 = x0 * grid.TILE, y0 = y0 * grid.TILE, x1 = (x1 + 1) * grid.TILE, y1 = (y1 + 1) * grid.TILE, units = {}, radii = {}, n = #units }
	for i, k in ipairs(order) do
		p.units[i], p.radii[i] = units[k], radii[k]
	end
	return p
end

-- Distance in metres from a point to a piece's ground (0 inside it), on the map's plane.
function M.distance(p, x, y)
	local dx = (x < p.x0 and p.x0 - x) or (x > p.x1 and x - p.x1) or 0
	local dy = (y < p.y0 and p.y0 - y) or (y > p.y1 and y - p.y1) or 0
	return math.sqrt(dx * dx + dy * dy)
end

-- How many of a piece's units (largest first) are drawn at distance d.
function M.count(p, d, scale)
	local need = (d / scale - M.BASE) / M.PER_METRE -- the least radius drawn
	if need <= 0 then return #p.units end
	local lo, hi = 0, #p.units -- radii are sorted down: find the last index with radius >= need
	while lo < hi do
		local mid = math.floor((lo + hi + 1) / 2)
		if p.radii[mid] >= need then lo = mid else hi = mid - 1 end
	end
	return lo
end

-- Brings one piece to what the camera at (x, y) should see. show(unit, visible) does the drawing.
-- Answers how many units changed.
function M.update(p, x, y, scale, show)
	local d = M.distance(p, x, y)
	local want = M.count(p, d, scale)
	if want < p.n then
		-- Fewer: only what is past its distance by the margin goes.
		want = math.max(want, M.count(p, math.max(0, d - M.MARGIN), scale))
		if want >= p.n then return 0 end
		for i = want + 1, p.n do show(p.units[i], false) end
	elseif want > p.n then
		for i = p.n + 1, want do show(p.units[i], true) end
	else
		return 0
	end
	local changed = math.abs(want - p.n)
	p.n = want
	return changed
end

-- Every piece shown again (scale off).
function M.reset(p, show)
	for i = p.n + 1, #p.units do show(p.units[i], true) end
	p.n = #p.units
end

function M.clamp_scale(s)
	s = tonumber(s)
	if not s or s <= 0 then return nil end
	return math.max(M.MIN_SCALE, math.min(M.MAX_SCALE, s))
end

return M
