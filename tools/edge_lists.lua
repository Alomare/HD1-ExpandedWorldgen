-- The edge piece lists of every biome, with sizes: luajit tools/edge_lists.lua
obsidian = { log = function() end }
local loaded = {}
obsidian.module = function(name)
	if loaded[name] == nil then loaded[name] = dofile(name .. ".lua") end
	return loaded[name]
end
local game = dofile("tests/game.lua")
if not game.available then print("the game's scripts aren't here") os.exit(0) end
game.install()
local settings = rawget(_G, "EnvironmentSettings")
for _, env in ipairs({ "desert", "forest", "snow", "lava", "city" }) do
	local e = settings.mission[env]
	for _, list in ipairs({ "edge_straight", "edge_fill", "edge_concave", "edge_convex" }) do
		local parts = {}
		for _, m in ipairs(e[list] or {}) do parts[#parts + 1] = m.name .. " " .. m.size[1] .. "x" .. m.size[2] .. (m.races and " races" or "") end
		print(env, list, #(e[list] or {}), table.concat(parts, ", "))
	end
end
