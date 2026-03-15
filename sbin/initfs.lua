--!lua

-- TODO: completely rework this
-- so the installer can just generate
-- a good /etc/fstab

-- Ensure root exists
local function log(severity, fmt, ...)
	k.invokeDaemon("initd", "log", severity, string.format(fmt, ...))
end

local function autoRoot()
	local boot = k.sysinfo().bootAddress
	if k.ctype(boot) == "filesystem" then return boot end

	-- Check root partitions
	for addr in k.clist("partition", true) do
		---@type Kocos.partdev
		local p = assert(k.cproxy(addr))
		if p.getStorageDevice() == boot and p.getPartitionType() == "root" then
			return addr
		end
	end
	-- Just assume it works
	return boot
end

---@return string?
local function autoBoot()
	local boot = k.sysinfo().bootAddress
	if k.ctype(boot) == "filesystem" then return end

	-- Check root partitions
	for addr in k.clist("partition", true) do
		---@type Kocos.partdev
		local p = assert(k.cproxy(addr))
		if p.getStorageDevice() == boot and p.getPartitionType() == "bldr" then
			return addr
		end
	end
	-- Just assume it works
	return boot
end

log("DEBUG", "initfs: reading fstab")
local data = assert(readfile("/etc/fstab"))
local fstab = string.split(data, "\n")

if k.sysinfo().rootAddress == "ramfs" then
	-- Check if installer
	log("DEBUG", "initfs: ramfs root!")
	if k.exists("/home") then
		log("DEBUG", "initfs: assumed installer due to /home")
	else
		log("INFO", "initfs: removing old root")
		assert(k.umount("/"))
	end
end

local function ensureBasicDirs()
	local ensureExists = {
		"/tmp",
		"/dev",
		"/proc",
		"/mnt",
		"/media",
	}
	for _, f in ipairs(ensureExists) do
		if not k.exists(f) then
			log("DEBUG", "initfs: creating %s with 511 permissions", f)
			assert(k.mkdir(f, 511))
		end
	end
end

---@type table<string, string>
local vars = {
	ROOT = autoRoot(),
	BOOT = autoBoot() or "no-boot",
	TMP = k.sysinfo().tmpAddress,
	PROCFS = "procfs",
	DEVFS = "devfs",
}

log("DEBUG", "initfs: loading fstab")
for _, line in ipairs(fstab) do
	if #line > 0 and line:sub(1, 1) ~= "#" then
		local parts = string.split(line, " ")
		local dev = parts[1]
		local path = parts[2]
		dev = vars[dev] or dev
		local cmdline = table.concat(parts, " ", 3)
		if k.isMount(path) then
			log("WARN", "initfs: %s already mounted", path)
		elseif k.ctype(dev) then
			assert(k.mount(path, dev, cmdline))
			if path == "/" then
				ensureBasicDirs()
			end
		else
			log("WARN", "initfs: missing device %s for %s", dev, path)
		end
	end
end

