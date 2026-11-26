-- Expanded Worldgen: entry script. A library: it changes nothing until another mod gives it a rule.
--
--   local worldgen = obsidian.import("alomare.expandedworldgen")
--   worldgen.rule(function(mission)
--       -- mission: seed, layout, environment, enemy, difficulty, time_of_day, preview
--       return { shape = "ring", size = 1.5, biomes = { "snow" }, relief = 6 }
--   end)
--
-- A rule runs on every machine, for the mission and for the map previews, and has to answer the
-- same profile everywhere: decide from `mission` and from option values every player shares, never
-- from anything only one machine knows. The mod that adds it sets "every_player": true.
local level = obsidian.module("src/level")
local shapes = obsidian.module("src/shapes")
local regions = obsidian.module("src/regions")
local profiles = obsidian.module("src/profile")
local view = obsidian.module("src/view")

level.log = function(text)
	obsidian.log(text)
end

level.install(obsidian.hook)

-- Where this player's camera is: the camera the game draws with (a free or third person camera
-- moves it), else the camera manager's.
local function camera_position(manager)
	local ok, pos = pcall(function()
		return rawget(_G, "Camera").world_position(manager.viewport:get_camera())
	end)
	if ok and pos then return pos end
	if manager.get_position and manager.position then return manager:get_position() end
	return nil
end

-- Units far from the camera are hidden by their size (src/view.lua); backdrop pieces and props far
-- from it too, where a profile asks for that.
local frame, view_failed = 0, false
if obsidian.on_frame then
	obsidian.on_frame(function()
		frame = frame + 1
		if not level.active then return end
		local camera = rawget(_G, "CameraManager")
		if type(camera) ~= "table" then return end
		local pos = camera_position(camera)
		if not pos then return end
		if not view_failed then
			local ok, err = pcall(level.view, pos.x, pos.y)
			if not ok then
				view_failed = true
				obsidian.log("draw distances stopped: " .. tostring(err))
			end
		end
		if frame % 20 == 0 then level.cull(pos.x, pos.y) end
	end)
end

local api = { version = 1 }

-- Adds a rule. Rules are asked in the order mods added them; the first profile answered is used.
--
-- A rule belongs to the mod that adds it and is asked only while the loader has that mod on. Maps
-- are built by every machine, so a mod that adds a rule has to be one every player runs
-- ("every_player": true in its obsidian.json): the loader then switches it off, on every machine,
-- while someone in the lobby is without it, and the maps are the game's own.
function api.rule(fn)
	if type(fn) ~= "function" then return false, "not_a_function" end
	local rule = { fn = fn, owner = obsidian.caller and obsidian.caller() or "?", on = true }
	-- Asked here, while the adding mod's code runs, these two answer for that mod.
	if obsidian.session and obsidian.session.cleared then rule.on = obsidian.session.cleared() and true or false end
	if obsidian.on_session then
		obsidian.on_session(function(on) rule.on = on and true or false end)
	end
	level.rules[#level.rules + 1] = rule
	return true
end

-- What a profile may name.
function api.shapes()
	local out = { "vanilla" }
	for _, name in ipairs(shapes.names) do out[#out + 1] = name end
	return out
end

function api.layouts()
	local out = {}
	for _, name in ipairs(regions.names) do out[#out + 1] = name end
	return out
end

function api.biomes()
	local out = {}
	for _, name in ipairs(profiles.BIOMES) do out[#out + 1] = name end
	return out
end

-- The height of the ground at a world position in the mission being played, in metres. 0 on a
-- flat map and outside a mission.
function api.height(x, y)
	return level.height(x, y)
end

-- How far this player sees the units of a map made by a rule: a scale of the draw distances (1 is
-- the default, 0.5 to 8), or false to draw everything. Only this player's picture changes, so the
-- value may differ between players. Answers the scale in use.
function api.view(scale)
	if scale == false then
		level.view_scale = nil
	elseif scale ~= nil then
		level.view_scale = view.clamp_scale(scale) or level.view_scale
	end
	return level.view_scale or false
end

-- What the generator did for the mission being played, or nil when the map is the game's own:
-- { profile, blocks, biomes = { names }, top = highest ground }.
function api.current()
	local wg = level.active and level.active.wg
	if not wg then return nil end
	local names = {}
	for i, b in ipairs(wg.biomes) do names[i] = b.name end
	return { profile = wg.profile.id, blocks = wg.blocks, biomes = names, top = wg.relief and wg.relief.top or 0 }
end

obsidian.log("Expanded Worldgen ready")
return api
