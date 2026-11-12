-- A random stream of the generator's own, the same on every machine for the same seed and label.
-- The game's Randomizer keeps feeding the game's own steps; the generator never draws from it, so a
-- profile changes nothing in how many numbers the game's steps take.
--
-- Park-Miller (48271 mod 2^31 - 1). Every product stays under 2^53, so doubles carry it exactly.
local M = {}
M.__index = M

local MOD = 2147483647
local MUL = 48271

local function mix(seed, label)
	local s = (math.floor(tonumber(seed) or 0) % MOD + 7919) % MOD
	label = tostring(label or "")
	for i = 1, #label do
		s = (s * 31 + label:byte(i)) % MOD
	end
	if s == 0 then s = 1 end
	return s
end

function M.new(seed, label)
	local r = setmetatable({ s = mix(seed, label) }, M)
	-- The first draws of nearby seeds are close together; throw a few away.
	for _ = 1, 4 do r:next() end
	return r
end

function M:next()
	self.s = (self.s * MUL) % MOD
	return self.s
end

-- [0, 1)
function M:float()
	return (self:next() - 1) / (MOD - 1)
end

-- A whole number from a to b, both included. int(n) is from 1 to n.
function M:int(a, b)
	if b == nil then a, b = 1, a end
	if b <= a then return a end
	return a + math.floor(self:float() * (b - a + 1))
end

function M:range(a, b)
	return a + (b - a) * self:float()
end

function M:chance(p)
	return self:float() < p
end

function M:pick(list)
	local n = #list
	if n == 0 then return nil end
	return list[self:int(1, n)]
end

-- One of `list` by weight, weight(item) answering a number; nil for an empty list or no weight at all.
function M:weighted(list, weight)
	local total = 0
	for i = 1, #list do total = total + math.max(0, weight(list[i]) or 0) end
	if total <= 0 then return nil end
	local at = self:float() * total
	for i = 1, #list do
		at = at - math.max(0, weight(list[i]) or 0)
		if at < 0 then return list[i], i end
	end
	return list[#list], #list
end

function M:shuffle(list)
	for i = #list, 2, -1 do
		local j = self:int(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

-- A stream of its own under this one, for a named part of the work: what one part draws never
-- moves the numbers of another.
function M:fork(label)
	return M.new(self.s, label)
end

return M
