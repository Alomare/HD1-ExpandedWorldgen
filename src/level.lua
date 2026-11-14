-- The generator inside the game's level build. GeneratedLevel builds a map in steps (area, mission,
-- unique, extract, rare, special, edge, common, spawn), called one by one from three places: the
-- mission itself, the briefing's map and the planet screen's map. Each step is wrapped here and
-- does the game's own work on tables this mod prepared, so a profile shapes the map while the
-- placing of pieces, the edge and the objectives stay the game's code:
--
--   area      the game's area is measured, then replaced by the profile's shape and size
--   mission   the game's step, with the profile's budget and filter
--   unique, rare, special
--             the game's step once per biome, on that biome's part of the ground with its pieces
--   edge      the game's step; each edge piece then takes the biome of the ground beside it
--   common    other biomes' ground is filled first; the game's step fills the rest and re-bases
--   after     backdrop rings, relief (heights and tilts), props are planned from the finished list
--   spawn     the game's step, with each piece loaded from its own biome, lifted and tilted
--
-- Every machine runs the same steps on the same seed, so every machine gets the same map.
local grid = obsidian.module("src/grid")
local rng_lib = obsidian.module("src/rng")
local shapes = obsidian.module("src/shapes")
local regions = obsidian.module("src/regions")
local relief_lib = obsidian.module("src/relief")
local profiles = obsidian.module("src/profile")
local props_lib = obsidian.module("src/props")

local M = { rules = {}, active = nil, log = function() end }

local key, unkey = grid.key, grid.unkey
local LISTS = { "mission", "unique", "rare", "children", "special", "common", "extract", "droppoint",
	"edge_straight", "edge_fill", "edge_concave", "edge_convex" }
local NAMED = { "mission", "unique", "rare", "children", "special", "common" } -- what all_modules holds
local NEEDED = { "common", "extract", "edge_fill", "edge_concave", "edge_convex" } -- an empty one stops the game

local function G(name)
	return rawget(_G, name)
end

local function clone(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[k] = clone(x) end
	return out
end

local function index_of(list, value)
	for i = 1, #(list or {}) do
		if list[i] == value then return i end
	end
	return nil
end

-- The game drops pieces that don't go with the mission's faction (races[n] == false).
local function for_faction(list, faction)
	local out = {}
	for i = 1, #list do
		local m = list[i]
		if not (faction and m.races and m.races[faction] == false) then out[#out + 1] = m end
	end
	return out
end

local function same_piece(a, b)
	if a.size[1] ~= b.size[1] or a.size[2] ~= b.size[2] then return false end
	if (a.blocked == nil) ~= (b.blocked == nil) then return false end
	for i = 1, #(a.blocked or {}) do
		if a.blocked[i] ~= b.blocked[i] then return false end
	end
	local oa, ob = a.objectives or {}, b.objectives or {}
	if #oa ~= #ob then return false end
	for i = 1, #oa do
		local pa, pb = oa[i].position or {}, ob[i].position or {}
		if oa[i].name ~= ob[i].name or pa[1] ~= pb[1] or pa[2] ~= pb[2] then return false end
	end
	return true
end

local function find_named(list, name)
	for i = 1, #(list or {}) do
		if list[i].name == name then return list[i] end
	end
	return nil
end

-- Which rule speaks for this mission: the first that answers a profile.
local function ask_rules(ctx)
	for i = 1, #M.rules do
		local ok, p = true, nil
		if M.rules[i].on ~= false then ok, p = pcall(M.rules[i].fn, ctx) end
		if not ok then
			M.log("rule of " .. tostring(M.rules[i].owner) .. " failed: " .. tostring(p))
		elseif type(p) == "table" then
			return p, M.rules[i].owner
		end
	end
	return nil
end

-- Tags the pieces a step added: which step, which biome. A piece from the planet's own lists that
-- landed on another biome's ground becomes that biome's piece when it has the same one.
local function tag(self, wg, from, cat, biome, by_ground)
	local list = self.spawn_list
	for i = from + 1, #list do
		local e = list[i]
		if e.wg_cat == nil then
			e.wg_cat, e.wg_biome = cat, biome or 1
			if by_ground and wg.layout then
				local b = wg.layout.at(e.x, e.y)
				local other = b ~= 1 and wg.biomes[b] and find_named(wg.biomes[b].env[by_ground], e.level_name)
				local own = find_named(wg.biomes[1].env[by_ground], e.level_name)
				if other and own and same_piece(own, other) then e.wg_biome = b end
			end
		end
	end
end

-- A piece put on the map by this mod, the way the game's own placing does it (its fn_29 and fn_30):
-- the entry, the cells it takes out of the free ground, and the cells it claims.
local function place(self, module, x, y, rot, is_edge, claim)
	local e = {
		level_name = module.name, x = x, y = y, rot = rot,
		size_x = module.size[1], size_y = module.size[2],
		children = module.children, objectives = module.objectives, is_edge = is_edge,
		objective_hidden_data = module.objective_hidden_data,
		allow_children_outside = module.allow_children_outside, child_generation = module.child_generation,
		no_strat_zone = module.no_strat_zone, no_strat_zone_sphere = module.no_strat_zone_sphere,
		hide_on_map = module.hide_on_map, drop_position = module.drop_position,
	}
	if claim then
		local cells = grid.cells(x, y, rot, e.size_x, e.size_y, module.blocked)
		for i = 1, #cells do
			local k = key(cells[i][1], cells[i][2])
			self.collision_map[k] = e
			if self.area_map[k] then
				self.area_map[k] = nil
				local at = index_of(self.area_map_lookup, k)
				if at then table.remove(self.area_map_lookup, at) end
			end
		end
	end
	self.spawn_list[#self.spawn_list + 1] = e
	return e
end

----------------------------------------------------------------------------------------------------
-- initialize: is there a profile for this mission, and what does it settle on.

local function setup(self, world, seed)
	if self.mission_type_name ~= "mission" or #M.rules == 0 then return end
	local settings = G("EnvironmentSettings")
	local difficulty = G("DifficultySettings")
	if not settings or not settings.mission or not difficulty then return end
	local ctx = {
		seed = seed, layout = math.floor(seed / 10000000),
		environment = self.environment_name, enemy = self.enemy, difficulty = self.difficulty,
		time_of_day = self.time_of_day, mission_type = self.mission_type_name, preview = world == nil,
	}
	local asked, owner = ask_rules(ctx)
	if not asked then return end
	local stream = rng_lib.new(seed, "worldgen")
	local p = profiles.resolve(asked, ctx, stream)
	if profiles.is_plain(p) then return end

	local faction = index_of(difficulty.enemy_lookup, self.enemy)
	local wg = { profile = p, ctx = ctx, rng = stream, owner = owner, biomes = {}, extra = {} }
	wg.biomes[1] = { env = self.environment, name = self.environment_name, path = self.environment.path }
	for i = 2, #p.biomes do
		local source = settings.mission[p.biomes[i].env]
		if source and source.path and source.path ~= "" then
			local env = clone(source)
			for _, name in ipairs(LISTS) do env[name] = for_faction(env[name] or {}, faction) end
			wg.biomes[#wg.biomes + 1] = { env = env, name = p.biomes[i].env, path = env.path, weight = p.biomes[i].weight }
		end
	end
	wg.biomes[1].weight = p.biomes[1].weight

	-- The profile's own edits to the lists, on this level's copies only.
	if p.remix then
		for i = 1, #wg.biomes do
			local before = {}
			for _, name in ipairs(NEEDED) do before[name] = wg.biomes[i].env[name] end
			local ok, err = pcall(p.remix, wg.biomes[i].env, wg.biomes[i].name, ctx)
			if not ok then M.log("remix failed: " .. tostring(err)) end
			for _, name in ipairs(LISTS) do
				if type(wg.biomes[i].env[name]) ~= "table" then wg.biomes[i].env[name] = {} end
			end
			for _, name in ipairs(NEEDED) do
				if #wg.biomes[i].env[name] == 0 then wg.biomes[i].env[name] = before[name] end
			end
		end
	end
	if p.objectives.filter then
		local kept = {}
		for _, m in ipairs(self.environment.mission) do
			local ok, keep = pcall(p.objectives.filter, m, ctx)
			if ok and keep then kept[#kept + 1] = m end
		end
		-- The game draws from this list without looking: an empty one stops it.
		if #kept > 0 then self.environment.mission = kept end
	end

	-- Names to pieces, for the children step: every biome's, the planet's own first.
	local all = {}
	wg.piece_biome = {}
	for i = 1, #wg.biomes do
		for _, name in ipairs(NAMED) do
			for _, m in ipairs(wg.biomes[i].env[name] or {}) do
				if all[m.name] == nil then
					all[m.name] = m
					wg.piece_biome[m] = i
				end
			end
		end
	end
	self.all_modules = all

	-- Packages besides the game's own two: the other biomes', and the profile's.
	for i = 2, #wg.biomes do
		wg.extra[#wg.extra + 1] = wg.biomes[i].path .. self.enemy
	end
	for _, name in ipairs(p.packages) do
		if not index_of(wg.extra, name) then wg.extra[#wg.extra + 1] = name end
	end
	self.wg = wg
	M.log(("map %s: profile %s (%s), shape %s x%.2f, biomes %d, relief %s"):format(tostring(seed), p.id, tostring(owner),
		p.shape, p.size, #wg.biomes, p.relief and tostring(p.relief.height) or "off"))
end

----------------------------------------------------------------------------------------------------
-- area

local function reshape(self, wg)
	local p = wg.profile
	local own = shapes.from_area(self.area_map)
	if not own then return end
	local n0 = shapes.count(own)
	local n = math.max(4, math.min(p.max_blocks, math.floor(n0 * p.size + 0.5)))
	local set = own
	local stream = wg.rng:fork("area")
	if p.shape ~= "vanilla" then
		local opts = clone(p.shape_opts)
		opts.across = p.across
		set = shapes.build(p.shape, n, stream, opts)
	elseif n > n0 then
		local half = math.floor(p.across / 2)
		-- The game's shape, grown from its border. Its blocks may already sit outside the limit
		-- the growing keeps to; they stay.
		set = shapes.connected(shapes.unpinch(shapes.grow(own, n, stream, half, 0.5), stream, half))
	else
		wg.blocks = n0
		return
	end
	for k in pairs(self.area_map) do self.area_map[k] = nil end
	for i = #self.area_map_lookup, 1, -1 do self.area_map_lookup[i] = nil end
	local x0, x1, y0, y1 = shapes.to_area(set, self.area_map, self.area_map_lookup)
	self.min_x, self.max_x, self.min_y, self.max_y = x0, x1, y0, y1
	self.width = (self.max_x - self.min_x) + 2
	self.height = (self.max_y - self.min_y) + 2
	wg.blocks = shapes.count(set)
end

local function lay_out(self, wg)
	if #wg.biomes < 2 then return end
	local x0, y0, x1, y1 = grid.bounds(self.area_map)
	if not x0 then return end
	local weights = {}
	for i = 1, #wg.biomes do weights[i] = wg.biomes[i].weight end
	wg.layout = regions.build(wg.profile.layout, #wg.biomes, weights, { x0, y0, x1, y1 }, wg.rng:fork("regions"))
end

----------------------------------------------------------------------------------------------------
-- The game's step once per biome, each on its own part of the free ground with its own pieces.

local function per_biome(self, wg, original, cat, ...)
	if not wg.layout then
		local from = #self.spawn_list
		original(self, ...)
		tag(self, wg, from, cat, 1)
		return
	end
	local env0, area0, lookup0 = self.environment, self.area_map, self.area_map_lookup
	for b = 1, #wg.biomes do
		local area, lookup = {}, {}
		for i = 1, #lookup0 do
			local k = lookup0[i]
			if area0[k] and wg.layout.at(unkey(k)) == b then
				area[k] = true
				lookup[#lookup + 1] = k
			end
		end
		if #lookup > 0 then
			local mine = {}
			for i = 1, #lookup do mine[i] = lookup[i] end
			local from = #self.spawn_list
			self.environment, self.area_map, self.area_map_lookup = wg.biomes[b].env, area, lookup
			local ok, err = pcall(original, self, ...)
			self.environment, self.area_map, self.area_map_lookup = env0, area0, lookup0
			if not ok then M.log(cat .. " step failed for " .. wg.biomes[b].name .. ": " .. tostring(err)) end
			-- What the step used is gone from its part; take it out of the whole.
			local used = false
			for i = 1, #mine do
				if not area[mine[i]] then
					area0[mine[i]] = nil
					used = true
				end
			end
			if used then
				local kept = {}
				for i = 1, #lookup0 do
					if area0[lookup0[i]] then kept[#kept + 1] = lookup0[i] end
				end
				for i = #lookup0, 1, -1 do lookup0[i] = nil end
				for i = 1, #kept do lookup0[i] = kept[i] end
			end
			tag(self, wg, from, cat, b)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- mission: the game's budget is the difficulty; a profile scales it and may lift the caps.

local function with_budget(self, wg, original, ...)
	local o = wg.profile.objectives
	local difficulty, level_settings = G("DifficultySettings"), G("GeneratedLevelSettings")
	local points = difficulty and difficulty.calculate_mission_points
	local info = level_settings and level_settings.mission and level_settings.mission.objective_info
	local max0, unique0 = info and info.max_objectives, info and info.max_unique_objectives
	if points and o.scale ~= 1 then
		difficulty.calculate_mission_points = function(...)
			return math.max(1, math.floor(points(...) * o.scale + 0.5))
		end
	end
	if info and o.max then info.max_objectives = o.max end
	if info and o.max_unique then info.max_unique_objectives = o.max_unique end
	local ok, err = pcall(original, self, ...)
	if points then difficulty.calculate_mission_points = points end
	if info then info.max_objectives, info.max_unique_objectives = max0, unique0 end
	if not ok then error(err, 0) end
end

----------------------------------------------------------------------------------------------------
-- edge: each piece of the game's edge takes the biome of the ground it stands beside.

local EDGE_LISTS = { "edge_fill", "edge_straight", "edge_concave", "edge_convex" }

local function rebiome_edge(self, wg, from)
	local stream = wg.rng:fork("edge")
	for i = from + 1, #self.spawn_list do
		local e = self.spawn_list[i]
		e.wg_cat, e.wg_biome = "edge", 1
		local b = wg.layout and wg.layout.at(e.x, e.y) or 1
		if b ~= 1 then
			local list_name
			for _, name in ipairs(EDGE_LISTS) do
				if find_named(wg.biomes[1].env[name], e.level_name) then
					list_name = name
					break
				end
			end
			local fits = {}
			for _, m in ipairs(list_name and wg.biomes[b].env[list_name] or {}) do
				if m.size[1] == e.size_x and m.size[2] == e.size_y and not m.blocked then fits[#fits + 1] = m end
			end
			-- One draw for every piece on other ground, a fit or not, so the stream never depends on
			-- what a biome happens to have.
			local pick = stream:int(1, math.max(1, #fits))
			if #fits > 0 then
				e.level_name, e.wg_biome = fits[pick].name, b
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
-- After the game re-based the finished map: backdrop, relief, props.

local function finish(self, wg, dx, dy)
	local p = wg.profile
	if wg.layout then wg.layout = regions.shifted(wg.layout, dx, dy) end
	local x0, y0, x1, y1 = grid.bounds(self.collision_map)
	if not x0 then return end

	if p.backdrop then
		-- Rings of plain cliff outside the edge, so a low camera sees land where the map stops.
		local rings, stream = p.backdrop.rings, wg.rng:fork("backdrop")
		local near = {}
		for k in pairs(self.collision_map) do
			local cx, cy = unkey(k)
			for ax = -rings, rings do
				for ay = -rings, rings do
					local nk = key(cx + ax, cy + ay)
					if not self.collision_map[nk] then near[nk] = true end
				end
			end
		end
		for _, k in ipairs(grid.sorted(near)) do
			local cx, cy = unkey(k)
			local b = wg.layout and wg.layout.at(cx, cy) or 1
			local plain = {}
			for _, m in ipairs(wg.biomes[b].env.edge_fill or {}) do
				if m.size[1] == 1 and m.size[2] == 1 and not m.races and not m.objectives then plain[#plain + 1] = m end
			end
			local pick, rot = stream:int(1, math.max(1, #plain)), stream:int(0, 3)
			if #plain > 0 then
				local e = place(self, plain[pick], cx, cy, rot, true, false)
				e.wg_cat, e.wg_biome, e.wg_backdrop, e.hide_on_map = "backdrop", b, true, true
			end
		end
		x0, y0, x1, y1 = x0 - rings, y0 - rings, x1 + rings, y1 + rings
	end

	if p.relief then
		wg.relief = relief_lib.build(self.spawn_list, { x0, y0, x1, y1 }, wg.rng:fork("relief"), p.relief)
		if wg.relief then
			for _, e in ipairs(self.spawn_list) do
				e.wg_pos, e.wg_quat, e.wg_stretch = wg.relief.place(e)
			end
		end
	end

	if #p.props > 0 then
		wg.props = props_lib.plan(self.spawn_list, p.props, p.biomes, wg.rng:fork("props"))
	end
	wg.done = true
end

----------------------------------------------------------------------------------------------------
-- spawn: the game's step, with each piece's level taken from its own biome and put where the
-- relief says. The game asks for a level's object sets, then loads it, one piece after another.

local function path_of(wg, e)
	return (wg.biomes[e.wg_biome or 1] or wg.biomes[1]).path .. e.level_name
end

local function spawn(self, wg, original, spawner, register, ...)
	local list, at = self.spawn_list, 0
	local resource, proxy = G("LevelResource"), self.world_proxy
	local Vector3, Quaternion, Level = G("Vector3"), G("Quaternion"), G("Level")
	local names0 = resource.object_set_names
	local load0 = proxy.load_level_with_object_sets
	local had = rawget(proxy, "load_level_with_object_sets")

	resource.object_set_names = function(path, ...)
		at = at + 1
		local e = list[at]
		return names0(e and path_of(wg, e) or path, ...)
	end
	proxy.load_level_with_object_sets = function(this, name, path, flag, sets, extra, pos, rot, ...)
		local e = list[at]
		if e then
			path = path_of(wg, e)
			if e.wg_pos then
				pos = Vector3(e.wg_pos.x, e.wg_pos.y, e.wg_pos.z)
				rot = Quaternion.from_elements(e.wg_quat.x, e.wg_quat.y, e.wg_quat.z, e.wg_quat.w)
			end
		end
		local level = load0(this, name, path, flag, sets, extra, pos, rot, ...)
		if e then e.wg_path = path end
		return level
	end
	local ok, err = pcall(original, self, spawner, register, ...)
	resource.object_set_names = names0
	proxy.load_level_with_object_sets = had
	if not ok then error(err, 0) end

	-- What the game wrote on each level from its own flat spot.
	for _, e in ipairs(list) do
		if e.level and e.wg_path then
			Level.set_data(e.level, "level_path", e.wg_path)
			if e.wg_pos then
				Level.set_data(e.level, "pos", Vector3(e.wg_pos.x, e.wg_pos.y, e.wg_pos.z))
				Level.set_data(e.level, "rot", Quaternion.from_elements(e.wg_quat.x, e.wg_quat.y, e.wg_quat.z, e.wg_quat.w))
			end
		end
	end

	-- The ground of a tilted piece, stretched so its borders reach its neighbours' (relief.place).
	-- The ground meshes are the units at the level's origin; the rest keep their size.
	local Unit = G("Unit")
	if wg.relief and Unit and Unit.set_local_scale and Level.units then
		local stretched = 0
		local ok, err = pcall(function()
			for _, e in ipairs(list) do
				local s = e.wg_stretch
				if e.level and s and (math.abs(s.x - 1) > 1e-6 or math.abs(s.y - 1) > 1e-6) then
					for _, u in ipairs(Level.units(e.level)) do
						local p = Unit.local_position(u, 0)
						local dx, dy, dz = p.x - e.wg_pos.x, p.y - e.wg_pos.y, p.z - e.wg_pos.z
						if dx * dx + dy * dy + dz * dz < 0.0025 then
							local k = Unit.local_scale(u, 0)
							Unit.set_local_scale(u, 0, Vector3(k.x * s.x, k.y * s.y, k.z))
							stretched = stretched + 1
						end
					end
				end
			end
		end)
		if not ok then M.log("stretching the ground failed: " .. tostring(err)) end
		wg.stretched = stretched
	end

	wg.units = {}
	if wg.props and #wg.props > 0 then
		local World = G("World")
		local world = proxy:get_world()
		for _, q in ipairs(wg.props) do
			local z = (wg.relief and wg.relief.height(q.x, q.y) or 0) + (q.lift or 0)
			local unit = World.spawn_unit(world, q.unit, Vector3(q.x, q.y, z), Quaternion(Vector3(0, 0, 1), q.yaw))
			wg.units[#wg.units + 1] = { unit = unit, x = q.x, y = q.y }
		end
	end
	M.active = self
	M.log(("map spawned: %d pieces, %d props, %s level entities, highest ground %.1f m, %d ground units stretched"):format(#list, #wg.units,
		tostring(spawner and spawner.num_level_entities), wg.relief and wg.relief.top or 0, wg.stretched or 0))
end

----------------------------------------------------------------------------------------------------
-- The briefing and HUD map. The game draws every piece into one texture at a fixed number of
-- pixels a cell, which holds 26 cells; a wider map is drawn smaller, and the HUD stretches the part
-- of the texture it is told to (map_uv) back over map_size cells. Each piece is drawn with the map
-- material of its biome.

local function draw_map(self, wg)
	local World, Gui, Vector2, Vector3 = G("World"), G("Gui"), G("Vector2"), G("Vector3")
	local Vector2Aux, Rotation2D, Application = G("Vector2Aux"), G("Rotation2D"), G("Application")
	World.update(self.map_world)
	local side, cell = 1872, 72
	if G("IS_PSVITA") or not (G("IS_PS4") or G("IS_PC")) then side, cell = 1248, 48 end
	local most = math.max(self.width, self.height) + 2
	if most * cell > side then cell = math.floor(side / most) end
	self.map_size = Vector2Aux.box({}, Vector2(self.width + 2, self.height + 2))
	local u, v = (self.map_size.x * cell) / side, (self.map_size.y * cell) / side
	self.map_uv = { Vector2Aux.box({}, Vector2(0, 1 - v)), Vector2Aux.box({}, Vector2(u, 1)) }
	for _, e in ipairs(self.spawn_list) do
		if not e.wg_backdrop then
			local gui = (wg.guis and wg.guis[e.wg_biome or 1]) or self.map_gui
			local x, y = e.x - self.min_x, (e.y + 1) - self.min_y
			if e.rot == 1 then
				x = x + 1
			elseif e.rot == 2 then
				x, y = x + 1, y + 1
			elseif e.rot == 3 then
				y = y + 1
			end
			local size = Vector2(e.size_x * cell, e.size_y * cell)
			local pos = Vector3((1 + x) * cell, y * cell, 2)
			local turn = Rotation2D(pos, e.rot * math.pi * -0.5, pos)
			Gui.bitmap_3d(gui, e.level_name, turn, Vector3.zero(), 1, size)
		end
	end
	Application.render_world(self.map_world, self.map_camera, self.map_viewport, self.map_shading_environment)
end

----------------------------------------------------------------------------------------------------

local function packages()
	local boot = G("Boot")
	return boot and boot.package_manager
end

-- Hides or shows what the mod added for looks alone, by distance from a point: backdrop pieces
-- and props. Nothing the game placed is touched, so nothing it tracks changes.
function M.cull(x, y)
	local self = M.active
	local wg = self and self.wg
	if not (wg and wg.profile.cull and wg.done) then return end
	local Unit, Level = G("Unit"), G("Level")
	local far = wg.profile.cull * wg.profile.cull
	local function set(shown, units)
		for i = 1, #units do Unit.set_unit_visibility(units[i], shown) end
	end
	for _, e in ipairs(self.spawn_list) do
		if e.wg_backdrop and e.level then
			local dx, dy = (e.x + 0.5) * grid.TILE - x, (e.y + 0.5) * grid.TILE - y
			local shown = dx * dx + dy * dy <= far
			if e.wg_shown ~= shown then
				e.wg_shown = shown
				set(shown, Level.units(e.level))
			end
		end
	end
	for _, q in ipairs(wg.units or {}) do
		local dx, dy = q.x - x, q.y - y
		local shown = dx * dx + dy * dy <= far
		if q.shown ~= shown then
			q.shown = shown
			set(shown, { q.unit })
		end
	end
end

-- The height of the ground at a world position in the mission being played: 0 on a flat map.
function M.height(x, y)
	local wg = M.active and M.active.wg
	if wg and wg.relief then return wg.relief.height(x, y) end
	return 0
end

function M.install(hook)
	-- A step of this mod that fails is logged and marks the level broken: the planning steps after it
	-- are then the game's own. The steps that load and draw (`always`) still run, because pieces
	-- already planned from another biome have to be loaded from that biome whatever happened since.
	local function guarded(name, fn, always)
		hook("GeneratedLevel", name, function(original, self, ...)
			local wg = self.wg
			if not wg or (wg.broken and not always) then return original(self, ...) end
			return fn(original, self, wg, ...)
		end)
	end
	local function try(wg, what, fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok then
			wg.broken = true
			M.log(what .. " failed, the rest of this map is the game's own: " .. tostring(err))
		end
		return ok
	end

	hook("GeneratedLevel", "initialize", function(original, self, world, seed, ...)
		original(self, world, seed, ...)
		self.wg = nil
		local ok, err = pcall(setup, self, world, seed)
		if not ok then
			self.wg = nil
			M.log("setup failed: " .. tostring(err))
		end
	end)

	guarded("generate_area", function(original, self, wg)
		original(self)
		if try(wg, "area", reshape, self, wg) then try(wg, "biome layout", lay_out, self, wg) end
	end)

	guarded("generate_mission", function(original, self, wg, ...)
		local from = #self.spawn_list
		with_budget(self, wg, original, ...)
		tag(self, wg, from, "mission", 1, "mission")
	end)

	guarded("generate_extract", function(original, self, wg, ...)
		local from = #self.spawn_list
		original(self, ...)
		tag(self, wg, from, "extract", 1, "extract")
	end)

	for _, step in ipairs({ "unique", "rare", "special" }) do
		guarded("generate_" .. step, function(original, self, wg, ...)
			if wg.profile.open then return end
			per_biome(self, wg, original, step, ...)
		end)
	end

	guarded("generate_children", function(original, self, wg, ...)
		local from = #self.spawn_list
		original(self, ...)
		for i = from + 1, #self.spawn_list do
			local e = self.spawn_list[i]
			if e.wg_cat == nil then
				e.wg_cat = "children"
				e.wg_biome = wg.piece_biome[self.all_modules and self.all_modules[e.level_name]] or 1
			end
		end
	end)

	guarded("generate_edge", function(original, self, wg, ...)
		local from = #self.spawn_list
		local straight = self.environment.edge_straight
		-- Long edge pieces would tie the relief's profiles down all round the map.
		if wg.profile.relief then self.environment.edge_straight = {} end
		local ok, err = pcall(original, self, ...)
		self.environment.edge_straight = straight
		if not ok then error(err, 0) end
		try(wg, "edge biomes", rebiome_edge, self, wg, from)
	end)

	guarded("generate_common", function(original, self, wg, ...)
		if wg.layout then
			try(wg, "common ground", function()
				local stream = wg.rng:fork("common")
				for _, k in ipairs(grid.sorted(self.area_map)) do
					local x, y = unkey(k)
					local b = wg.layout.at(x, y)
					local list = wg.biomes[b].env.common
					local pick, rot = stream:int(1, math.max(1, #list)), stream:int(0, 3)
					if b ~= 1 and #list > 0 and not self.collision_map[k] and list[pick].size[1] == 1 and list[pick].size[2] == 1 then
						local e = place(self, list[pick], x, y, rot, nil, true)
						e.wg_cat, e.wg_biome = "common", b
					end
				end
			end)
		end
		local from, dx, dy = #self.spawn_list, self.min_x, self.min_y
		original(self, ...)
		tag(self, wg, from, "common", 1)
		try(wg, "finish", finish, self, wg, dx, dy)
	end)

	guarded("spawn_levels", function(original, self, wg, spawner, register, ...)
		spawn(self, wg, original, spawner, register, ...)
	end, true)

	-- The map of the briefing and the HUD.
	guarded("load_map", function(original, self, wg, ...)
		original(self, ...)
		try(wg, "map materials", function()
			local World, manager = G("World"), packages()
			wg.guis = { self.map_gui }
			for b = 2, #wg.biomes do
				manager:load_package(wg.biomes[b].path .. "map", true)
				wg.guis[b] = World.create_screen_gui(self.map_world, "immediate", "material", wg.biomes[b].path .. "map")
			end
		end)
	end, true)
	guarded("update_map", function(original, self, wg, ...)
		draw_map(self, wg)
	end, true)
	guarded("release_world", function(original, self, wg, ...)
		if wg.guis then
			local World = G("World")
			for b = 2, #wg.guis do pcall(World.destroy_gui, self.map_world, wg.guis[b]) end
			wg.guis = nil
		end
		if M.active == self then M.active = nil end
		return original(self, ...)
	end, true)

	-- Packages: the other biomes' and the profile's go with the game's own two.
	guarded("load_resources", function(original, self, wg, sync, ...)
		original(self, sync, ...)
		local manager = packages()
		for _, name in ipairs(wg.extra) do manager:load_package(name, sync) end
	end, true)
	guarded("load_map_package", function(original, self, wg, sync, ...)
		original(self, sync, ...)
		local manager = packages()
		for b = 2, #wg.biomes do manager:load_package(wg.biomes[b].path .. "map", sync) end
	end, true)
	guarded("unload_map_package", function(original, self, wg, ...)
		original(self, ...)
		local manager = packages()
		for b = 2, #wg.biomes do manager:unload_package(wg.biomes[b].path .. "map") end
	end, true)
	guarded("has_loaded_map_package", function(original, self, wg, ...)
		if not original(self, ...) then return false end
		local manager = packages()
		for b = 2, #wg.biomes do
			if not manager:is_package_online(wg.biomes[b].path .. "map") then return false end
		end
		return true
	end, true)
	guarded("has_loaded_resources", function(original, self, wg, ...)
		local manager = packages()
		for _, name in ipairs(wg.extra) do
			if not manager:is_package_online(name) then return false end
		end
		return original(self, ...)
	end, true)
	guarded("release_enemy_package", function(original, self, wg, ...)
		original(self, ...)
		local manager = packages()
		for _, name in ipairs(wg.extra) do manager:unload_package(name) end
		if M.active == self then M.active = nil end
	end, true)
	guarded("get_package_size_in_bytes", function(original, self, wg, ...)
		local total, manager = original(self, ...), packages()
		for _, name in ipairs(wg.extra) do total = total + (manager:get_size_in_bytes(name) or 0) end
		return total
	end, true)
	guarded("get_package_loaded_bytes", function(original, self, wg, ...)
		local total, manager = original(self, ...), packages()
		for _, name in ipairs(wg.extra) do total = total + (manager:get_loaded_bytes(name) or 0) end
		return total
	end, true)

	-- The game keeps found paths under a key that two pairs of cells can share once a map is wider
	-- than ten cells. With a profile the path is found again each time.
	guarded("get_waypoints", function(original, self, wg, ...)
		self.waypoints_cache = {}
		return original(self, ...)
	end)

	-- Relief: SpawnManager casts a ray down from 100 m and takes the hit only between -0.5 and 1 m (a
	-- group spawn point between -0.2 and 1 m), the height of flat ground. On raised ground every try
	-- fails, and the players never drop. While a spawn's ray reports, the hit is given from the
	-- terrain's height, and what the game boxes in that moment (the spawn position) is put back up.
	local function on_ground(original, self, ...)
		local wg = M.active and M.active.wg
		local physics = G("PhysicsWorld")
		if not (wg and wg.relief and physics and physics.make_raycast) then return original(self, ...) end
		local make = physics.make_raycast
		physics.make_raycast = function(world, callback, ...)
			local function report(hit, pos, ...)
				local h = hit and pos and wg.relief and wg.relief.height(pos.x, pos.y) or 0
				if h == 0 then return callback(hit, pos, ...) end
				local aux = G("Vector3Aux")
				local box = aux.box
				aux.box = function(t, v, ...)
					local r = box(t, v, ...)
					if type(r) == "table" and r.z then r.z = r.z + h end
					return r
				end
				local res = { pcall(callback, hit, G("Vector3")(pos.x, pos.y, pos.z - h), ...) }
				aux.box = box
				if not res[1] then error(res[2], 0) end
				return unpack(res, 2)
			end
			return make(world, report, ...)
		end
		local res = { pcall(original, self, ...) }
		physics.make_raycast = make
		if not res[1] then error(res[2], 0) end
		return unpack(res, 2)
	end
	hook("SpawnManager", "queue_spawn", on_ground)
	hook("SpawnManager", "queue_group_spawn", on_ground)

	-- Relief: what the game spawns below the ground is lifted to it. `get_closest_position_on_level`
	-- stays the game's: the camera calls it each frame from a point at z 0 and moves by the
	-- difference, so a lifted answer makes the camera climb without end.
	hook("EntitySpawner", "spawn_entity", function(original, self, path, pos, ...)
		local wg = M.active and M.active.wg
		if wg and wg.relief and pos then
			local ground = wg.relief.height(pos.x, pos.y)
			if pos.z < ground then pos = G("Vector3")(pos.x, pos.y, ground) end
		end
		return original(self, path, pos, ...)
	end)
end

return M
