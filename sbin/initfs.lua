--!lua

local ensureExists = {
	"/tmp",
	"/dev",
	"/proc",
	"/mnt",
	"/media",
}
for _, f in ipairs(ensureExists) do
	if not k.exists(f) then
		assert(k.mkdir(f, 511))
	end
end

local tmpAddr = assert(k.sysinfo()).tmpAddress

if tmpAddr then assert(k.mountDev("/tmp", tmpAddr)) end

local data = assert(readfile("/etc/fstab"))
local fstab = string.split(data, "\n")

for _, line in ipairs(fstab) do
	if #line > 0 and line:sub(1, 1) ~= "#" then
		local parts = string.split(line, " ")
		local dev = parts[1]
		local path = parts[2]
		local cmdline = table.concat(parts, " ", 3)
		if k.ctype(dev) then
			assert(k.mount(path, dev, cmdline))
		else
			k.invokeDaemon("initd", "log", string.format("initfs: missing device %s for %s", dev, path))
		end
	end
end
