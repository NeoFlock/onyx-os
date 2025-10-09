--!lua

local mounts = k.getMounts()

local minsize = 1
for dev, p in pairs(mounts) do
	minsize = math.max(minsize, #p)
end

for dev, p in pairs(mounts) do
	local t = k.ctype(dev)
	print(dev, string.rightpad(p, minsize, " "), t)
end
