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
local function locked_borders(spans)
	local locked = {}
	for i = 1, #spans do
		for k = spans[i][1] + 1, spans[i][2] do locked[k] = true end
	end
	return locked
end

-- One profile: heights at every cell border from c0 to c1 + 1.
-- step: the most a cell rises (metres); top: how high the profile climbs; rough (0 to 1): the share
-- of runs that follow the hills, the others stay level (plateaus).
-- The profile follows one or two hills placed along the span, each reaching top, as closely as the
-- step and the locked borders allow. (A random walk, as before, seldom got past half of top.)
local function profile(c0, c1, locked, rng, step, top, rough)
	local n = c1 - c0 + 1
	local hills = rng:chance(0.5) and 1 or 2
	local peaks = {}
	for i = 1, hills do peaks[i] = c0 + (i - 1 + 0.2 + 0.6 * rng:float()) * n / hills end
	local width = n / hills * 0.45
	local function target(k)
		local t = 0
		for i = 1, hills do
			local d = (k - peaks[i]) / width
			t = math.max(t, math.exp(-d * d))
		end
		return top * t
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
-- metres, 1.25, capped at 2 which is under 5 degrees: a tilted piece is a little shorter across,
-- by the cosine of the tilt, which opens a slit of a few centimetres at its borders), rough (0 to 1, 0.5).
-- Answers a relief: { height = function(x, y) in metres, slope = function(x, y) -> dz/dx, dz/dy,
-- place = function(entry) -> pos, quat, top = highest ground }, or nil when it came out flat.
function M.build(entries, box, rng, opts)
	opts = opts or {}
	local total = math.max(0, math.min(40, tonumber(opts.height) or 6))
	local step = math.max(0.1, math.min(2, tonumber(opts.step) or 1.25))
	local rough = math.max(0, math.min(1, tonumber(opts.rough) or 0.5))
	if total <= 0 then return nil end

	local xs, ys = {}, {}
	for i = 1, #entries do
		local e = entries[i]
		local x0, y0, x1, y1 = grid.span(e.x, e.y, e.rot or 0, e.size_x or 1, e.size_y or 1)
		if x1 > x0 then xs[#xs + 1] = { x0, x1 } end
		if y1 > y0 then ys[#ys + 1] = { y0, y1 } end
	end
	-- Each axis may climb to three quarters of the height, so the two together reach it where their
	-- hills meet; the sum is then scaled down to the height where it goes over. Scaling both keeps
	-- every piece one plane and only makes slopes gentler.
	local fx = profile(box[1], box[3], locked_borders(xs), rng:fork("x"), step, total * 0.75, rough)
	local fy = profile(box[2], box[4], locked_borders(ys), rng:fork("y"), step, total * 0.75, rough)

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
	-- ({ x, y, z } and { x, y, z, w }), and the stretch ({ x, y }, along the piece's own axes) its
	-- ground takes about the level's origin. A tilted piece covers a little less ground across (the
	-- cosine of the tilt), which opened slits at its borders that showed the dark below (seen in
	-- game). Its ground is stretched by the inverse, about the middle of the piece, so a piece that
	-- slopes one way meets its neighbours exactly. One that slopes both ways is a rectangle where the
	-- ground is a parallelogram, which no turn and stretch can match: where the slope changes at a
	-- border that leaves a wedge of up to 24 |a b| metres, so such a piece reaches past each border
	-- by half of that (each neighbour covers its own half) and a centimetre.
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
		local ux, uy = M.rotate(q, 1, 0, 0)
		local vx, vy = M.rotate(q, 0, 1, 0)
		local sx, sy = 1 / math.sqrt(ux * ux + uy * uy), 1 / math.sqrt(vx * vx + vy * vy)
		if a ~= 0 and b ~= 0 then
			local reach = math.max(w, h) / 2 * math.abs(a * b) + 0.01
			sx, sy = sx * (1 + 2 * reach / w), sy * (1 + 2 * reach / h)
		end
		-- The level's origin, so that the middle of the stretched piece sits on the middle of its cells.
		local ox, oy, oz = M.rotate(q, w / 2 * sx, h / 2 * sy, 0)
		return { x = cx - ox, y = cy - oy, z = R.height(cx, cy) - oz }, { x = q[1], y = q[2], z = q[3], w = q[4] }, { x = sx, y = sy }
	end

	return R
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
