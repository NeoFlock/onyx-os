-- DevFS abstraction
local fs = Kocos.fs

---@param addr string
local function devfsAddrSuffix(addr)
	return addr:sub(1, 3):upper()
end

local function computeDeviceFiles()
	---@type table<string, string>
	local f = {}
	for addr, type in component.list() do
		local name
		if type == "filesystem" then
			name = "fs" .. devfsAddrSuffix(addr)
		elseif type == "drive" then
			name = "hd" .. devfsAddrSuffix(addr)
		elseif type == "partition" then
			local devaddr = component.invoke(addr, "getDeviceAddress") or "ERR"
			name = "hd" .. devfsAddrSuffix(devaddr) .. "p" .. devfsAddrSuffix(addr)
		elseif type == "serial" then -- imaginary component for all serial comms
			name = "usb" .. devfsAddrSuffix(addr)
		elseif type == "gpu" then
			name = "gpu" .. devfsAddrSuffix(addr)
		elseif type == "screen" then
			name = "screen" .. devfsAddrSuffix(addr)
		elseif type == "eeprom" then
			name = "eeprom" .. devfsAddrSuffix(addr)
		else
			-- TODO: handle the virtual drive abstraction
		end
		if name then f[name] = addr end
	end
	return f
end

---@param path string
---@param mode "r"|"w"|"a"
---@return Kocos.fs.FileDescriptor?, string?
local function devfsMakeFD(path, mode)
	local errno = Kocos.errno
	if path == "null" then
		---@type Kocos.fs.FileDescriptor
		return {
			write = function() return true end,
			read = function() end,
		}
	end
	if path == "zero" then
		if mode ~= "r" then return nil, errno.EPERM end
		---@type Kocos.fs.FileDescriptor
		return {
			read = function(_, len)
				if len == math.huge then len = 1 end
				return string.rep("\0", len)
			end,
		}
	end
	if path == "random" then
		if mode ~= "r" then return nil, errno.EPERM end
		---@type Kocos.fs.FileDescriptor
		return {
			read = function(_, len)
				if len == math.huge then len = 1 end
				local c = ""
				for _=1,len do
					c = c .. string.char(math.random(0, 255))
				end
				return c
			end,
		}
	end
	if path == "hex" then
		if mode ~= "r" then return nil, errno.EPERM end
		---@type Kocos.fs.FileDescriptor
		return {
			read = function(_, len)
				if len == math.huge then len = 1 end
				local c = ""
				local a = "0123456789ABCDEF"
				for _=1,len do
					local i = math.random(1, 16)
					c = c .. a:sub(i, i)
				end
				return c
			end,
		}
	end
	if path:sub(1,3) == "std" then
		local fd = Kocos.process["STD" .. path:sub(4):upper()]
		if not fd then return nil, errno.ENOENT end
		---@type Kocos.fs.FileDescriptor
		return {
			write = function(_, data)
				return syscall("write", fd, data)
			end,
			read = function(_, len)
				return syscall("read", fd, len)
			end,
			ioctl = function(_, action, ...)
				return syscall("ioctl", action, ...)
			end,
			seek = function(_, whence, off)
				return syscall("seek", whence, off)
			end,
			setflags = function(_, flags)
				return syscall("fcntl", Kocos.fs.F_SETFL, flags)
			end,
			-- no finalizer cuz no
		}
	end
	return nil, errno.ENOENT
end

---@param req string
function Kocos._default_devfs(req, ...)
	if req == "FS-mount" then
		---@type Kocos.device
		local dev = ...
		if dev.type ~= "devfs" then return end
		return "devfs"
	end
	if req == "FS-mkdir" then
		return nil, Kocos.errno.EPERM
	end
	if req == "FS-touch" then
		return nil, Kocos.errno.EPERM
	end
	if req == "FS-openFile" then
		---@type unknown, string, string
		local _, path, mode = ...
		return devfsMakeFD(path, mode)
	end
	if req == "FS-listDir" then
		---@type unknown, string
		local _, path = ...
		if path == "" then
			local files = {"components", "null", "zero", "random", "hex", "stdin", "stderr", "stdout", "stdterm"}
			for f in pairs(computeDeviceFiles()) do
				table.insert(files, f)
			end
			return files
		end
		if path == "components" then
			local f = {}
			for addr in component.list() do
				table.insert(f, addr)
			end
			return f
		end
		return nil, path
	end
	if req == "FS-ftype" then
		---@type unknown, string
		local _, path = ...
		if path == "" then return fs.FTYPE_DIR end
		if path == "components" then return fs.FTYPE_DIR end
		if path == "null" then return fs.FTYPE_CHR end
		if path == "zero" then return fs.FTYPE_CHR end
		if path == "random" then return fs.FTYPE_CHR end
		if path == "hex" then return fs.FTYPE_CHR end
		if path == "stdin" then return fs.FTYPE_CHR end
		if path == "stderr" then return fs.FTYPE_CHR end
		if path == "stdout" then return fs.FTYPE_CHR end
		if path == "stdterm" then return fs.FTYPE_CHR end
		for f in pairs(computeDeviceFiles()) do
			if path == f then return fs.FTYPE_BLK end
		end
		if string.startswith(path, "components/") then
			for addr in component.list() do
				if path == "components/" .. addr then
					return fs.FTYPE_BLK
				end
			end
		end
		return fs.FTYPE_NONE
	end
	if req == "FS-exists" then
		---@type unknown, string
		local _, path = ...
		if path == "" then return true end
		if path == "components" then return true end
		if path == "null" then return true end
		if path == "zero" then return true end
		if path == "random" then return true end
		if path == "hex" then return true end
		if path == "stdin" then return true end
		if path == "stderr" then return true end
		if path == "stdout" then return true end
		if path == "stdterm" then return true end
		for f in pairs(computeDeviceFiles()) do
			if path == f then return true end
		end
		return false
	end
end

Kocos.printk(Kocos.L_DEBUG, "devfs subsystem loaded")
Kocos.printk(Kocos.L_DEBUG, "adding devfs driver")

Kocos.addDriver(Kocos._default_devfs)

Kocos.printk(Kocos.L_DEBUG, "adding devfs component")

component.add {
	address = "devfs",
	type = "devfs",
	invoke = function() end,
	methods = {},
	slot = -1,
}
