-- ProcFS module

local procAddr = "procfs"

component.add {
	address = procAddr,
	type = "procfs",
	invoke = function() end,
	methods = {},
	slot = -1,
}

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
	uptime = function() return computer.uptime() .. "\n" end,
	meminfo = function()
		return string.format("Free: %d\nTotal: %d\n", computer.freeMemory(), computer.totalMemory())
	end,
}

---@param req string
return function(req, ...)
	local readonlyPerms = 4*64 + 4*8 + 4
	if req == "dkms_close" then
		component.remove(procAddr)
		return
	end
	if req == "FS-mount" then
		local dev = ...
		if dev.address == "procfs" then
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
		Kocos.printkf(Kocos.L_DEBUG, "stat: %s", path)
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
				}
			end
		end
		return nil, Kocos.ENOENT
	end
end
