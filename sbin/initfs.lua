--!lua

local ensureExists = {
	"/tmp",
	"/dev",
	"/mnt",
	"/media",
}
for _, f in ipairs(ensureExists) do
	if not k.exists(f) then
		assert(k.mkdir(f, 511))
	end
end

local tmpAddr = k.sysinfo().tmpAddress

if tmpAddr then assert(k.mountDev("/tmp", tmpAddr)) end
--assert(k.mountDev("/dev", "devfs"))
