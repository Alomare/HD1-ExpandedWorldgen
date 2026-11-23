-- Ground that rises and falls. The game lays a map from flat pieces of 24 by 24 metres, each a level
-- of its own with a position and a rotation. A piece can be lifted and tilted, never bent, so the
-- ground stays closed only where every piece is one flat plane and neighbours meet along their whole
-- border. That holds exactly when the height is one profile along x plus one along y, each made of
-- straight runs that change slope only on cell borders:
--
--     height(x, y) = F(x) + G(y)
--
-- A piece wider than a cell needs one slope across all of it, so a profile may change slope only on
-- borders no piece crosses. The profiles are drawn after the pieces are placed.
local grid = obsidian.module("src/grid")

local M = {}
local TILE = grid.TILE

-- Borders along one axis that a piece crosses. spans: { {lo, hi}, ... } in cells.
function M.locked_borders(spans)
	local locked = {}
	for i = 1, #spans do
		for k = spans[i][1] + 1, spans[i][2] do locked[k] = true end
	end
	return locked
end

-- The lines where the ground may change slope, chosen before the game places its special pieces,
-- which are then kept between them (level.lua). A profile may only bend on a border no piece crosses,
-- and with the pieces where the game put them nearly every border was crossed somewhere along the
-- map: the ground came out as one or two long flat runs. entries: the pieces placed so far; area:
-- the free cells ({ [key] = true }). Answers { x = { [border] = true }, y = ... }, a line every
-- M.STRIP cells or so, on borders nothing placed so far crosses.
M.STRIP = { 3, 5 }
function M.strips(entries, area, rng)
	local xs, ys = {}, {}
	for i = 1, #entries do
		local e = entries[i]
		local x0, y0, x1, y1 = grid.span(e.x, e.y, e.rot or 0, e.size_x or 1, e.size_y or 1)
		if x1 > x0 then xs[#xs + 1] = { x0, x1 } end
		if y1 > y0 then ys[#ys + 1] = { y0, y1 } end
	end
	local bx0, by0, bx1, by1 = grid.bounds(area)
	local out = {}
	for _, axis in ipairs({ { "x", bx0, bx1, xs }, { "y", by0, by1, ys } }) do
		local name, lo, hi, spans = axis[1], axis[2], axis[3], axis[4]
		local stream, set = rng:fork(name), {}
		if lo then
			local locked = M.locked_borders(spans)
			local at = lo + stream:int(M.STRIP[1], M.STRIP[2])
			while at <= hi do
				-- The nearest free border, at most one cell either way.
				local pick = (not locked[at] and at) or (not locked[at + 1] and at + 1) or (not locked[at - 1] and at - 1)
				if pick then set[pick] = true end
				at = (pick or at) + stream:int(M.STRIP[1], M.STRIP[2])
			end
		end
		out[name] = set
	end
	return out
end

-- One profile: heights at every cell border from c0 to c1 + 1.
-- step: the most a cell rises (metres); top: how high the profile climbs; rough (0 to 1): the share
-- of runs that follow the hills, the others stay level (plateaus).
-- The profile follows waves that rise and fall over the span, from 0 to top, as closely as the step
-- and the locked borders allow. The shortest wave is as short as the step lets it reach top, so a map
-- has hills and valleys a few hundred metres apart. (One or two hills over the whole span, as before,
-- made most of a map one long tilt or a plateau, hard to see in game.)
-- The waves: a main one, and a longer, weaker one that keeps the hills from repeating. A sine of
-- amplitude top / 2 and length L cells rises at most pi top / L a cell; the main wave is a little
-- shorter than that, so the step cuts its slopes into straight runs at the step (steady slopes).
M.WAVES = { { length = 0.7, weight = 1 }, { length = 2.3, weight = 0.4 } }
local function profile(c0, c1, locked, rng, step, top, rough)
	local shortest = math.max(3, math.pi * top / step)
	local waves = {}
	for i, w in ipairs(M.WAVES) do
		waves[i] = { length = shortest * w.length * (0.85 + 0.3 * rng:float()), phase = rng:float() * 2 * math.pi, weight = w.weight }
	end
	local raw, lo, hi = {}, math.huge, -math.huge
	for k = c0, c1 + 1 do
		local v = 0
		for i = 1, #waves do v = v + waves[i].weight * math.sin(2 * math.pi * k / waves[i].length + waves[i].phase) end
		raw[k], lo, hi = v, math.min(lo, v), math.max(hi, v)
	end
	local function target(k)
		if hi - lo < 1e-9 then return 0 end
		return top * (raw[math.max(c0, math.min(c1 + 1, k))] - lo) / (hi - lo)
	end
	local h = target(c0)
	local at = { [c0] = h }
	local c = c0
	while c <= c1 do
		local e = c
		while e < c1 and locked[e + 1] do e = e + 1 end
		local cells = e - c + 1
		local follow = rng:chance(0.35 + 0.65 * rough)
		local slope = 0
		if follow then
			slope = math.max(-step, math.min(step, (target(e + 1) - h) / cells))
		end
		for k = c, e do
			h = h + slope
			at[k + 1] = h
		end
		c = e + 1
	end
	return at
end

local function sample(at, c0, c1, metres)
	local f = metres / TILE
	if f <= c0 then return at[c0] end
	if f >= c1 + 1 then return at[c1 + 1] end
	local k = math.floor(f)
	return at[k] + (at[k + 1] - at[k]) * (f - k)
end

-- entries: the spawn list once the game has re-based it (x, y, rot, size_x, size_y of each piece).
-- box: { min_x, min_y, max_x, max_y } in cells, everything a piece may stand on, edge included.
-- opts: height (metres from the lowest to the highest ground, 6), step (the most one cell rises in
-- metres, 1.25, capped at 5 which is under 12 degrees: a tilted piece is a little shorter across,
-- by the cosine of the tilt, which place() makes up for with a shear), rough (0 to 1, 0.5).
-- Answers a relief: { height = function(x, y) in metres, slope = function(x, y) -> dz/dx, dz/dy,
-- place = function(entry) -> pos, quat, top = highest ground }, or nil when it came out flat.
function M.build(entries, box, rng, opts)
	opts = opts or {}
	local total = math.max(0, math.min(40, tonumber(opts.height) or 6))
	local step = math.max(0.1, math.min(5, tonumber(opts.step) or 1.25))
	local rough = math.max(0, math.min(1, tonumber(opts.rough) or 0.5))
	if total <= 0 then return nil end

	local xs, ys = {}, {}
	for i = 1, #entries do
		local e = entries[i]
		local x0, y0, x1, y1 = grid.span(e.x, e.y, e.rot or 0, e.size_x or 1, e.size_y or 1)
		if x1 > x0 then xs[#xs + 1] = { x0, x1 } end
		if y1 > y0 then ys[#ys + 1] = { y0, y1 } end
	end
	-- Each axis climbs to half the height, so the two together reach it where their hills meet. (Three
	-- quarters each, scaled down to the height afterwards, made every slope a third gentler.) The sum
	-- is still scaled where it goes over; scaling both keeps every piece one plane.
	local fx = profile(box[1], box[3], M.locked_borders(xs), rng:fork("x"), step, total * 0.5, rough)
	local fy = profile(box[2], box[4], M.locked_borders(ys), rng:fork("y"), step, total * 0.5, rough)

	-- Lowest ground at 0.
	local low, high = math.huge, -math.huge
	local lx, hx, ly, hy = math.huge, -math.huge, math.huge, -math.huge
	for k = box[1], box[3] + 1 do lx, hx = math.min(lx, fx[k]), math.max(hx, fx[k]) end
	for k = box[2], box[4] + 1 do ly, hy = math.min(ly, fy[k]), math.max(hy, fy[k]) end
	low, high = lx + ly, hx + hy
	if high - low < 0.01 then return nil end
	local scale = math.min(1, total / (high - low))
	for k = box[1], box[3] + 1 do fx[k] = (fx[k] - lx) * scale end
	for k = box[2], box[4] + 1 do fy[k] = (fy[k] - ly) * scale end
	low, high = 0, (high - low) * scale

	local R = { top = high - low, box = box, fx = fx, fy = fy }

	function R.height(x, y)
		return sample(fx, box[1], box[3], x) + sample(fy, box[2], box[4], y)
	end

	-- The slope of the cell a point is in: metres up per metre along x and along y.
	function R.slope(x, y)
		local cx = math.max(box[1], math.min(box[3], math.floor(x / TILE)))
		local cy = math.max(box[2], math.min(box[4], math.floor(y / TILE)))
		return (fx[cx + 1] - fx[cx]) / TILE, (fy[cy + 1] - fy[cy]) / TILE
	end

	-- Where a piece goes: the position and rotation its level is loaded with, as plain numbers
	-- ({ x, y, z } and { x, y, z, w }), and the shear that draws it (nil on flat ground).
	--
	-- The level is loaded tilted onto its plane, so that its collision follows the slope. A turn
	-- can't lay a square on a slope, though: a tilted piece covers less ground across (the cosine of
	-- the tilt), one tilted both ways is a parallelogram, and its walls lean, so that neighbours with
	-- other tilts part above the ground (seen in game: slits along borders, black wedges between the
	-- cliffs of the edge). What is drawn is the flat piece sheared onto the plane instead: each point
	-- keeps its place across and is lifted by a x + b y. Neighbours then meet exactly along every
	-- border and walls and trees stay upright (the engine draws a sheared pose). The collision stays
	-- the turned one, which leaves slits of a few centimetres on borders (see on_border).
	-- The shear: { a, b (the slope), cx, cy, cz (the middle), pos (the tilted origin), flat (the flat
	-- origin), back (the turn from the tilted level to the flat one) }.
	function R.place(e)
		local rot = e.rot or 0
		local x0, y0, x1, y1 = grid.span(e.x, e.y, rot, e.size_x or 1, e.size_y or 1)
		local cx, cy = (x0 + x1 + 1) * TILE / 2, (y0 + y1 + 1) * TILE / 2
		local a, b = R.slope(cx, cy)
		-- The level's footprint runs from its origin over (size_x, size_y) tiles of its own axes; the
		-- game turns it about the corner that keeps it on its cells, so its middle is the cells' middle.
		local yaw = M.axis_angle(0, 0, 1, rot * math.pi * 0.5)
		local len = math.sqrt(a * a + b * b + 1)
		local nx, ny, nz = -a / len, -b / len, 1 / len
		local tilt = { 0, 0, 0, 1 }
		local axis = math.sqrt(nx * nx + ny * ny)
		if axis > 1e-9 then tilt = M.axis_angle(-ny / axis, nx / axis, 0, math.acos(nz)) end
		local q = M.multiply(tilt, yaw)
		local w, h = (e.size_x or 1) * TILE, (e.size_y or 1) * TILE
		local cz = R.height(cx, cy)
		local ox, oy, oz = M.rotate(q, w / 2, h / 2, 0)
		local pos = { x = cx - ox, y = cy - oy, z = cz - oz }
		local sh
		if a ~= 0 or b ~= 0 then
			local fx, fy = M.rotate(yaw, w / 2, h / 2, 0)
			sh = { a = a, b = b, cx = cx, cy = cy, cz = cz, pos = pos, flat = { x = cx - fx, y = cy - fy, z = cz },
				back = M.multiply(yaw, { -q[1], -q[2], -q[3], q[4] }) }
		end
		return pos, { x = q[1], y = q[2], z = q[3], w = q[4] }, sh
	end

	return R
end

-- Whether a point lies within w metres of a cell border.
function M.on_border(x, y, w)
	local fx, fy = x % TILE, y % TILE
	return math.min(fx, TILE - fx, fy, TILE - fy) <= w
end

-- Where a point p ({ x, y, z }) of the tilted level is drawn under the shear sh (from place).
function M.sheared(sh, p)
	local x, y, z = M.rotate(sh.back, p.x - sh.pos.x, p.y - sh.pos.y, p.z - sh.pos.z)
	x, y, z = sh.flat.x + x, sh.flat.y + y, sh.flat.z + z
	return x, y, z + sh.a * (x - sh.cx) + sh.b * (y - sh.cy)
end

-- A direction or axis v of the tilted level, as the shear draws it.
function M.sheared_axis(sh, v)
	local x, y, z = M.rotate(sh.back, v.x, v.y, v.z)
	return x, y, z + sh.a * x + sh.b * y
end

-- Quaternions as { x, y, z, w }.
function M.axis_angle(x, y, z, angle)
	local s = math.sin(angle / 2)
	return { x * s, y * s, z * s, math.cos(angle / 2) }
end

-- a after b: the rotation that turns by b, then by a.
function M.multiply(a, b)
	return {
		a[4] * b[1] + a[1] * b[4] + a[2] * b[3] - a[3] * b[2],
		a[4] * b[2] - a[1] * b[3] + a[2] * b[4] + a[3] * b[1],
		a[4] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[4],
		a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3],
	}
end

function M.rotate(q, x, y, z)
	local qx, qy, qz, qw = q[1], q[2], q[3], q[4]
	local tx, ty, tz = 2 * (qy * z - qz * y), 2 * (qz * x - qx * z), 2 * (qx * y - qy * x)
	return x + qw * tx + (qy * tz - qz * ty), y + qw * ty + (qz * tx - qx * tz), z + qw * tz + (qx * ty - qy * tx)
end

return M
