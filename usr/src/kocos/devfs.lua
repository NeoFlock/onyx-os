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
		elseif type == "tunnel" then
			name = "tnl" .. devfsAddrSuffix(addr)
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

---@return string?
local function devfsPathToDev(path)
	if string.startswith(path, "components/") then
		for addr in component.list() do
			if path == "components/" .. addr then
				return addr
			end
		end
		return
	end
	for p, dev in pairs(computeDeviceFiles()) do
		if p == path then return dev end
	end
end

---@param dev string
---@param mode "r"|"a"|"w"
---@return Kocos.fs.FileDescriptor?, string?
local function devfsDevToFD(dev, mode)
	local t = component.type(dev)
	if t == "tunnel" then
		local s, err = Kocos.net.socket("AF_TUNNEL", "dgram")
		if not s then return nil, err end
		local ok, err2 = Kocos.net.connect(s, {address = dev, port = 0})
		if not ok then return nil, err2 end
		s.flags = 1
		---@type Kocos.fs.FileDescriptor
		return {
			flags = 1,
			write = function(_, data)
				if mode == "r" then return false, Kocos.errno.EBADF end
				return Kocos.net.write(s, data)
			end,
			read = function(_, len)
				if mode ~= "r" then return nil, Kocos.errno.EBADF end
				return Kocos.net.read(s, len)
			end,
			close = function()
				Kocos.net.close(s)
			end,
		}
	end
	if t == "serial" then
		---@type Kocos.fs.FileDescriptor
		return {
			flags = 1,
			write = function(_, data)
				if mode == "r" then return false, Kocos.errno.EBADF end
				return component.invoke(dev, "write", data)
			end,
			read = function(_, len)
				if mode ~= "r" then return nil, Kocos.errno.EBADF end
				return component.invoke(dev, "read", len)
			end,
		}
	end
	if t == "drive" or t == "partition" then
		if mode == "a" then
			return nil, "bad mode"
		end
		local d = component.proxy(dev)
		---@cast d Kocos.fs.partition
		local cursor = 0

		---@type Kocos.fs.FileDescriptor
		return {
			flags = 1,
			read = function(_, len)
				if mode ~= "r" then return nil, Kocos.errno.EBADF end
				local cap = d.getCapacity()
				if cursor >= cap then return end
				len = math.min(len, cap - cursor, 4*1024)
				local sectorSize = d.getSectorSize()
				local parts = {}
				local left = len
				while left > 0 do
					local off = cursor % sectorSize
					local sector = assert(d.readSector(1 + math.floor(cursor / sectorSize)))
					-- sub is expensive
					sector = sector:sub(1+off, len+off)
					table.insert(parts, sector)
					left = left - #sector
					cursor = cursor + #sector
				end
				cursor = math.clamp(cursor, 0, cap)
				return table.concat(parts)
			end,
			write = function(_, data)
				if mode == "r" then return false, Kocos.errno.EBADF end
				local cap = d.getCapacity()
				local sectorSize = d.getSectorSize()
				local left = math.min(#data, cap - cursor)
				while left > 0 do
					local written = 0
					if cursor % sectorSize == 0 and left >= sectorSize then
						-- best case scenario possible
						local sec = data:sub(1, sectorSize)
						d.writeSector(1 + cursor / sectorSize, sec)
						written = sectorSize
					else
						-- horrible scenario to be in
						local off = cursor % sectorSize
						local len = math.min(left, sectorSize)
						local secId = 1 + math.floor(cursor / sectorSize)
						local sec = assert(d.readSector(secId))
						sec = sec:sub(1, off) .. data:sub(1, len) .. sec:sub(1+off+len)
						d.writeSector(secId, sec)
						written = len
					end
					data = data:sub(1 + written)
					cursor = cursor + written
					left = left - written
				end
				cursor = math.clamp(cursor, 0, cap)
				return true
			end,
			seek = function(_, whence, off)
				local cap = d.getCapacity()
				if whence == "set" then
					cursor = off
				elseif whence == "cur" then
					cursor = cursor + off
				elseif whence == "end" then
					cursor = cap - off
				end
				cursor = math.clamp(cursor, 0, cap)
				return cursor
			end,
			ioctl = function(_, action, ...)
				if action == "devfs:address" then
					return dev
				end
				if action == "devfs:slot" then
					return component.slot(dev)
				end
				if action == "devfs:type" then
					return component.type(dev)
				end
				if action == "devfs:doc" then
					return component.doc(dev, ...)
				end
				return component.invoke(dev, action, ...)
			end,
		}
	end
	---@type Kocos.fs.FileDescriptor
	return {
		flags = 0,
		ioctl = function(_, method, ...)
				if method == "devfs:address" then
					return dev
				end
				if method == "devfs:slot" then
					return component.slot(dev)
				end
				if method == "devfs:type" then
					return component.type(dev)
				end
				if method == "devfs:doc" then
					return component.doc(dev, ...)
				end
			return component.invoke(dev, method, ...)
		end,
	}
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
			flags = 0,
		}
	end
	if path == "zero" then
		if mode ~= "r" then return nil, errno.EPERM end
		---@type Kocos.fs.FileDescriptor
		return {
			read = function(_, len)
				if len == math.huge then len = 4096 end
				return string.rep("\0", len)
			end,
			flags = 0,
		}
	end
	if path == "random" then
		if mode ~= "r" then return nil, errno.EPERM end
		---@type Kocos.fs.FileDescriptor
		return {
			read = function(_, len)
				if len == math.huge then len = 4096 end
				local c = ""
				for _=1,len do
					c = c .. string.char(math.random(0, 255))
				end
				return c
			end,
			flags = 0,
		}
	end
	if path == "hex" then
		if mode ~= "r" then return nil, errno.EPERM end
		---@type Kocos.fs.FileDescriptor
		return {
			read = function(_, len)
				if len == math.huge then len = 4096 end
				local c = ""
				local a = "0123456789ABCDEF"
				for _=1,len do
					local i = math.random(1, 16)
					c = c .. a:sub(i, i)
				end
				return c
			end,
			flags = 0,
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
			-- no finalizer cuz no
			-- flags are not shared. TODO: consider setting fd flags on use
			flags = 0,
		}
	end
	local dev = devfsPathToDev(path)
	if dev then
		return devfsDevToFD(dev, mode)
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
	if req == "FS-stat" then
		---@type unknown, string
		local _, path = ...
		local dev = devfsPathToDev(path)
		if dev then
			local ctype = component.type(dev)
			---@type integer
			local size = 0 -- TODO: make it correct
			local used = 0
			if ctype == "filesystem" then
				used = component.invoke(dev, "spaceUsed")
				size = component.invoke(dev, "spaceTotal")
			elseif ctype == "drive" or ctype == "partition" then
				size = component.invoke(dev, "getCapacity")
			end
			---@type Kocos.fs.stat
			return {
				deviceAddress = dev,
				deviceType = ctype,
				size = size,
				createdAt = 0,
				lastModified = 0,
				diskUsed = used,
				diskTotal = size,
				inode = math.random(0, 2^32-1),
				perms = 0,
			}
		end
		---@type Kocos.fs.stat
		return {
			deviceAddress = "devfs",
			deviceType = "devfs",
			size = 0,
			createdAt = 0,
			lastModified = 0,
			diskUsed = 0,
			diskTotal = 0,
			inode = math.random(0, 2^32-1),
			perms = 0,
		}
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
