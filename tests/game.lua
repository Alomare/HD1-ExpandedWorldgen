-- The game's own level generator, run outside the game: its compiled scripts (LuaJIT 2.0 bytecode,
-- dumped from the game's bundles, never part of this repository) on a stand-in for the engine. With
-- them the tests build real maps from the real piece tables, the game's steps included.
--
-- The scripts are looked for in WORLDGEN_GAME_SCRIPTS, then in the workspace's research folder.
-- Without them game.available is false and the tests that need the game are skipped.
local M = { available = false }

local roots = {
	os.getenv("WORLDGEN_GAME_SCRIPTS"),
	"../../../ProjectObsidian/ObsidianLauncher/internal/research/scripts",
}

local function read(root, name)
	local f = io.open(root .. "/" .. name .. ".ljbc", "rb")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

for i = 1, 2 do
	local root = roots[i]
	if not M.available and root and read(root, "lua/utility/generated_level") then
		M.root = root
		M.available = true
	end
end

-- Vectors as plain tables with the arithmetic the generator uses.
local V = {}
V.__index = V
local function vec(x, y, z)
	return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V)
end
V.__add = function(a, b) return vec(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return vec(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__unm = function(a) return vec(-a.x, -a.y, -a.z) end
V.__mul = function(a, b)
	if type(a) == "number" then return vec(a * b.x, a * b.y, a * b.z) end
	return vec(a.x * b, a.y * b, a.z * b)
end
V.__div = function(a, b) return vec(a.x / b, a.y / b, a.z / b) end

-- A quaternion of from_elements ({ x, y, z, w }) turning v.
local function elements_rotate(q, v)
	local qx, qy, qz, qw = q.x, q.y, q.z, q.w
	local tx, ty, tz = 2 * (qy * v.z - qz * v.y), 2 * (qz * v.x - qx * v.z), 2 * (qx * v.y - qy * v.x)
	return vec(v.x + qw * tx + (qy * tz - qz * ty), v.y + qw * ty + (qz * tx - qx * tz), v.z + qw * tz + (qx * ty - qy * tx))
end

-- A unit's pose: its axes and translation.
local function pose(rot, p)
	local function axis(v) return rot and rot.w and elements_rotate(rot, v) or v end
	return { x = axis(vec(1, 0, 0)), y = axis(vec(0, 1, 0)), z = axis(vec(0, 0, 1)), t = p }
end
M.pose = pose

local function quat_rotate(q, v)
	if q.axis and math.abs(q.axis.z) == 1 then
		local c, s = math.cos(q.angle * q.axis.z), math.sin(q.angle * q.axis.z)
		return vec(v.x * c - v.y * s, v.x * s + v.y * c, v.z)
	end
	return vec(v.x, v.y, v.z)
end

function M.install()
	local loaded = {}
	local function load_script(name)
		if loaded[name] then return end
		loaded[name] = true
		local code = read(M.root, name)
		if not code then return end
		local fn = assert(loadstring(code, name))
		fn()
	end
	_G.require = load_script

	_G.IS_PC, _G.IS_PS4, _G.IS_PSVITA = true, false, false
	-- The game's assert takes a format, and is switched off in the retail build.
	_G.assert = function(v) return v end
	_G.sprintf = string.format
	_G.Profiler = { start = function() end, stop = function() end }
	_G.FlatProfiler = _G.Profiler
	_G.Log = setmetatable({}, { __index = function() return function() end end })
	M.feed = {}
	_G.Debug = { feed_and_log = function(_, text, ...) M.feed[#M.feed + 1] = string.format(text, ...) end }
	_G.Color = function(...) return { ... } end
	_G.Application = { make_hash = function(s) return string.format("%x", #s * 2654435761 % 2 ^ 32) end }
	math.clamp = math.clamp or function(v, lo, hi) return math.max(lo, math.min(hi, v)) end
	math.round = math.round or function(v) return math.floor(v + 0.5) end
	math.lerp = math.lerp or function(a, b, t) return a + (b - a) * t end

	-- The engine's random step: (seed, ...) -> next seed, value. Any fixed sequence serves here.
	_G.Math = {
		next_random = function(seed, a, b)
			seed = (seed * 48271 + 11) % 2147483647
			local f = seed / 2147483647
			if a == nil then return seed, f end
			if b == nil then return seed, 1 + math.floor(f * a) end
			return seed, a + math.floor(f * (b - a + 1))
		end,
	}

	_G.Vector3 = setmetatable({
		zero = function() return vec(0, 0, 0) end,
		forward = function() return vec(0, 1, 0) end,
		up = function() return vec(0, 0, 1) end,
		x = function(v) return v.x end,
		y = function(v) return v.y end,
		z = function(v) return v.z end,
		normalize = function(v)
			local l = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
			return l > 0 and v / l or vec(0, 0, 0)
		end,
		distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end,
		distance_squared = function(a, b) return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2 end,
		length = function(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end,
	}, { __call = function(_, x, y, z) return vec(x, y, z) end })
	_G.Vector2 = function(x, y) return vec(x, y, 0) end
	_G.Vector3Aux = {
		box = function(t, v) t = t or {}; t.x, t.y, t.z = v.x, v.y, v.z; return t end,
		unbox = function(t) return vec(t.x, t.y, t.z) end,
	}
	_G.Vector2Aux = {
		box = function(t, v) t = t or {}; t.x, t.y = v.x, v.y; return t end,
		unbox = function(t) return vec(t.x, t.y, 0) end,
	}
	_G.Quaternion = setmetatable({
		rotate = quat_rotate,
		right = function(q) return q.right end,
		from_elements = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end,
	}, { __call = function(_, axis, angle) return { axis = axis, angle = angle } end })
	_G.QuaternionAux = { box = function(t, q) t = t or {}; t.q = q; return t end, unbox = function(t) return t.q end }
	_G.Rotation2D = function(pos, angle) return { pos = pos, angle = angle } end
	_G.ProvinggroundsSettings = { get_all_flat_sub_modifiers = function() return {} end }

	load_script("foundation/lua/base/class")
	load_script("foundation/lua/util/table_aux")
	load_script("foundation/lua/util/array")
	load_script("foundation/lua/util/randomizer")
	load_script("lua/settings/difficulty_settings")
	load_script("lua/settings/environment_settings")
	load_script("lua/settings/generated_level_settings")
	load_script("lua/utility/generated_level")

	-- Packages, the map world and levels: recorded, nothing more.
	M.packages, M.levels, M.bitmaps, M.units = {}, {}, {}, {}
	_G.Boot = { package_manager = {
		load_package = function(_, name) M.packages[name] = true end,
		unload_package = function(_, name) M.packages[name] = nil end,
		is_package_online = function(_, name) return M.packages[name] == true end,
		has_property_preference = function() return true end,
		add_property_preference = function() end,
		remove_property_preference = function() end,
		get_size_in_bytes = function() return 10 end,
		get_loaded_bytes = function() return 10 end,
	} }
	_G.World = {
		update = function() end,
		physics_world = function() return {} end,
		levels = function() return M.levels end,
		timpani_world = function() return {} end,
		create_screen_gui = function(_, _, _, material) return { material = material } end,
		create_shading_environment = function() return {} end,
		spawn_unit = function(_, unit, pos, rot)
			local u = { unit = unit, pos = pos, rot = rot, shown = true }
			M.units[#M.units + 1] = u
			return u
		end,
		destroy_gui = function() end,
	}
	_G.Application.new_world = function() return {} end
	_G.Application.create_viewport = function() return {} end
	_G.Application.render_world = function() end
	_G.Application.release_world = function() end
	_G.Unit = {
		camera = function() return {} end,
		set_unit_visibility = function(u, shown) u.shown = shown end,
		num_meshes = function() return 1 end,
		mesh_visibility = function(u) return u.mesh_shown ~= false end,
		set_mesh_visibility = function(u, _, shown) u.mesh_shown = shown end,
		local_position = function(u) return u.pose.t end,
		local_pose = function(u) return u.pose end,
		set_local_pose = function(u, _, m) u.pose = m end,
	}
	_G.Matrix4x4 = {
		x = function(m) return m.x end, y = function(m) return m.y end, z = function(m) return m.z end,
		translation = function(m) return m.t end,
		from_axes = function(x, y, z, t) return { x = x, y = y, z = z, t = t } end,
	}
	_G.Gui = { bitmap_3d = function(gui, name, turn, _, _, size)
		M.bitmaps[#M.bitmaps + 1] = { gui = gui, name = name, pos = turn.pos, size = size }
	end }
	_G.TimpaniWorld = { set_environment = function() end }
	_G.LevelResource = { object_set_names = function(path)
		M.asked = M.asked or {}
		M.asked[#M.asked + 1] = path
		return { "_hidden", "day", "night", "bugs", "plain" }
	end }
	_G.Level = {
		set_data = function(level, name, value) level.data[name] = value end,
		set_flow_variable = function() end,
		trigger_level_loaded = function() end,
		units = function(level) return level.units end,
	}
end

function M.world_proxy()
	local viewport = { set_shading_environment = function(_, name) M.shading = name end, set_shading_environment_settings = function() end }
	local class = {}
	class.__index = class
	function class:get_world() return {} end
	function class:viewport() return viewport end
	function class:load_level_with_object_sets(name, path, _, sets, _, pos, rot)
		-- A ground mesh at the level's origin and a prop 5 m across and 7 m along the level's own
		-- axes, 3 m up, as the game's pieces have them; each placed by the level's turn.
		local function at(x, y, z)
			local d = rot and rot.w and elements_rotate(rot, vec(x, y, z)) or vec(x, y, z)
			return pose(rot, vec(pos.x + d.x, pos.y + d.y, pos.z + d.z))
		end
		local ground = { shown = true, ground = true, pose = at(0, 0, 0) }
		local prop = { shown = true, pose = at(5, 7, 3) }
		local level = { name = name, path = path, sets = sets, pos = pos, rot = rot, data = {}, units = { ground, prop } }
		M.levels[#M.levels + 1] = level
		return level
	end
	return setmetatable({}, class)
end

-- A mission seed as the game writes one (DifficultySettings.modulate_seed).
function M.seed(layout, environment, enemy, difficulty, time_of_day)
	local envs = { desert = 0, forest = 1, snow = 2, lava = 3, city = 4 }
	local enemies = { bugs = 0, cyborgs = 1, illuminates = 2 }
	return layout * 10000000 + (time_of_day or 1) * 1000000 + envs[environment] * 10000 + enemies[enemy] * 100 + difficulty
end

-- The steps the briefing's map takes (a level with no world), then, with `spawn`, the mission's.
function M.build(seed, spawn)
	M.levels, M.bitmaps, M.units, M.asked, M.feed = {}, {}, {}, {}, {}
	local GeneratedLevel = _G.GeneratedLevel
	local level = GeneratedLevel()
	local proxy = spawn and M.world_proxy() or nil
	level:initialize(proxy, seed)
	if not spawn then level:load_map() end
	level:generate_area()
	level:generate_mission()
	level:generate_children()
	level:generate_unique()
	level:generate_children()
	level:generate_extract()
	level:generate_children()
	level:generate_rare()
	level:generate_children()
	level:generate_special()
	level:generate_edge()
	level:generate_common()
	if spawn then
		level:load_map()
		level:load_resources(true)
		level:spawn_levels({ build_level_units_lookup = function() end, register_level_units = function() end, num_level_entities = 0 }, true)
	end
	level:update_map()
	return level
end

return M
