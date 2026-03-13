--!lua

-- Ensure root exists
local function log(fmt, ...)
	k.invokeDaemon("initd", "log", 1, string.format(fmt, ...))
end

if k.sysinfo().rootAddress == "ramfs" then
	-- Check if installer
	log("initfs: ramfs root!")
	if k.exists("/home") then
		log("initfs: assumed installer due to /home")
	else
		log("initfs: finding real root")
		local root = k.kcmdline()["ROOT"] or k.sysinfo().bootAddress
		log("initfs: real root: %s", root)

		log("initfs: unmounting old root")
		assert(k.umount("/"))
		log("initfs: mounting new root")
		assert(k.mount("/", root))
	end
end

local ensureExists = {
	"/tmp",
	"/dev",
	"/proc",
	"/mnt",
	"/media",
}
for _, f in ipairs(ensureExists) do
	if not k.exists(f) then
		log("initfs: creating %s with 511 permissions", f)
		assert(k.mkdir(f, 511))
	end
end

local tmpAddr = assert(k.sysinfo()).tmpAddress

log("initfs: mounted tmp")
if tmpAddr then assert(k.mountDev("/tmp", tmpAddr)) end

log("initfs: loading fstab")
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
			log("initfs: missing device %s for %s", dev, path)
		end
	end
end
