--!lua

local devutils = require("devutils")
local devs = {...}

local lost = 0
for _, dev in ipairs(devs) do
	dev = assert(io.todevice(dev))
	if #devs > 1 then
		io.write(dev, ": ")
	end
	local p = devutils.pathToDev(dev)
	print(p or "")
	if not p then lost = lost + 1 end
end
return lost
