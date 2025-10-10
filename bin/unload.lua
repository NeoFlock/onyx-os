--!lua

local patterns = {...}

local toRemove = {}

for p in pairs(package.loaded) do
	for _, pat in ipairs(patterns) do
		if string.match(p, pat) then
			table.insert(toRemove, p)
			break
		end
	end
end

for _, p in ipairs(toRemove) do
	package.loaded[p] = nil
end
