-- DevFS module

local devfs = {}
devfs.addr = "devfs"
devfs.roPerms = 4*64
devfs.rwPerms = 6*64
devfs.dirPerms = 6*64 + 4*8 + 4

---@type table<string, {rc: integer, chunks: string[]}>
devfs.fdDataBuffers = {}

---@param address string
---@return boolean
function devfs.isDevReadOnly(address)
	local ty = component.type(address)
	if ty == "partition" then
		return (component.invoke(address, "getPartitionFlags") & Kocos.PART_READONLY) ~= 0
	elseif ty == "filesystem" then
		return component.invoke(address, "isReadOnly")
	end
	return false
end

---@param address string
---@return integer
function devfs.devSize(address)
	local ty = component.type(address)
	if ty == "drive" or ty == "partition" then
		return component.invoke(address, "getCapacity")
	elseif ty == "filesystem" then
		return component.invoke(address, "spaceTotal")
	elseif ty == "eeprom" then
		return component.invoke(address, "getSize")
	elseif ty == "gpu" then
		return component.invoke(address, "totalMemory")
	elseif ty == "data" then
		return component.invoke(address, "getLimit")
	elseif ty == "modem" then
		-- ocelot got rid of it?
		if component.methods(address).maxPacketSize == nil then
			return 0
		end
		return component.invoke(address, "maxPacketSize")
	elseif ty == "tunnel" then
		if component.methods(address).maxPacketSize == nil then
			return 0
		end
		return component.invoke(address, "maxPacketSize")
	end
	return 0
end

---@param address string
function devfs.isExternal(address)
	local s = component.slot(address)
	if not s then return false end
	return s < 0
end

---@param address string
---@return string?
function devfs.filenameFor(address)
	if address == computer.tmpAddress() then return "tmpfs" end
	local ty = component.type(address)
	local external = devfs.isExternal(address)
	local short = address:sub(1, 4)

	if ty == "filesystem" then
		local total = component.invoke(address, "spaceTotal")
		if total < 1*1024*1024 then return "fd-" .. short end
		if external then return "raid-" .. short end
		return "fs-" .. short
	end
	if ty == "drive" then
		local total = component.invoke(address, "getCapacity")
		if total < 1*1024*1024 then return "fd-" .. short end
		if external then return "uraid-" .. short end
		return "hdd-" .. short
	end
	if ty == "tape_drive" then
		return "tape-" .. short
	end
	if ty == "colorful_lamp" then
		return "lamp-" .. short
	end
	if ty == "partition" then
		local idx = component.invoke(address, "getPartitionIndex")
		local storage = component.invoke(address, "getStorageDevice")
		return (devfs.filenameFor(storage) or storage:sub(1, 4)) .. "p" .. idx
	end
	if ty == "note_block" then
		return "note-" .. short
	end
	if ty == "relay" or ty == "access_point" then
		return "relay-" .. short
	end
	if ty == "modem" then
		local wireless = component.invoke(address, "isWireless")
		return (wireless and "wlan-" or "lan-") .. short
	end
	if ty == "procfs" or ty == "devfs" then return end
	return ty .. "-" .. short
end

---@param address string
function devfs.statDev(address)
	---@type Kocos.fstat
	return {
		deviceAddress = address,
		linkCount = 1,
		type = "device",
		diskSize = 0,
		diskUsed = 0,
		diskTotal = 0,
		uid = 0,
		gid = 0,
		inode = -1,
		lastModified = 0,
		perms = devfs.isDevReadOnly(address) and devfs.roPerms or devfs.rwPerms,
		size = devfs.devSize(address),
	}
end

---@type Kocos.descriptorHandler
function devfs._blockDevHandler(handle, req, ...)
	---@type Kocos.blockdev
	local vdev = handle._vdev
	local ss = vdev.getSectorSize()
	local cap = vdev.getCapacity()
	local lastSec = cap / ss
	if req == "read" then
		if handle._sec > lastSec then return end
		local data, err = vdev.readSector(handle._sec)
		handle._sec = handle._sec + 1
		return data, err
	end
	if req == "write" then
		if handle._sec > lastSec then return false, Kocos.ENOSPC end
		---@type string
		local data = ...
		if #data % ss ~= 0 then return false, "misaligned" end
		local bc = #data / ss
		for i=1,bc do
			vdev.writeSector(handle._sec + i - 1, data)
		end
		handle._sec = handle._sec + bc
		return true
	end
	if req == "seek" then
		---@type seekwhence, integer
		local whence, off = ...
		local cur = (handle._sec - 1) * ss

		if whence == "set" then
			cur = off
		elseif whence == "cur" then
			cur = cur + off
		elseif whence == "end" then
			cur = cap - off
		end

		if cur % ss ~= 0 then
			return nil, "misaligned"
		end
		handle._sec = 1 + (cur / ss)
		return cur
	end
	if req == "ioctl" then
		local field = ...
		if field == "blocksize" then return ss end
	end
	return Kocos.defaultDevHandler(handle, req, ...)
end

---@type Kocos.descriptorHandler
function devfs._charDevHandler(handle, req, ...)
	---@type "null"|"zero"|"random"|"hex"
	local dev = assert(handle.device)
	if req == "read" then
		---@type integer
		local len = ...
		if len > 8192 then len = 8192 end
		if dev == "null" then return end
		if dev == "zero" then return string.rep('\0', len) end
		if dev == "hex" then
			local t = {}
			local alpha = "123456789abcdef"
			for i=1,len do
				local j = math.random(#alpha)
				t[i] = alpha:sub(j,j)
			end
			return table.concat(t)
		end
		if dev == "random" then
			local t = {}
			for i=1,len do
				t[i] = math.random(0, 255)
			end
			return string.char(table.unpack(t, 1, len))
		end
		return nil, Kocos.EBADF
	end
	if req == "write" then
		---@type string
		local data = ...
		if dev == "null" then return true end
		if dev == "zero" then return true end
		return nil, Kocos.EBADF
	end
end

---@type Kocos.descriptorHandler
function devfs._networkDevHandler(handle, req, ...)
	local dev = handle.device or ""
	local ty = component.type(dev)
	if req == "write" then
		---@type string
		local data = ...
		if ty == "modem" then
			local port = handle._modemport or 1
			if handle._modemtarget then
				return component.invoke(dev, "send", handle._modemtarget, port, data)
			else
				return component.invoke(dev, "broadcast", port, data)
			end
		elseif ty == "tunnel" then
			return component.invoke(dev, "send", data)
		end
		return false, Kocos.EBADDEV
	end
	if req == "ioctl" then
		local method, val = ...
		if method == "blocksize" then
			if component.methods(dev).maxPacketSize == nil then
				return 0
			end
			return component.invoke(dev, "maxPacketSize")
		end
		if ty == "modem" then
			if method == "setTarget" then
				handle._modemtarget = val
				return handle._modemtarget
			end
			if method == "getTarget" then
				return handle._modemtarget
			end
			if method == "targetport" then
				handle._modemport = tonumber(val) or 1
				return handle._modemport
			end
		end
	end
	if req == "read" then
		local buf = devfs.fdDataBuffers[dev]
		if not buf then return nil, Kocos.EBADF end
		return table.remove(buf.chunks, 1) or ""
	end
	if req == "close" then
		local buf = devfs.fdDataBuffers[dev]
		if not buf then return nil, Kocos.EBADF end
		buf.rc = buf.rc - 1
		if buf.rc < 1 then
			devfs.fdDataBuffers[dev] = nil
		end
		return true
	end
	return Kocos.defaultDevHandler(handle, req, ...)
end

---@param address string
function devfs.incDataBuffer(address)
	devfs.fdDataBuffers[address] = devfs.fdDataBuffers[address] or {
		rc = 0,
		chunks = {},
	}
	devfs.fdDataBuffers[address].rc = devfs.fdDataBuffers[address].rc + 1
end

---@param address string
---@param mode "r"|"w"|"a"
---@return Kocos.descriptor?, string?
function devfs.devHandle(address, mode)
	local dev, err = component.proxy(address)
	if not dev then return nil, err end
	if dev.type == "modem" or dev.type == "tunnel" then
		devfs.incDataBuffer(address)
		---@type Kocos.descriptor
		return {
			type = "device",
			state = "",
			flags = 0,
			pid = 0,
			rc = 1,
			handler = devfs._networkDevHandler,
			device = address,
		}
	end
	local vdrive = Kocos.virtualDriveFrom(dev)
	if vdrive then
		---@type Kocos.descriptor
		return {
			type = "device",
			state = "",
			flags = 0,
			pid = 0,
			rc = 1,
			handler = devfs._blockDevHandler,
			device = address,
			_vdev = vdrive,
			_sec = 1,
		}
	end
	return -- not handled
end

---@param req string
return function(req, ...)
	if req == "dkms_init" then
		component.add {
			address = devfs.addr,
			type = "devfs",
			invoke = function() end,
			methods = {},
			slot = -1,
		}
		return
	end
	if req == "dkms_close" then
		component.remove(devfs.addr)
		return
	end
	if req == "FS-mount" then
		local dev = ...
		if dev.address == devfs.addr then
			return "devfs"
		end
		return
	end
	if req == "FS-sync" then return true end
	if req == "FS-list" then
		---@type _, string
		local _, path = ...

		if path == "" then
			local t = {"primaries/", "components/", "null", "zero", "random", "hex"}
			for addr in component.list() do
				local n = devfs.filenameFor(addr)
				if n then table.insert(t, n) end
			end
			return t
		end
		if path == "components" then
			local t = {}
			for addr in component.list() do
				table.insert(t, addr)
			end
			return t
		end
		if path == "primaries" then
			local t = {}
			for _, ty in component.list() do
				local prim = assert(component.getPrimary(ty))
				t[ty] = prim.address
			end
			local f = {}
			for ty in pairs(t) do
				table.insert(f, ty)
			end
			return f
		end

		return nil, Kocos.ENOTDIR
	end
	if req == "FS-open" then
		---@type _, string
		local _, path = ...
		if path == "null" or path == "zero" or path == "random" or path == "hex" then
			---@type Kocos.descriptor
			return {
				type = "file",
				state = "",
				flags = 0,
				rc = 1,
				pid = 0,
				handler = devfs._charDevHandler,
				device = path,
			}
		end
		return nil, Kocos.EISDIR
	end
	if req == "FS-stat" then
		---@type _, string
		local _, path = ...
		if path == "" then
			---@type Kocos.fstat
			return {
				type = "directory",
				deviceAddress = devfs.addr,
				diskSize = 0,
				size = 0,
				diskUsed = 0,
				diskTotal = 0,
				uid = 0,
				gid = 0,
				inode = 0,
				lastModified = 0,
				perms = devfs.dirPerms,
				linkCount = 1,
			}
		end
		if path == "components" or path == "primaries" then
			---@type Kocos.fstat
			return {
				type = "directory",
				deviceAddress = devfs.addr,
				diskSize = 0,
				size = 0,
				diskUsed = 0,
				diskTotal = 0,
				uid = 0,
				gid = 0,
				inode = 0,
				lastModified = 0,
				perms = devfs.dirPerms,
				linkCount = 1,
			}
		end
		if path == "null" or path == "zero" or path == "random" or path == "hex" then
			---@type Kocos.fstat
			return {
				type = "regular",
				deviceAddress = devfs.addr,
				diskSize = 0,
				size = 0,
				diskUsed = 0,
				diskTotal = 0,
				uid = 0,
				gid = 0,
				inode = 0,
				lastModified = 0,
				perms = devfs.rwPerms,
				linkCount = 1,
			}
		end
		local primPref = "primaries/"
		if string.startswith(path, primPref) then
			local ty = string.sub(path, #primPref+1)
			local prim = component.getPrimary(ty)
			if prim then
				return devfs.statDev(prim.address)
			end
			return nil, Kocos.ENOENT
		end
		local compPref = "components/"
		if string.startswith(path, compPref) then
			local addr = string.sub(path, #compPref+1)
			if component.type(addr) then
				return devfs.statDev(addr)
			end
			return nil, Kocos.ENOENT
		end
		for addr in component.list() do
			if path == devfs.filenameFor(addr) then
				return devfs.statDev(addr)
			end
		end
		return nil, Kocos.ENOENT
	end
	if req == "EVENT" then
		local e = {...}
		if e[1] == "modem_message" then
			local recv = e[2]
			local buf = devfs.fdDataBuffers[recv]
			if not buf then return end
			local data = e[6]
			if type(data) == "string" then
				table.insert(buf.chunks, data)
			end
			return
		end
		return
	end
	if req == "FS-wrapdev" then
		local addr, mode = ...
		return devfs.devHandle(addr, mode)
	end
end
