--!lua

local dev, path, cmdline = ...

local addr = assert(io.todevice(dev))

local ok, err = k.mount(path, addr, cmdline)
if not ok then
	io.ewrite("mount: ", err, "\n")
	return 1
end
