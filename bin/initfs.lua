--!lua

local ensureExists = {
	"/tmp",
	"/dev",
	"/mnt",
}
for _, f in ipairs(ensureExists) do
	if not k.exists(f) then
		assert(k.mkdir(f))
	end
end

local tmpAddr = k.sysinfo().tmpAddress

assert(k.mountDev("/tmp", tmpAddr))
