-- Offline tests. From the repository's root:
--   luajit tests/run.lua
-- The tests in test_game.lua build real maps with the game's own scripts (tests/game.lua) and are
-- skipped where those aren't on the machine.
local loaded = {}
obsidian = {
	module = function(name)
		if loaded[name] == nil then loaded[name] = dofile(name .. ".lua") end
		return loaded[name]
	end,
	log = function() end,
}

local passed, failed, skipped = 0, 0, 0
local function test(name, fn)
	local ok, err = xpcall(fn, debug.traceback)
	if ok and err == "skip" then
		skipped = skipped + 1
	elseif ok then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL " .. name .. "\n" .. tostring(err))
	end
end

function eq(got, want, what)
	if got ~= want then error((what or "value") .. ": expected " .. tostring(want) .. ", got " .. tostring(got), 2) end
end

function yes(v, what)
	if not v then error((what or "condition") .. " is false", 2) end
end

function near(got, want, tolerance, what)
	if math.abs(got - want) > tolerance then
		error((what or "value") .. ": expected " .. tostring(want) .. " within " .. tostring(tolerance) .. ", got " .. tostring(got), 2)
	end
end

local only = arg and arg[1]
for _, file in ipairs({ "tests/test_core.lua", "tests/test_game.lua" }) do
	if not only or file:find(only, 1, true) then
		local tests = dofile(file)
		for _, t in ipairs(tests) do test(file .. " " .. t[1], t[2]) end
	end
end
print(passed .. " passed, " .. failed .. " failed" .. (skipped > 0 and (", " .. skipped .. " skipped (the game's scripts aren't here)") or ""))
os.exit(failed == 0 and 0 or 1)
