-- Obsidian Worldgen: entry script. A library: it changes nothing until another mod gives it a rule.
--
--   local worldgen = obsidian.import("obsidian.worldgen")
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

level.log = function(text)
	obsidian.log(text)
end

level.install(obsidian.hook)

-- Backdrop pieces and props far from the camera are hidden, where a profile asks for that.
local frame = 0
if obsidian.on_frame then
	obsidian.on_frame(function()
		frame = frame + 1
		if frame % 20 ~= 0 or not level.active then return end
		local camera = rawget(_G, "CameraManager")
		if not (camera and camera.get_position and camera.position) then return end
		local pos = camera:get_position()
		level.cull(pos.x, pos.y)
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

-- What the generator did for the mission being played, or nil when the map is the game's own:
-- { profile, blocks, biomes = { names }, top = highest ground }.
function api.current()
	local wg = level.active and level.active.wg
	if not wg then return nil end
	local names = {}
	for i, b in ipairs(wg.biomes) do names[i] = b.name end
	return { profile = wg.profile.id, blocks = wg.blocks, biomes = names, top = wg.relief and wg.relief.top or 0 }
end

obsidian.log("Obsidian Worldgen ready")
return api
