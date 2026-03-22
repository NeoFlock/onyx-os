-- ProcFS module

local procAddr = "procfs"

---@type table<string, fun(): string>
local rootFiles = {
	cmdline = function() return Kocos.encodeCmdline(Kocos.cmdline) .. "\n" end,
	mounts = function()
		local lines = {"# DEVICE PATH CMDLINE"}
		for p, state in pairs(Kocos.mounts) do
			table.insert(lines, string.format("%s %s %s", state.device, "/" .. p, state.cmdline))
		end
		return table.concat(lines, "\n") .. "\n"
	end,
	kmodules = function()
		local lines = {}
		for mod in pairs(Kocos.mods) do
			table.insert(lines, mod)
		end
		return table.concat(lines, "\n") .. "\n"
	end,
	version = function()
		return string.format("%s\n%s\n%s\n", _KVERSION, _OSVERSION, _VERSION)
	end,
	uptime = function() return computer.uptime() .. "\n" end,
	meminfo = function()
		return string.format("Free: %d\nTotal: %d\n", computer.freeMemory(), computer.totalMemory())
	end,
	compusage = function()
		local lines = {"COMPONENT READ WRITE IOCTL"}
		for comp, info in pairs(Kocos.componentUsage) do
			table.insert(lines, string.format("%s %d %d %d", comp, info.read, info.write, info.ioctl))
		end
		return table.concat(lines, "\n") .. "\n"
	end,
}

---@param req string
return function(req, ...)
	local readonlyPerms = 4*64 + 4*8 + 4
	if req == "dkms_init" then
		component.add {
			address = procAddr,
			type = "procfs",
			invoke = function() end,
			methods = {},
			slot = -1,
		}
		return
	end
	if req == "dkms_close" then
		component.remove(procAddr)
		return
	end
	if req == "FS-mount" then
		local dev = ...
		if dev.address == procAddr then
			return "procfs"
		end
		return
	end
	if req == "FS-sync" then return true end
	if req == "FS-list" then
		---@type _, string
		local _, path = ...
		if path == "" then
			local l = {}
			for p in pairs(rootFiles) do
				table.insert(l, p)
			end
			return l
		end
		return nil, Kocos.ENOENT
	end
	if req == "FS-open" then
		---@type _, string
		local _, path = ...
		if rootFiles[path] then
			return Kocos.romFile("file", rootFiles[path]())
		end
		return nil, Kocos.ENOENT
	end
	if req == "FS-stat" then
		---@type _, string
		local _, path = ...
		if path == "" then
			---@type Kocos.fstat
			return {
				type = "directory",
				deviceAddress = procAddr,
				diskSize = 0,
				size = 0,
				diskUsed = 0,
				diskTotal = 0,
				uid = 0,
				gid = 0,
				inode = 0,
				lastModified = 0,
				perms = readonlyPerms,
				linkCount = 1,
			}
		end
		for p, _ in pairs(rootFiles) do
			if path == p then
				---@type Kocos.fstat
				return {
					type = "regular",
					deviceAddress = procAddr,
					diskSize = 0,
					size = 0,
					diskUsed = 0,
					diskTotal = 0,
					uid = 0,
					gid = 0,
					inode = 0,
					lastModified = 0,
					perms = readonlyPerms,
					linkCount = 1,
				}
			end
		end
		return nil, Kocos.ENOENT
	end
end
