--!lua

local ensureExists = {
	"/tmp",
	"/dev",
	"/mnt",
	"/media",
}
for _, f in ipairs(ensureExists) do
	if not k.exists(f) then
		assert(k.mkdir(f, 2^16-1))
	end
end

local tmpAddr = k.sysinfo().tmpAddress

assert(k.mountDev("/tmp", tmpAddr))
assert(k.mountDev("/dev", "devfs"))
