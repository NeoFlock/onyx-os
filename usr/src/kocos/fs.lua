-- Virtual filesystem.
-- Also handles the open/read/write/close/etc. syscalls

Kocos.P_EXECUTABLE = 1
Kocos.P_WRITABLE = 2
Kocos.P_READABLE = 4
Kocos.P_MASK = 7
Kocos.P_GROUPSHIFT = 3
Kocos.P_OWNERSHIFT = 6

Kocos.P_DEFAULT = 6*64 + 6*8 + 6
Kocos.P_ALL = 511
Kocos.P_NONE = 0

---@param permBits integer
---@param bit integer
---@param owned boolean
---@param grouped boolean
function Kocos.permCheck(permBits, bit, owned, grouped)
	if owned then
		permBits = permBits >> Kocos.P_OWNERSHIFT
	elseif grouped then
		permBits = permBits >> Kocos.P_GROUPSHIFT
	end
	permBits = permBits & Kocos.P_MASK
	-- Not ~= 0 so bit can be 0 for all
	return (permBits & bit) == bit
end

---@alias Kocos.dev table|{address: string, type: string, slot: integer}

---@class Kocos.blockdev
---@field address string
---@field type "drive"
---@field slot integer
---@field getCapacity fun(): integer
---@field getSectorSize fun(): integer
---@field getPlatterCount fun(): integer
---@field readSector fun(sector: integer): string
---@field writeSector fun(sector: integer, data: string)
---@field readByte fun(index: integer): integer
---@field writeByte fun(index: integer, byte: integer)

--- bldr - EFI partition, effectively where /boot lives
--- boot - Where the bootloader lives, effectively where to write /boot/init.lua too. Typically first 32KiB.
--- root - KOCOS Root partition, effectively /
--- data - Generic user partition, might be /home, /usr, or whatever the user wants
---@alias Kocos.parttype string|"boot"|"root"|"data"|"bldr"

Kocos.PART_READONLY = 1
Kocos.PART_HIDDEN = 2
Kocos.PART_PINNED = 4

---@class Kocos.partdev: Kocos.blockdev
---@field address string
---@field type "partition"
---@field slot integer
---@field getPartitionName fun(): string
---@field getStorageDevice fun(): string
---@field getPartitionFlags fun(): integer
---@field getPartitionType fun(): Kocos.parttype
---@field getSectorOffset fun(): integer

---@param dev Kocos.dev
---@param partitions string[]
function Kocos.retainpartof(dev, partitions)
	local allparts = {}
	for addr in component.list("partition", true) do
		---@type Kocos.partdev
		local part = component.proxy(addr)
		if part.getStorageDevice() == dev.address then
			table.insert(allparts, addr)
		end
	end
	for _, addr in ipairs(allparts) do
		if not table.contains(partitions, addr) then
			component.remove(addr)
		end
	end
end

---@param dev Kocos.dev
---@return string[]?, string?
function Kocos.getpartof(dev)
	if dev.type == "partition" then return nil, Kocos.EBADDEV end
	---@type string[]?, string?
	local l, err
	for _, mod in pairs(Kocos.mods) do
		l, err = mod("FS-partition", dev)
		if err then return nil, err end
		if l then break end
	end
	if l then
		-- automatically drop old partitions
		Kocos.retainpartof(dev, l)
		return l
	end
	return nil, Kocos.ENODRIVER
end

-- Makes a block partition
-- If the component already exists, it'll do nothing
---@param address string
---@param drive Kocos.blockdev
---@param name string
---@param sectorOff integer Starts at 0
---@param size integer In sectors
---@param partType string
---@param partFlags integer
---@return string?
function Kocos.addDrivePartition(address, drive, name, sectorOff, size, partType, partFlags)
	if component.type(address) then return address end
	return component.add {
		address = address,
		type = "partition",
		slot = drive.slot,
		methods = {
			getCapacity = {
				direct = true,
				doc = "function(): integer - Returns the partition size.",
			},
			getSectorSize = {
				direct = true,
				doc = "function(): integer - Returns the sector size of the partition.",
			},
			getPlatterCount = {
				direct = true,
				doc = "function(): integer - Returns the platter count of the device the partition lives on.",
			},
			readSector = {
				direct = true,
			},
			writeSector = {
				direct = true,
			},
			readByte = {
				direct = true,
			},
			writeByte = {
				direct = true,
			},
			getPartitionName = {
				direct = true,
			},
			getStorageDevice = {
				direct = true,
			},
			getPartitionFlags = {
				direct = true,
			},
			getPartitionType = {
				direct = true,
			},
			getSectorOffset = {
				direct = true,
			},
		},
		invoke = function(method, ...)
			if method == "getCapacity" then return size * drive.getSectorSize() end
			if method == "getSectorSize" then return drive.getSectorSize() end
			if method == "getPlatterCount" then return drive.getPlatterCount() end
			if method == "readSector" then
				local sec = ...
				return drive.readSector(sec + sectorOff)
			end
			if method == "writeSector" then
				if readOnly then return nil, "read-only partition" end
				local sec, data = ...
				return drive.writeSector(sec + sectorOff, data)
			end
			if method == "readByte" then
				local idx = ...
				return drive.readSector(idx + sectorOff * drive.getSectorSize())
			end
			if method == "writeByte" then
				if readOnly then return nil, "read-only partition" end
				local idx, data = ...
				return drive.writeSector(idx + sectorOff * drive.getSectorSize(), data)
			end
			if method == "getPartitionName" then
				return name
			end
			if method == "getStorageDevice" then
				return drive.address
			end
			if method == "getPartitionFlags" then
				return partFlags
			end
			if method == "getPartitionType" then
				return partType
			end
			if method == "getSectorOffset" then
				return sectorOff
			end
			return nil, "no such method"
		end,
	}
end

function Kocos.refetchPartitions()
	for dev in component.list() do
		local p = component.proxy(dev)
		if p and p.type ~= "partition" then Kocos.getpartof(p) end
	end
end

---@param path string
---@return string parent, string? child
function Kocos.parentOf(path)
	path = Kocos.canonicalPath(path)
	local parts = string.split(path, "/")
	local name = table.remove(parts, #parts)

	local parents = Kocos.canonicalPath(table.concat(parts, "/"))
	return parents, name
end

---@class Kocos.mountState
---@field device string
---@field driver? Kocos.module
---@field state any
---@field cmdline string

--- The keys are the paths without the leading /
---@type table<string, Kocos.mountState>
Kocos.mounts = {}

---@alias Kocos.vfifostate {reader: Kocos.descriptor, writer: Kocos.descriptor, buf: string}

---@alias Kocos.vfilestate Kocos.vfifostate|Kocos.descriptor

---@type table<string, Kocos.vfilestate>
Kocos.volatileFileStates = {}

---@param path string
---@return string
function Kocos.canonicalPath(path)
	local parts = string.split(path, "/")
	local newparts = {}

	for _, part in ipairs(parts) do
		if #part > 0 then
			table.insert(newparts, part)
			if part == string.rep(".", #part) then
				for _=1,#part do table.remove(newparts, #newparts) end
			end
		end
	end

	return "/" .. table.concat(newparts, "/")
end

---@vararg string
---@return string
function Kocos.joinPath(...)
	return Kocos.canonicalPath(table.concat({...}, "/"))
end

---@param proc Kocos.vmproc
---@param path string
function Kocos.realPathFor(proc, path)
	if path:sub(1, 1) == "/" then
		return Kocos.joinPath(proc.root, path)
	end
	return Kocos.joinPath(proc.root, proc.cwd, path)
end

---@alias Kocos.filetype "regular"|"directory"|"symlink"|"fifo"|"device"

---@param ftype Kocos.filetype
function Kocos.validFileType(ftype)
	return ftype == "regular" or ftype == "directory" or ftype == "symlink" or ftype == "fifo"
end

---@class Kocos.fstat
---@field deviceAddress string
---@field inode integer
---@field size integer
---@field diskSize integer
---@field type Kocos.filetype
---@field perms integer
---@field uid integer
---@field gid integer
---@field lastModified integer
---@field diskUsed integer
---@field diskTotal integer
---@field linkCount integer

--- Only resolves direct mount
---@return Kocos.mountState, string
function Kocos.resolveMount(path, keepLink)
	path = Kocos.canonicalPath(path):sub(2)
	local mount, subpath = Kocos.mounts[""], path
	local bestScore = 0

	for mpath, m in pairs(Kocos.mounts) do
		if #mpath > bestScore then
			if mpath == path and not keepLink then
				return m, ""
			elseif string.startswith(path, mpath .. "/") then
				bestScore = #mpath
				mount = m
				subpath = path:sub(#mpath + 2)
			end
		end
	end

	return mount, subpath
end

---@param mount Kocos.mountState
---@param path string
---@return Kocos.fstat?, string?
function Kocos.statMount(mount, path)
	if not mount.driver then return nil, Kocos.ENODRIVER end
	return mount.driver("FS-stat", mount.state, path)
end

---@param mount Kocos.mountState
---@param path string
---@return boolean
function Kocos.existsOnMount(mount, path)
	local s, err = Kocos.statMount(mount, path)
	return (s ~= nil) or (err ~= Kocos.ENOENT)
end

---@param path string
---@param uid integer
---@param gid integer
---@param permbit integer
---@param keepLink boolean
---@param keepMissing boolean
---@return Kocos.mountState?, string
function Kocos.resolvePath(path, uid, gid, permbit, keepLink, keepMissing)
	path = Kocos.canonicalPath(path)
	local checkPerms = Kocos.getCmdlineBool("FS_RECURSIVEPERM", true)
	local maxLinkCount = Kocos.getCmdlineNum("FS_MAXLINK", 4)
	local linkCount = 0

	local root = Kocos.mounts[""]
	if not root then return nil, Kocos.ENOENT end

	if path == "/" then return root, "" end

	while true do
		if linkCount > maxLinkCount then return nil, Kocos.ELOOP end
		local mount, subpath = Kocos.resolveMount(path, keepLink)

		-- Scan for symlink or violations
		local parts = string.split(subpath, "/")
		local looped = false
		for idx=1, #parts do
			local checkpath = table.concat(parts, "/", 1, idx)
			local stat, err = Kocos.statMount(mount, checkpath)
			if not stat then
				if err == Kocos.ENOENT and keepMissing and idx == #parts then
					return mount, subpath
				end
				return nil, err or Kocos.ENODRIVER
			end
			if idx == #parts or checkPerms then
				if not Kocos.permCheck(stat.perms, permbit, stat.uid == uid, stat.gid == gid) then
					return nil, Kocos.EACCESS
				end
			end
			if stat.type == "symlink" and (idx < #parts or not keepLink) then
				local linkpath, err = mount.driver("FS-readlink", mount.state, checkpath)
				if not linkpath then return nil, err end
				looped = true
				linkCount = linkCount + 1
				path = linkpath
				break
			elseif stat.type ~= "directory" and idx < #parts then
				return nil, Kocos.ENOTDIR
			end
		end
		if not looped then return mount, subpath end
	end
end

---@param device string
function Kocos.isMounted(device)
	for _, s in pairs(Kocos.mounts) do
		if s.device == device then return true end
	end
	return false
end

---@param device Kocos.dev
---@return Kocos.blockdev?, string
--- Will attempt to turn the device into either a drive or partition component
function Kocos.virtualDriveFrom(device)
	if device.type == "drive" then
		---@cast device Kocos.blockdev
		return device, ""
	end
	if device.type == "partition" then
		---@cast device Kocos.partdev
		return device, ""
	end
	for k, mod in pairs(Kocos.mods) do
		local vdev, err = mod("FS-vdrive", device)
		if vdev or err then
			return vdev, err
		end
	end
	return nil, Kocos.ENODRIVER
end

---@param dev Kocos.dev
---@param cmdline? string
---@return Kocos.mountState?, string
function Kocos.mountFor(dev, cmdline)
	cmdline = cmdline or ""
	for _, s in pairs(Kocos.mounts) do
		if s.device == dev.address then return s, "" end
	end

	for _, mod in pairs(Kocos.mods) do
		local state, err = mod("FS-mount", dev, cmdline)
		if state or err then
			if err then return nil, err end
			---@type Kocos.mountState
			local m = {
				device = dev.address,
				state = state,
				driver = mod,
				cmdline = cmdline,
			}
			return m, err
		end
	end

	return nil, Kocos.ENODRIVER
end

---@param path string
function Kocos.removeMount(path)
	path = Kocos.canonicalPath(path):sub(2)
	local mnt = Kocos.mounts[path]
	assert(mnt, Kocos.ENODEV)
	Kocos.mounts[path] = nil
	if mnt.driver then mnt.driver("FS-umount", mnt.state) end
end

---@param req "dkms_added"|"dkms_removed"
---@param mod string
---@param driver Kocos.module
function Kocos._fsModListener(req, mod, driver)
	if req == "dkms_removed" then
		for p, mnt in pairs(Kocos.mounts) do
			if mnt.driver == driver then
				Kocos.printkf(Kocos.L_DEBUG, "Module %q for /%s removed, mountpoint is in dead state", mod, p)
				mnt.driver = nil
			end
		end
		return
	end
	if req == "dkms_added" then
		for p, mnt in pairs(Kocos.mounts) do
			if not mnt.driver then
				local dev = component.proxy(mnt.device)
				local state, err = driver("FS-mount", dev, mnt.cmdline, mnt.state)
				if state or err then
					if err then
						Kocos.printkf(Kocos.L_WARN, "Module %q failed to recover /%s", mod, p)
						return nil, err
					end
					Kocos.printkf(Kocos.L_DEBUG, "Module %q successfully recovered /%s", mod, p)
					mnt.state = state
					mnt.driver = driver
				end
			end
		end
		return
	end
end

Kocos.listen(Kocos._fsModListener)

Kocos.printk(Kocos.L_INFO, "loaded managedfs")

Kocos.loadModuleCode("managedfs", _EMBED_MIN("lib/modules/managedfs.lua"))

do
	Kocos.printk(Kocos.L_INFO, "mounting /")
	local dev = Kocos.getCmdlineStr("ROOT", computer.getBootAddress())

	if Kocos.ramfs then
		Kocos.mounts[""] = assert(Kocos.ramfsFor(Kocos.ramfs))
		-- to no longer retain it, let the GC free it
		Kocos.ramfs = nil
		Kocos.printk(Kocos.L_INFO, "mounted / as ramfs")
	elseif component.type(dev) == "filesystem" then
		-- ultra free
		Kocos.mounts[""] = assert(Kocos.mountFor(component.proxy(dev)))
		Kocos.printk(Kocos.L_INFO, "mounted / as managedfs")
	else
		Kocos.panick("Unsupported root. Please provide a ramfs instead")
	end
end

---@type Kocos.descriptorHandler
function Kocos._fifoHandler(h, req, ...)
	---@type Kocos.vfifostate
	local state = Kocos.volatileFileStates[h._fifopath]
	local isNonBlocking = (h.flags & Kocos.O_NONBLOCK) ~= 0

	if req == "read" then
		while #state.buf == "" and not isNonBlocking do
			-- we wait for more data
			Kocos.sysyield()
		end
		---@type integer
		local len = ...
		if len > #state.buf then len = #state.buf end
		local chunk = state.buf:sub(1, len)
		state.buf = state.buf:sub(len+1)
		return chunk
	end
	if req == "write" then
		---@type string
		local data = ...
		state.buf = state.buf .. data
		return true
	end
	-- no one cares
	if req == "close" then return true end

	return nil, Kocos.EBADF
end

---@type Kocos.descriptorHandler
function Kocos._romFileHandler(desc, req, ...)
	---@type string
	local data = desc._data
	if req == "read" then
		---@type integer
		local len = ...
		if len > #data then len = #data end
		len = math.floor(len)

		if desc._pos >= #data then return end

		local chunk = data:sub(desc._pos + 1, desc._pos + len)
		desc._pos = desc._pos + #chunk
		return chunk
	end
	if req == "seek" then
		---@type "set"|"cur"|"end", integer
		local whence, off = ...

		if whence == "set" then
			data._pos = off
		elseif whence == "cur" then
			data._pos = data._pos + off
		elseif whence == "end" then
			desc._pos = #data - off
		end
		desc._pos = math.clamp(desc._pos, 0, #data)
		return desc._pos
	end
	if req == "close" then return true end
	return nil, Kocos.EBADF
end

---@param type Kocos.descriptorType
---@param data string
function Kocos.romFile(type, data)
	---@type Kocos.descriptor
	return {
		type = type,
		state = "",
		pid = 0,
		flags = 0,
		rc = 1,
		handler = Kocos._romFileHandler,
		_pos = 0,
		_data = data,
	}
end

---@param path string
---@param mode "r"|"w"|"a"
---@return integer?, string?
function syscalls.open(path, mode)
	if type(path) ~= "string" then return nil, Kocos.EINVAL end
	if type(mode) ~= "string" then return nil, Kocos.EINVAL end
	if mode ~= "r" and mode ~= "w" and mode ~= "a" then return nil, Kocos.EINVAL end
	local proc = Kocos.currentProcess()
	local availableFd = Kocos.availableDescriptorFor(proc)

	local truepath = Kocos.realPathFor(proc, path)
	local mnt, subpath = Kocos.resolvePath(truepath, proc.uid, proc.gid, mode == "r" and Kocos.P_READABLE or Kocos.P_WRITABLE, false, false)
	if not mnt then return nil, subpath end

	local stat, err = Kocos.statMount(mnt, subpath)
	if not stat then return nil, err end

	if stat.type == "directory" then
		return nil, Kocos.EISDIR
	elseif stat.type == "regular" then
		-- Filesystem shi
		---@type Kocos.descriptor?, string?
		local handle, err = mnt.driver("FS-open", mnt.state, subpath, mode)
		if not handle then return nil, err or Kocos.EHWPOISON end
		-- prevents buggy behavior
		setmetatable(handle, nil)
		proc.fds[availableFd] = handle
		return availableFd
	elseif stat.type == "fifo" then
		local state = Kocos.volatileFileStates[truepath]
		---@cast state Kocos.vfifostate

		if state then
			local h = mode == "r" and state.reader or state.writer
			h.rc = h.rc + 1
			proc.fds[availableFd] = h
			return availableFd
		end

		state = {
			buf = "",
			reader = {
				rc = 1,
				state = "reader",
				type = "pipe",
				flags = 0,
				handler = Kocos._fifoHandler,
				_fifopath = truepath,
				pid = 0,
			},
			writer = {
				rc = 1,
				state = "writer",
				type = "pipe",
				flags = 0,
				handler = Kocos._fifoHandler,
				_fifopath = truepath,
				pid = 0,
			},
		}
		Kocos.volatileFileStates[truepath] = state

		proc.fds[availableFd] = mode == "r" and state.reader or state.writer
		return availableFd
	end
	return nil, Kocos.EHWPOISON
end

---@param fd integer
---@return boolean, string?
function syscalls.close(fd)
	if type(fd) ~= "number" then return false, Kocos.EINVAL end
	local proc = Kocos.currentProcess()
	local f = proc.fds[fd]
	if not f then return false, Kocos.EBADF end
	Kocos.closeDescriptor(f)
	proc.fds[fd] = nil
	return true
end

---@param fd integer
---@param data string
---@return boolean, string?
function syscalls.write(fd, data)
	if type(fd) ~= "number" then return false, Kocos.EINVAL end
	if type(data) ~= "string" then return false, Kocos.EINVAL end

	local proc = Kocos.currentProcess()
	local f = proc.fds[fd]
	if not f then return false, Kocos.EBADF end
	return Kocos.handleDescriptorRequest(f, "write", data)
end

---@param fd integer
---@param len integer
---@return string?, string?
function syscalls.read(fd, len)
	if type(fd) ~= "number" then return nil, Kocos.EINVAL end
	if type(len) ~= "number" then return nil, Kocos.EINVAL end
	local proc = Kocos.currentProcess()
	local f = proc.fds[fd]
	if not f then return nil, Kocos.EBADF end
	return Kocos.handleDescriptorRequest(f, "read", len)
end

---@param fd integer
---@param whence? "set"|"cur"|"end"
---@param off? integer
---@return integer?, string?
function syscalls.seek(fd, whence, off)
	whence = whence or "cur"
	off = off or 0
	if type(fd) ~= "number" then return nil, Kocos.EINVAL end
	if type(whence) ~= "string" then return nil, Kocos.EINVAL end
	if type(off) ~= "number" then return nil, Kocos.EINVAL end

	if whence ~= "set" and whence ~= "cur" and whence ~= "end" then
		return nil, Kocos.EINVAL
	end

	local proc = Kocos.currentProcess()
	local f = proc.fds[fd]
	if not f then return nil, Kocos.EBADF end
	return Kocos.handleDescriptorRequest(f, "seek", whence, off)
end

---@param fd integer
---@param action string
---@return boolean, string?
function syscalls.ioctl(fd, action, ...)
	if type(fd) ~= "number" then return false, Kocos.EINVAL end
	if type(action) ~= "string" then return false, Kocos.EINVAL end

	local proc = Kocos.currentProcess()
	local f = proc.fds[fd]
	if not f then return false, Kocos.EBADF end
	return Kocos.handleDescriptorRequest(f, "ioctl", action, ...)
end

---@param path string
---@return string[]?, string?
function syscalls.list(path)
	if type(path) ~= "string" then return nil, Kocos.EINVAL end

	local proc = Kocos.currentProcess()
	local mnt, subpath = Kocos.resolvePath(Kocos.realPathFor(proc, path), proc.uid, proc.gid, Kocos.P_READABLE, false, false)
	if not mnt then return nil, subpath end

	local stat, err = Kocos.statMount(mnt, subpath)
	if not stat then return nil, err end

	if stat.type ~= "directory" then return nil, Kocos.ENOTDIR end

	return mnt.driver("FS-list", mnt.state, subpath)
end

---@param path string
---@param keepLink? boolean
---@return Kocos.fstat?, string?
function syscalls.stat(path, keepLink)
	if type(path) ~= "string" then return nil, Kocos.EINVAL end
	keepLink = keepLink or false
	if type(keepLink) ~= "boolean" then return nil, Kocos.EINVAL end

	local proc = Kocos.currentProcess()
	local mnt, subpath = Kocos.resolvePath(Kocos.realPathFor(proc, path), proc.uid, proc.gid, 0, keepLink, false)
	if not mnt then return nil, subpath end

	return Kocos.statMount(mnt, subpath)
end

---@param path string
---@return Kocos.filetype?, string?
function syscalls.ftype(path)
	local stat, err = syscalls.stat(path, true)
	if not stat then return nil, err end
	return stat.type
end

---@param path string
---@return Kocos.fstat?, string?
function syscalls.lstat(path)
	return syscalls.stat(path, true)
end

---@param path string
---@param traverse? boolean
---@return boolean, string?
function syscalls.exists(path, traverse)
	if type(path) ~= "string" then return false, Kocos.EINVAL end
	local proc = Kocos.currentProcess()
	local mnt, subpath = Kocos.resolvePath(Kocos.realPathFor(proc, path), proc.uid, proc.gid, Kocos.P_READABLE, not traverse, false)
	return (mnt ~= nil and subpath ~= Kocos.ENOENT)
end

---@param path string
---@param ftype? Kocos.filetype
---@param perms? integer
---@param uid? integer
---@param gid? integer
---@return boolean, string?
function syscalls.mknod(path, ftype, perms, uid, gid)
	local proc = Kocos.currentProcess()
	ftype = ftype or "regular"
	perms = perms or Kocos.P_DEFAULT
	uid = uid or proc.uid
	gid = gid or proc.gid
	if type(path) ~= "string" then return false, Kocos.EINVAL end
	if type(ftype) ~= "string" then return false, Kocos.EINVAL end
	if not Kocos.validFileType(ftype) then return false, Kocos.EINVAL end
	if type(perms) ~= "number" then return false, Kocos.EINVAL end
	if type(uid) ~= "number" then return false, Kocos.EINVAL end
	if type(gid) ~= "number" then return false, Kocos.EINVAL end
	perms = math.floor(perms) % 512
	uid = math.floor(uid)
	gid = math.floor(gid)
	local truepath = Kocos.realPathFor(proc, path)
	local mnt, subpath = Kocos.resolvePath(truepath, proc.uid, proc.gid, Kocos.P_WRITABLE, false, true)
	if not mnt then return false, subpath end
	if Kocos.existsOnMount(mnt, subpath) then return false, Kocos.EEXIST end
	return mnt.driver("FS-mknod", mnt.state, subpath, ftype, perms, uid, gid)
end

---@param path string
---@param uid integer
---@param gid integer
function syscalls.chown(path, uid, gid)
	local proc = Kocos.currentProcess()
	local truepath = Kocos.realPathFor(proc, path)
	local mnt, subpath = Kocos.resolvePath(truepath, proc.uid, proc.gid, Kocos.P_WRITABLE, false, false)
	if not mnt then return false, subpath end
	return mnt.driver("FS-chown", mnt.state, subpath, uid, gid)
end

---@param path string
---@param perms integer
function syscalls.chmod(path, perms)
	local proc = Kocos.currentProcess()
	local truepath = Kocos.realPathFor(proc, path)
	local mnt, subpath = Kocos.resolvePath(truepath, proc.uid, proc.gid, Kocos.P_WRITABLE, false, false)
	if not mnt then return false, subpath end
	return mnt.driver("FS-chnod", mnt.state, subpath, perms)
end

---@param path string
---@return boolean, string?
function syscalls.remove(path)
	local proc = Kocos.currentProcess()
	local truepath = Kocos.realPathFor(proc, path)
	local mnt, subpath = Kocos.resolvePath(truepath, proc.uid, proc.gid, Kocos.P_WRITABLE, false, false)
	if not mnt then return false, subpath end
	local stat = assert(Kocos.statMount(mnt, subpath))
	if stat.type == "directory" then
		-- don't call list() because that stats a lot
		local l, err = mnt.driver("FS-list", mnt.state, subpath)
		if err then return false, err end
		if #l > 0 then return false, Kocos.ENOTEMPTY end
	end
	return mnt.driver("FS-remove", mnt.state, subpath)
end

---@param path string
---@param mtime? integer
---@return boolean, string?
function syscalls.touch(path, mtime)
	if type(path) ~= "string" then return false, Kocos.EINVAL end
	if type(mtime) ~= "number" and type(mtime) ~= "nil" then return false, Kocos.EINVAL end

	local proc = Kocos.currentProcess()

	local truepath = Kocos.realPathFor(proc, path)
	local mnt, subpath = Kocos.resolvePath(truepath, proc.uid, proc.gid, Kocos.P_WRITABLE, false, false)
	if not mnt then return false, subpath end
	return mnt.driver("FS-touch", mnt.state, subpath, mtime)
end

---@param dev? string
---@return integer?, string?
function syscalls.sync(dev)
	Kocos.refetchPartitions()
	local synced = 0
	for _, mnt in pairs(Kocos.mounts) do
		if mnt.device == (dev or mnt.device) and mnt.driver then
			local ok, err = mnt.driver("FS-sync", mnt.state)
			if not ok then return nil, err end
			synced = synced + 1
		end
	end
	return synced
end

---@param dev? string
---@return integer?, string?
function syscalls.flush(dev)
	local flushed = 0
	for _, mnt in pairs(Kocos.mounts) do
		if mnt.device == (dev or mnt.device) and mnt.driver then
			local ok, err = mnt.driver("FS-flush", mnt.state)
			if not ok then return nil, err end
			flushed = flushed + 1
		end
	end
	return flushed
end


---@param dev? string
---@return string[]?, string?
function syscalls.partitionsof(dev)
	local proxy = component.proxy(dev)
	if not proxy then return nil, Kocos.ENODEV end
	return Kocos.getpartof(proxy)
end

syscalls.canonical = Kocos.canonicalPath
syscalls.parentPath = Kocos.parentOf

---@param first string
---@vararg string
---@return string
function syscalls.join(first, ...)
	if first:sub(1, 1) == "/" then
		return Kocos.joinPath(first, ...)
	end
	return Kocos.joinPath(Kocos.currentProcess().cwd, first, ...)
end

---@param fd integer
---@return boolean, string?
function syscalls.isatty(fd)
	local proc = Kocos.currentProcess()
	local h = proc.fds[fd]
	if not h then return false, Kocos.EINVAL end
	return h.type == "tty"
end

---@type Kocos.descriptorHandler
function Kocos._ttyHandler(h, req, ...)
	local proc = Kocos.processes[h.pid]
	if not proc then return nil, Kocos.ESRCH end
	local t = Kocos.procCall(proc, h._ttyhandler, req, ...)
	if t[1] then
		return table.unpack(t, 2)
	else
		return nil, t[2]
	end
end

---@type Kocos.descriptorHandler
function Kocos._timerHandler(h, req, ...)
	if req == "close" then
		Kocos.cancelTimer(h._timer)
		return true
	end
	return nil, Kocos.EBADF
end

---@param handler fun(req: Kocos.descriptorReq, ...): ...
function syscalls.opentty(handler, flags)
	local proc = Kocos.currentProcess()
	flags = flags or 0
	if type(handler) ~= "function" then return nil, Kocos.EINVAL end
	if type(flags) ~= "number" then return nil, Kocos.EINVAL end
	flags = math.floor(flags)

	---@type Kocos.descriptor
	local desc = {
		type = "tty",
		state = "",
		flags = flags,
		pid = proc.pid,
		rc = 1,
		_ttyhandler = handler,
		handler = Kocos._ttyHandler,
	}
	local avail = Kocos.availableDescriptorFor(proc)
	proc.fds[avail] = desc
	return avail
end

---@param interval number
---@param func function
---@param times integer
function syscalls.mktimer(interval, func, times)
	local proc = Kocos.currentProcess()
	if type(interval) ~= "number" then return nil, Kocos.EINVAL end
	if type(func) ~= "function" then return nil, Kocos.EINVAL end
	if type(times) ~= "number" then return nil, Kocos.EINVAL end

	local timer = Kocos.timer(interval, function()
		Kocos.procCall(proc, func)
	end, times)

	---@type Kocos.descriptor
	local desc = {
		type = "timer",
		state = "",
		flags = 0,
		pid = proc.pid,
		rc = 1,
		_timer = timer,
		handler = Kocos._timerHandler,
	}
	local avail = Kocos.availableDescriptorFor(proc)
	proc.fds[avail] = desc
	return avail
end

---@param fd integer
---@return integer?, string?
function syscalls.dup(fd)
	local proc = Kocos.currentProcess()
	local h = proc.fds[fd]
	if not h then return nil, Kocos.EBADF end
	local availFd = Kocos.availableDescriptorFor(proc)
	proc.fds[availFd] = h
	h.rc = h.rc + 1
	return availFd
end

---@return boolean, string?
function syscalls.dup2(fd, newFd)
	local proc = Kocos.currentProcess()
	if proc.fds[newFd] then return false, Kocos.EEXIST end
	local h = proc.fds[fd]
	if not h then return false, Kocos.EBADF end
	proc.fds[newFd] = h
	h.rc = h.rc + 1
	return true
end

---@param path string
---@return string?, string?
function syscalls.chdir(path)
	if type(path) ~= "string" then return nil, Kocos.EINVAL end
	local proc = Kocos.currentProcess()
	if path:sub(1, 1) ~= "/" then
		path = Kocos.joinPath(proc.cwd, path)
	end
	path = Kocos.canonicalPath(path)
	local stat, err = syscalls.stat(path)
	if not stat then return nil, err end
	if stat.type ~= "directory" then return nil, err end
	proc.cwd = path
	return proc.cwd
end

---@return table<string, string>
function syscalls.getMounts()
	local mnt = {}
	for p, state in pairs(Kocos.mounts) do
		mnt[state.device] = "/" .. p
	end
	return mnt
end

---@param path string
function syscalls.isMount(path)
	local proc = Kocos.currentProcess()
	local mntpath = Kocos.realPathFor(proc, path):sub(2)
	return Kocos.mounts[mntpath] ~= nil
end

---@param path string
---@param device string
---@param cmdline? string
---@return boolean, string?
function syscalls.mount(path, device, cmdline)
	if Kocos.isMounted(device) then
		return false, Kocos.EADDRINUSE
	end
	local proxy = component.proxy(device)
	if not proxy then
		return false, Kocos.ENODEV
	end

	if Kocos.mounts[""] then
		local list, err = syscalls.list(path)
		if not list then return false, err end
		if #list > 0 then return false, Kocos.ENOTEMPTY end
	end

	local proc = Kocos.currentProcess()
	local mntpath = Kocos.realPathFor(proc, path):sub(2)
	if Kocos.mounts[mntpath] then
		return false, Kocos.EISMNT
	end

	local state, err = Kocos.mountFor(proxy, cmdline)
	if not state then return false, err end

	Kocos.mounts[mntpath] = state
	return true
end

---@param path string
---@return boolean, string?
function syscalls.umount(path)
	local proc = Kocos.currentProcess()
	local mntpath = Kocos.realPathFor(proc, path):sub(2)
	if not Kocos.mounts[mntpath] then
		return false, Kocos.ENOENT
	end

	Kocos.removeMount(mntpath)
	return true
end

---@return boolean, string?
function writefile(filename, data)
	local f, err = syscall("open", filename, "w")
	if not f then return false, err end

	local ok, err = syscall("write", f, data)
	syscall("close", f)
	return ok, err
end

---@return string?, string?
function readfile(filename, bufsize)
	local f, err = syscall("open", filename, "r")
	if not f then return nil, err end

	local data = ""
	while true do
		local chunk, err = syscall("read", f, bufsize or math.huge)
		if err then
			syscall("close", f)
			return nil, err
		end
		if not chunk then break end
		data = data .. chunk
	end

	syscall("close", f)
	return data
end

---@return function?, string?
function loadfile(filename, mode, env)
	local data, err = readfile(filename)
	if not data then return nil, err end
	if data:sub(1, 2) == "#!" then
		local term = string.find(data, "\n", 3) or 1
		data = data:sub(term)
	end
	return load(data, "=" .. filename, mode, env)
end

function dofile(filename, ...)
	return assert(loadfile(filename))(...)
end

---@param modname string
---@param uncached? boolean
---@param env? _G
---@return any, string
function require(modname, uncached, env)
	local proc = Kocos.currentProcess()
	env = env or proc.namespace

	if env.package.loaded[modname] ~= nil and not uncached then
		return env.package.loaded[modname], ':loaded:'
	end

	local mod = proc.modules[modname]
	if mod then
		local f = assert(load(mod.data, "=" .. mod.src))
		local v = f(modname)
		if v == nil then v = true end
		if not uncached then env.package.loaded[modname] = v end
		return v, ':module:'
	end

	if env.package.preload[modname] then
		local v = env.package.preload[modname](modname)
		if v == nil then v = true end
		if not uncached then env.package.loaded[modname] = v end
		return v, ':preload:'
	end

	local luaCode = package.searchpath(modname, proc.env["LUA_PATH"] or env.package.path)

	if luaCode then
		--if not uncached then env.package.loaded[modname] = true end
		local v = dofile(luaCode, modname, uncached)
		if v == nil then v = true end
		if not uncached then env.package.loaded[modname] = v end
		return v, luaCode
	end

	error("could not find module: " .. modname, 2)
end
