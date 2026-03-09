--!lua

local dev, path, cmdline = ...

local stat = k.stat(dev)
local addr
if stat then
	if stat.type == "device" then
		addr = stat.deviceAddress
	else
		io.ewrite(dev, ": not a device\n")
		return 1
	end
else
	addr = assert(k.caddress(dev))
end

local ok, err = k.mount(path, addr, cmdline)
if not ok then
	io.ewrite("mount: ", err, "\n")
	return 1
end
