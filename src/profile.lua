-- A profile says how one mission's map is made. A mod hands one over from a rule (see main.lua);
-- this file turns it into settled choices, the same on every machine: every "any" is drawn from the
-- seed, every number is brought inside what the game can carry.
local shapes = obsidian.module("src/shapes")
local regions = obsidian.module("src/regions")

local M = {}

M.BIOMES = { "desert", "forest", "snow", "lava", "city" }
M.MAX_BLOCKS = 170 -- 680 cells of ground: more than any map of the game, under what a 24 by 24 one holds
M.MAX_RINGS = 4

local function clamp(v, lo, hi, default)
	v = tonumber(v)
	if not v then return default end
	return math.max(lo, math.min(hi, v))
end

local function one_of(value, names, rng, default)
	if type(value) == "table" then value = #value > 0 and rng:pick(value) or default end
	if value == "any" then return rng:pick(names) end
	if value == nil then return default end
	for i = 1, #names do
		if names[i] == value then return value end
	end
	return default
end

local function is_biome(name)
	for i = 1, #M.BIOMES do
		if M.BIOMES[i] == name then return true end
	end
	return false
end

-- p: the profile a rule answered. ctx: what the mission is (environment, enemy, difficulty, seed).
-- rng: the map's own stream. Answers the settled profile; nothing in p is changed.
function M.resolve(p, ctx, rng)
	local out = { id = tostring(p.id or "profile") }

	local r = rng:fork("shape")
	out.shape = one_of(p.shape, shapes.names, r, "vanilla")
	out.size = clamp(p.size, 0.25, 8, 1)
	out.across = math.floor(clamp(p.across, 4, shapes.MAX_ACROSS, shapes.MAX_ACROSS))
	out.max_blocks = math.floor(clamp(p.max_blocks, 4, M.MAX_BLOCKS, M.MAX_BLOCKS))
	out.shape_opts = type(p.shape_opts) == "table" and p.shape_opts or {}

	-- Biomes: the planet's own first, then the ones the profile adds, each once.
	r = rng:fork("biomes")
	out.biomes = { { env = ctx.environment, weight = clamp(p.own_weight, 0.05, 20, 1) } }
	local seen = { [ctx.environment] = true }
	local wanted = p.biomes
	if wanted == "any" then wanted = { "any" } end
	if type(wanted) == "table" then
		for i = 1, #wanted do
			local b = wanted[i]
			local env = type(b) == "table" and b.env or b
			local weight = type(b) == "table" and b.weight or 1
			if env == "any" then
				local free = {}
				for j = 1, #M.BIOMES do
					if not seen[M.BIOMES[j]] then free[#free + 1] = M.BIOMES[j] end
				end
				env = r:pick(free)
			end
			if env and is_biome(env) and not seen[env] and #out.biomes < 4 then
				seen[env] = true
				out.biomes[#out.biomes + 1] = { env = env, weight = clamp(weight, 0.05, 20, 1) }
			end
		end
	end
	out.layout = one_of(p.layout, regions.names, r, "patches")

	if p.relief then
		local rel = type(p.relief) == "table" and p.relief or { height = tonumber(p.relief) }
		out.relief = {
			height = clamp(rel.height, 0, 40, 6),
			step = clamp(rel.step, 0.1, 5, 1.25),
			rough = clamp(rel.rough, 0, 1, 0.5),
		}
		if out.relief.height <= 0 then out.relief = nil end
	end

	local o = type(p.objectives) == "table" and p.objectives or {}
	out.objectives = {
		scale = clamp(o.scale, 0.25, 4, 1),
		max = o.max and math.floor(clamp(o.max, 1, 12, 6)) or nil,
		max_unique = o.max_unique and math.floor(clamp(o.max_unique, 1, 16, 10)) or nil,
		filter = type(o.filter) == "function" and o.filter or nil,
	}

	out.open = p.open == true -- no set pieces: unique, rare and special steps are skipped
	out.remix = type(p.remix) == "function" and p.remix or nil

	local b = p.backdrop
	if type(b) == "number" then b = { rings = b } end
	if type(b) == "table" then
		local rings = math.floor(clamp(b.rings, 0, M.MAX_RINGS, 0))
		if rings > 0 then out.backdrop = { rings = rings } end
	end
	out.cull = p.cull and clamp(p.cull, 60, 2000, 240) or nil

	out.packages = {}
	if type(p.packages) == "table" then
		for i = 1, #p.packages do
			if type(p.packages[i]) == "string" then out.packages[#out.packages + 1] = p.packages[i] end
		end
	end

	out.props = {}
	if type(p.props) == "table" then
		for i = 1, #p.props do
			local q = p.props[i]
			if type(q) == "table" and type(q.unit) == "string" then
				local per = q.per_tile
				local lo, hi = 1, 1
				if type(per) == "table" then lo, hi = per[1], per[2] or per[1] elseif per then lo, hi = per, per end
				out.props[#out.props + 1] = {
					unit = q.unit,
					min = math.floor(clamp(lo, 0, 12, 1)),
					max = math.floor(clamp(hi, 0, 12, 1)),
					chance = clamp(q.chance, 0, 1, 1),
					margin = clamp(q.margin, 0, 11, 2),
					on = type(q.on) == "table" and q.on or { "common" },
					biomes = type(q.biomes) == "table" and q.biomes or nil,
					lift = clamp(q.lift, -5, 20, 0),
				}
			end
		end
	end
	return out
end

-- Whether a settled profile changes anything at all. One that doesn't leaves the level untouched.
function M.is_plain(out)
	return out.shape == "vanilla" and out.size == 1 and #out.biomes == 1 and not out.relief
		and out.objectives.scale == 1 and not out.objectives.max and not out.objectives.max_unique
		and not out.objectives.filter and not out.open and not out.remix and not out.backdrop
		and #out.props == 0 and #out.packages == 0
end

return M
