--!lua

local buf = {}
local function hasData()
	return #buf > 0
end

assert(k.mklistener(function(...)
	local t = {...}
	for i=1,#t do
		t[i] = table.serialize(t[i], nil, table.colorTypeInfo)
	end
	table.insert(buf, string.format("[%f] %s", k.uptime(), table.concat(t, ", ")))
end))

while true do
	k.blockUntil(k.getpid(), hasData)
	local data = table.remove(buf, 1)
	print(data)
end
