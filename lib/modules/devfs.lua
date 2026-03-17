-- DevFS module

local devfs = {}
devfs.addr = "devfs"
devfs.roPerms = 4*64
devfs.rwPerms = 6*64
devfs.dirPerms = 6*64 + 4*8 + 4

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
	---@type Kocos.partdev
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
	return Kocos.defaultDevHandler(handle, req, ...)
end

---@param address string
---@param mode "r"|"w"|"a"
---@return Kocos.descriptor?, string?
function devfs.devHandle(address, mode)
	local dev, err = component.proxy(address)
	if not dev then return nil, err end
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
			local t = {"primaries/", "components/"}
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
	if req == "FS-wrapdev" then
		local addr, mode = ...
		return devfs.devHandle(addr, mode)
	end
end
