-- The parts that are plain Lua: the random stream, shapes, biome layouts, relief, profiles, props.
local rng = obsidian.module("src/rng")
local grid = obsidian.module("src/grid")
local shapes = obsidian.module("src/shapes")
local regions = obsidian.module("src/regions")
local relief = obsidian.module("src/relief")
local profiles = obsidian.module("src/profile")
local props = obsidian.module("src/props")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

test("rng: the same seed and label give the same numbers, another label gives others", function()
	local a, b, c = rng.new(1234, "x"), rng.new(1234, "x"), rng.new(1234, "y")
	local differs = false
	for _ = 1, 50 do
		local v = a:next()
		eq(b:next(), v)
		if c:next() ~= v then differs = true end
	end
	yes(differs, "labels differ")
end)

test("rng: whole numbers stay in range and reach both ends", function()
	local r, low, high = rng.new(7, "ints"), false, false
	for _ = 1, 2000 do
		local v = r:int(3, 6)
		yes(v >= 3 and v <= 6 and v == math.floor(v), "in range")
		low, high = low or v == 3, high or v == 6
		local f = r:float()
		yes(f >= 0 and f < 1, "float in range")
	end
	yes(low and high, "both ends")
end)

local function check_shape(set, across, what)
	local half = math.floor(across / 2)
	local n = shapes.count(set)
	yes(n >= 4, what .. ": has blocks")
	eq(shapes.count(shapes.connected(set)), n, what .. ": one piece")
	for k in pairs(set) do
		local bx, by = grid.unkey(k)
		yes(bx >= -half and bx < half and by >= -half and by < half, what .. ": inside the limit")
		for sx = -1, 1, 2 do
			if set[grid.key(bx + sx, by + 1)] then
				yes(set[grid.key(bx + sx, by)] or set[grid.key(bx, by + 1)], what .. ": no blocks joined by a corner alone")
			end
		end
	end
end

test("shapes: every shape is one piece, inside the limit, with no corner-only joins", function()
	for _, name in ipairs(shapes.names) do
		for seed = 1, 25 do
			for _, n in ipairs({ 8, 40, 110, 170 }) do
				local set = shapes.build(name, n, rng.new(seed, name), {})
				check_shape(set, shapes.MAX_ACROSS, name .. " seed " .. seed .. " n " .. n)
			end
		end
	end
end)

test("shapes: about the size asked for, where the limit allows", function()
	for _, name in ipairs({ "blob", "ragged", "rectangle", "cross", "corner", "islands" }) do
		for seed = 1, 10 do
			local n = shapes.count(shapes.build(name, 60, rng.new(seed, name), {}))
			yes(n >= 45 and n <= 90, name .. " of 60 came out " .. n)
		end
	end
end)

test("shapes: the same seed gives the same shape", function()
	for _, name in ipairs(shapes.names) do
		local a = shapes.build(name, 50, rng.new(99, "s"), {})
		local b = shapes.build(name, 50, rng.new(99, "s"), {})
		eq(shapes.count(a), shapes.count(b))
		for k in pairs(a) do yes(b[k], name .. " same blocks") end
	end
end)

test("shapes: a ring has a hole in the middle", function()
	local set = shapes.build("ring", 60, rng.new(5, "ring"), {})
	yes(not set[grid.key(0, 0)] and not set[grid.key(-1, -1)], "middle is empty")
end)

test("shapes: across narrows the map", function()
	local set = shapes.build("blob", 170, rng.new(3, "a"), { across = 8 })
	check_shape(set, 8, "narrow blob")
	yes(shapes.count(set) <= 64, "no more than fits")
end)

test("shapes: to_area and from_area agree, and an area off the lattice is refused", function()
	local set = shapes.build("cross", 30, rng.new(11, "c"), {})
	local area, lookup = {}, {}
	local x0, x1, y0, y1 = shapes.to_area(set, area, lookup)
	eq(#lookup, shapes.count(set) * 4)
	local bx0, by0, bx1, by1 = grid.bounds(area)
	eq(x0, bx0); eq(y0, by0); eq(x1, bx1); eq(y1, by1)
	local back = shapes.from_area(area)
	eq(shapes.count(back), shapes.count(set))
	eq(shapes.from_area({ [grid.key(0, 0)] = true }), nil)
end)

test("shapes: grow keeps what was there", function()
	local set = { [grid.key(0, 0)] = true, [grid.key(1, 0)] = true }
	shapes.grow(set, 30, rng.new(2, "g"), 9, 0.5)
	eq(shapes.count(set), 30)
	yes(set[grid.key(0, 0)] and set[grid.key(1, 0)])
end)

test("regions: every biome gets ground, blocks are never cut, and the layout repeats", function()
	local box = { 0, 0, 23, 19 }
	for _, mode in ipairs(regions.names) do
		for count = 2, 4 do
			for seed = 1, 12 do
				local a = regions.build(mode, count, nil, box, rng.new(seed, mode))
				local b = regions.build(mode, count, nil, box, rng.new(seed, mode))
				local seen = {}
				for x = 0, 23 do
					for y = 0, 19 do
						local v = a.at(x, y)
						yes(v >= 1 and v <= count, "a biome of the list")
						eq(b.at(x, y), v, "repeats")
						eq(a.at(math.floor(x / 2) * 2, math.floor(y / 2) * 2), v, "a block is one biome")
						seen[v] = true
					end
				end
				for i = 1, count do yes(seen[i], mode .. " " .. count .. " seed " .. seed .. ": biome " .. i .. " has ground") end
			end
		end
	end
end)

test("regions: a shifted layout answers for the moved cells", function()
	local a = regions.build("patches", 3, nil, { -6, -4, 9, 11 }, rng.new(4, "p"))
	local s = regions.shifted(a, -6, -4)
	for x = 0, 15 do
		for y = 0, 15 do eq(s.at(x, y), a.at(x - 6, y - 4)) end
	end
end)

-- A map of single pieces with a few wide ones, as a finished spawn list.
local function fake_entries(w, h, wide)
	local list, taken = {}, {}
	for _, e in ipairs(wide) do
		list[#list + 1] = e
		for _, c in ipairs(grid.cells(e.x, e.y, e.rot, e.size_x, e.size_y)) do taken[grid.key(c[1], c[2])] = true end
	end
	for x = 0, w - 1 do
		for y = 0, h - 1 do
			if not taken[grid.key(x, y)] then list[#list + 1] = { x = x, y = y, rot = (x + y) % 4, size_x = 1, size_y = 1 } end
		end
	end
	return list
end

-- The four corners of a piece's footprint as its level carries them: the game's flat spot of each
-- corner, and where the piece's position and rotation put it.
local function corners(e, r)
	local pos, q, sh = r.place(e)
	local rot = e.rot
	local px, py = 24 * e.x, 24 * e.y
	if rot == 1 or rot == 2 then px = px + 24 end
	if rot == 2 or rot == 3 then py = py + 24 end
	local yaw = relief.axis_angle(0, 0, 1, rot * math.pi * 0.5)
	local out = {}
	for _, c in ipairs({ { 0, 0 }, { 24 * e.size_x, 0 }, { 0, 24 * e.size_y }, { 24 * e.size_x, 24 * e.size_y } }) do
		local fx, fy = relief.rotate(yaw, c[1], c[2], 0)
		local wx, wy, wz = relief.rotate({ q.x, q.y, q.z, q.w }, c[1], c[2], 0)
		local x, y, z = pos.x + wx, pos.y + wy, pos.z + wz
		if sh then x, y, z = relief.sheared(sh, { x = x, y = y, z = z }) end
		out[#out + 1] = { flat_x = px + fx, flat_y = py + fy, x = x, y = y, z = z }
	end
	return out
end

test("relief: every corner of every piece lies on the ground it is given, so neighbours meet", function()
	local wide = {
		{ x = 3, y = 2, rot = 0, size_x = 2, size_y = 2 },
		{ x = 9, y = 6, rot = 1, size_x = 3, size_y = 1 },
		{ x = 6, y = 10, rot = 2, size_x = 2, size_y = 1 },
	}
	-- Drawn sheared, every piece covers exactly its cells, each corner at the height of the ground
	-- there, so neighbours meet along every border whatever their slopes. (Turned, pieces left
	-- slits along the borders and wedges where the slope changed both ways, seen in game.)
	local built, sloped = 0, 0
	for seed = 1, 30 do
		local entries = fake_entries(14, 12, wide)
		local r = relief.build(entries, { 0, 0, 13, 11 }, rng.new(seed, "relief"), { height = 20, step = 4, rough = 0.7 })
		if r then
			built = built + 1
			yes(r.top <= 20.001 and r.top > 0, "within the height asked")
			for _, e in ipairs(entries) do
				local x0, y0, x1, y1 = grid.span(e.x, e.y, e.rot, e.size_x, e.size_y)
				local a, b = r.slope((x0 + x1 + 1) * 12, (y0 + y1 + 1) * 12)
				if a ~= 0 and b ~= 0 then sloped = sloped + 1 end
				for _, c in ipairs(corners(e, r)) do
					near(c.x, c.flat_x, 1e-6, "corner x")
					near(c.y, c.flat_y, 1e-6, "corner y")
					near(c.z, r.height(c.flat_x, c.flat_y), 1e-6, "corner on the ground")
				end
				-- What stands upright on the tilted level stands upright as drawn.
				local _, q, sh = r.place(e)
				if sh then
					local ux, uy, uz = relief.rotate({ q.x, q.y, q.z, q.w }, 0, 0, 1)
					local x, y, z = relief.sheared_axis(sh, { x = ux, y = uy, z = uz })
					near(x, 0, 1e-9); near(y, 0, 1e-9); near(z, 1, 1e-9, "up stays up")
				end
			end
		end
	end
	yes(built >= 25, "most seeds give relief")
	yes(sloped > 50, "pieces sloping both ways were tried: " .. sloped)
end)

test("relief: flat when asked for none, and never below 0", function()
	local entries = fake_entries(8, 8, {})
	eq(relief.build(entries, { 0, 0, 7, 7 }, rng.new(1, "r"), { height = 0 }), nil)
	local r = relief.build(entries, { 0, 0, 7, 7 }, rng.new(1, "r"), { height = 10, rough = 1 })
	yes(r, "relief built")
	local low = math.huge
	for x = 0, 192, 6 do
		for y = 0, 192, 6 do low = math.min(low, r.height(x, y)) end
	end
	near(low, 0, 0.001, "lowest ground")
end)

test("relief: the quaternion helpers turn as expected", function()
	local q = relief.axis_angle(0, 0, 1, math.pi / 2)
	local x, y, z = relief.rotate(q, 1, 0, 0)
	near(x, 0, 1e-9); near(y, 1, 1e-9); near(z, 0, 1e-9)
	local both = relief.multiply(relief.axis_angle(1, 0, 0, math.pi / 2), q)
	x, y, z = relief.rotate(both, 1, 0, 0)
	near(x, 0, 1e-9); near(y, 0, 1e-9); near(z, 1, 1e-9)
end)

local CTX = { environment = "desert", enemy = "bugs", difficulty = 8, seed = 1 }

test("profile: numbers are brought inside the limits, and unknown names fall back", function()
	local p = profiles.resolve({ shape = "nonsense", size = 99, across = 500, relief = { height = 900, step = 9 },
		biomes = { "desert", "moon", "snow", "snow", { env = "lava", weight = -3 } }, backdrop = 50,
		objectives = { scale = 100, max = 99 }, props = { { unit = "a/b", per_tile = { 2, 400 } }, { per_tile = 1 } } }, CTX, rng.new(1, "p"))
	eq(p.shape, "vanilla"); eq(p.size, 8); eq(p.across, shapes.MAX_ACROSS)
	eq(p.relief.height, 40); eq(p.relief.step, 5)
	eq(#p.biomes, 3); eq(p.biomes[1].env, "desert"); eq(p.biomes[2].env, "snow"); eq(p.biomes[3].env, "lava")
	eq(p.backdrop.rings, profiles.MAX_RINGS)
	eq(p.objectives.scale, 4); eq(p.objectives.max, 12)
	eq(#p.props, 1); eq(p.props[1].max, 12)
end)

test("profile: \"any\" is settled from the seed, the same each time", function()
	local a = profiles.resolve({ shape = "any", biomes = "any", layout = "any" }, CTX, rng.new(42, "p"))
	local b = profiles.resolve({ shape = "any", biomes = "any", layout = "any" }, CTX, rng.new(42, "p"))
	eq(a.shape, b.shape); eq(a.layout, b.layout); eq(a.biomes[2].env, b.biomes[2].env)
	yes(a.biomes[2].env ~= "desert", "another biome than the planet's own")
end)

test("profile: one that changes nothing is plain", function()
	yes(profiles.is_plain(profiles.resolve({}, CTX, rng.new(1, "p"))))
	yes(not profiles.is_plain(profiles.resolve({ size = 1.5 }, CTX, rng.new(1, "p"))))
	yes(not profiles.is_plain(profiles.resolve({ relief = 4 }, CTX, rng.new(1, "p"))))
end)

test("props: land inside their piece, only on the kinds and biomes asked, the same each time", function()
	local entries = {
		{ x = 2, y = 3, size_x = 1, size_y = 1, wg_cat = "common", wg_biome = 1 },
		{ x = 4, y = 3, size_x = 1, size_y = 1, wg_cat = "common", wg_biome = 2 },
		{ x = 6, y = 3, size_x = 1, size_y = 1, wg_cat = "edge", wg_biome = 1 },
		{ x = 8, y = 3, size_x = 2, size_y = 2, wg_cat = "common", wg_biome = 1 },
	}
	local rules = profiles.resolve({ props = { { unit = "u/one", per_tile = { 2, 4 }, margin = 3, biomes = { "desert" } } } }, CTX, rng.new(1, "p")).props
	local biomes = { { env = "desert" }, { env = "snow" } }
	local a = props.plan(entries, rules, biomes, rng.new(5, "props"))
	local b = props.plan(entries, rules, biomes, rng.new(5, "props"))
	yes(#a >= 2 and #a <= 4, "only the one piece qualifies")
	eq(#a, #b)
	for i, q in ipairs(a) do
		yes(q.x >= 2 * 24 + 3 and q.x <= 3 * 24 - 3 and q.y >= 3 * 24 + 3 and q.y <= 4 * 24 - 3, "inside the piece, off its border")
		eq(q.x, b[i].x); eq(q.y, b[i].y); eq(q.yaw, b[i].yaw)
	end
end)

return T
