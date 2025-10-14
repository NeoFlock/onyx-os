local fs = {}

---@alias Kocos.fs.partitionType "root"|"boot"|"user"
---@alias Kocos.fs.ftype "none"|"regular"|"directory"|"mount"|"blockdev"|"chardev"

fs.FTYPE_NONE = "none"
fs.FTYPE_REGF = "regular"
fs.FTYPE_DIR = "directory"
fs.FTYPE_MNT = "mount"
fs.FTYPE_BLK = "blockdev"
fs.FTYPE_CHR = "chardev"

---@class Kocos.fs.vdrive
---@field address string
---@field type string
---@field getSectorSize fun(): integer
---@field getPlatterCount fun(): integer
---@field getCapacity fun(): integer
---@field readSector fun(index: integer): string
---@field writeSector fun(index: integer, data: string)
--- readByte/writeByte considered harmful, evil and stinky

---@class Kocos.fs.stat
---@field deviceAddress string
---@field deviceType string
---@field inode integer
---@field size integer
---@field lastModified integer
---@field createdAt integer
---@field diskUsed integer
---@field diskTotal integer
--- Currently unused
---@field perms integer
--- Symlinks are not currently supported
---@field linkPath? string

fs.O_NONBLOCK = 1
fs.O_CLOEXEC = 2

fs.F_GETFL = "F_GETFL"
fs.F_SETFL = "F_SETFL"
fs.F_SETCB = "F_SETCB"
fs.F_NOTIF = "F_NOTIF"

-- This one is triggered BEFORE the finalizer is called, thus the resource is still usable in the listener.
fs.EV_CLOSED = "closed"
-- As extra arguments: an integer, containing the length of the data that can be read without blocking
fs.EV_DATAREADY = "data-ready"
-- As extra argumnets: a string, indicating request ID, and an optional string, indicating error if applicable. If no error is passed, operation is assumed to have succeeded atomically.
-- The string ID is conventionally obtained as the error of the successful write.
fs.EV_WRITEDONE = "write-done"

---@class Kocos.fs.FileDescriptor
---@field write? fun(self, data: string): boolean, string?
---@field read? fun(self, amount: integer): string?, string?
---@field seek? fun(self, whence: seekwhence, off: integer): integer?, string?
---@field close? fun(self)
---@field ioctl? fun(self, action: string, ...): ...
---@field flags integer
--- This field should be invoked by the code managing this file descriptor
--- To notify whoever is listening on file system events
--- This is often used for asynchronous I/O, and allows for realtime responses
--- The listener is ONLY automatically informed of *close* events, and thus, **DO NOT MANUALLY NOTIFY OF CLOSE EVENTS**.
---@field listener? function

---@param drive Kocos.device
---@return Kocos.fs.vdrive?
function fs.getVirtualDrive(drive)
	if drive.type == "drive" then return drive end
	if drive.type == "partition" then return drive end
	for _, driver in ipairs(Kocos.drivers) do
		local virt = driver("FS-vdrive", drive)
		if virt then return virt end
	end
end

---@param drive Kocos.device
---@return Kocos.fs.partition[]?
function fs.getPartitionsOf(drive)
	for _, driver in ipairs(Kocos.drivers) do
		local parts = driver("FS-getpartitions", drive)
		if parts then return parts end
	end
end

---@class Kocos.fs.partition: Kocos.fs.vdrive
---@field type "partition"
---@field getDevice fun(): Kocos.device
---@field getDeviceAddress fun(): string
---@field getPartitionType fun(): Kocos.fs.partitionType
---@field getOffset fun(): integer
---@field isReadonly fun(): boolean

---@class Kocos.fs.mountpoint
---@field mountc integer
---@field dev Kocos.device
---@field submounts table<string, Kocos.fs.mountpoint>
---@field fsid string
---@field driverData any
---@field driver? function

--- Maps parition IDs to filesystem mountpoints
---@type table<string, Kocos.fs.mountpoint>
fs.allMounts = {}

---@type Kocos.fs.mountpoint
fs.root = nil

---@param dev Kocos.device
---@return Kocos.fs.mountpoint?
function fs.mount(dev)
	local mountID = dev.address
	if fs.allMounts[mountID] then
		fs.allMounts[mountID].mountc = fs.allMounts[mountID].mountc + 1
		return fs.allMounts[mountID]
	end
	for _, driver in ipairs(Kocos.drivers) do
		local fsid, driverData = driver("FS-mount", dev)
		if fsid then
			fs.allMounts[mountID] = {
				mountc = 1,
				dev = dev,
				submounts = {},
				fsid = fsid,
				driverData = driverData,
				driver = driver,
			}
			return fs.allMounts[mountID]
		end
	end
end

---@param mountpoint Kocos.fs.mountpoint
function fs.unmount(mountpoint)
	if not mountpoint.fsid then return end
	mountpoint.fsid = nil
	mountpoint.mountc = mountpoint.mountc - 1
	if mountpoint.mountc > 0 then return end
	fs.allMounts[mountpoint.dev.address] = nil
	for _, mount in pairs(mountpoint.submounts) do
		fs.unmount(mount)
	end
	if mountpoint.driver then
		mountpoint.driver("FS-unmount", mountpoint.driverData)
	end
end

---@param mountpoint Kocos.fs.mountpoint
function fs.syncMount(mountpoint)
	if mountpoint.driver then
		mountpoint.driver("FS-syncAll", mountpoint.driverData)
	end
end

function fs.sync()
	for _, mount in pairs(fs.allMounts) do
		fs.syncMount(mount)
	end
end

---@param path string
function fs.canonical(path)
	if path:sub(1, 1) == "/" then path = path:sub(2) end
    local parts = string.split(path, "%/")
    local stack = {}

    for _, part in ipairs(parts) do
        if #part > 0 then
            table.insert(stack, part)
            if part == string.rep(".", #part) then
                for _=1,#part do
                    stack[#stack] = nil
                end
            end
        end
    end

    return "/" .. table.concat(stack, "/")
end

function fs.join(...)
	return fs.canonical(table.concat({...}, "/"))
end

---@param path string
---@param root string
function fs.fromRoot(path, root)
	if path == root then
		return "/"
	end
	if root == "/" then
		return path
	end
	return path:sub(#root+1)
end

---@param path string
---@param ignoreLastLink? boolean
---@return Kocos.fs.mountpoint, string
function fs.resolve(path, ignoreLastLink)
	path = fs.canonical(path)
	while path:sub(1,1) == "/" do path = path:sub(2) end
	while path:sub(#path) == "/" do path = path:sub(1, -2) end

	local mountpoint, mountpath = fs.root, path

	while true do
		local done = true
		if mountpoint.submounts[mountpath] then
			if ignoreLastLink then
				break
			end
			return mountpoint.submounts[mountpath], ""
		end

		-- TODO: symlinks

		for m, mp in pairs(mountpoint.submounts) do
			if path:sub(1, #m + 1) == m .. "/" then
				mountpoint = mp
				mountpath = path:sub(#m + 2)
				done = false
			end
		end
		-- TODO: there appears to be a bug where it doesn't loop
		if done then break end
	end

	return mountpoint, mountpath
end

---@param dir string
---@return string[]?, string?
function fs.list(dir)
	if not fs.exists(dir) then
		return nil, Kocos.errno.ENOENT
	end

	local mnt, p = fs.resolve(dir)

	if not mnt.driver then
		return nil, Kocos.errno.ENODRIVER
	end

	local files, err = mnt.driver("FS-listDir", mnt.driverData, p)

	if not files then
		return nil, err or Kocos.errno.EHWPOISON
	end
	return files
end

---@param path string
---@return Kocos.fs.stat?, string?
function fs.stat(path, checklink)
	if not fs.exists(path, checklink) then
		return nil, Kocos.errno.ENOENT
	end

	local mnt, p = fs.resolve(path, checklink)

	if not mnt.driver then
		return nil, Kocos.errno.ENODRIVER
	end

	local stat, err = mnt.driver("FS-stat", mnt.driverData, p)

	if not stat then
		return nil, err or Kocos.errno.EHWPOISON
	end
	return stat
end

---@param path string
---@param mode "r"|"w"|"a"
---@return Kocos.fs.FileDescriptor?, string?
function fs.open(path, mode)
	if not fs.exists(path) then
		return nil, Kocos.errno.ENOENT
	end

	if fs.ftype(path) == fs.FTYPE_DIR then
		return nil, Kocos.errno.EISDIR
	end

	local mnt, p = fs.resolve(path)

	if not mnt.driver then
		return nil, Kocos.errno.ENODRIVER
	end

	return mnt.driver("FS-openFile", mnt.driverData, p, mode)
end

---@param fd Kocos.fs.FileDescriptor
function fs.close(fd)
	if fd.listener then fd.listener(fs.EV_CLOSED) end
	if fd.close then fd:close() end
end

---@param fd Kocos.fs.FileDescriptor
---@param data string
---@return boolean, string?
function fs.write(fd, data)
	if fd.write then
		return fd:write(data)
	end
	return false, Kocos.errno.EBADF
end

---@param fd Kocos.fs.FileDescriptor
---@param len integer
---@return string?, string?
function fs.read(fd, len)
	if fd.read then
		return fd:read(len)
	end
	return nil, Kocos.errno.EBADF
end

---@param fd Kocos.fs.FileDescriptor
---@param whence? seekwhence
---@param off? integer
---@return integer?, string?
function fs.seek(fd, whence, off)
	whence = whence or "set"
	off = off or 0
	if fd.seek then
		return fd:seek(whence, off)
	end
	return nil, Kocos.errno.EBADF
end

---@param fd Kocos.fs.FileDescriptor
---@param action string
---@return ...
function fs.ioctl(fd, action, ...)
	if fd.ioctl then
		return fd:ioctl(action, ...)
	end
	return nil, Kocos.errno.EBADF
end

---@param fd Kocos.fs.FileDescriptor
---@param listener function?
function fs.setlistener(fd, listener)
	fd.listener = listener
end

---@param fd Kocos.fs.FileDescriptor
---@param ev string
function fs.notify(fd, ev, ...)
	if fd.listener then
		fd.listener(ev, ...)
	end
end

---@param reader? fun(self, n: integer): string?, string?
---@param writer? fun(self, data: string): boolean, string?
---@param finalizer? function
---@param ioctl? fun(self, action: string, ...): ...
---@return Kocos.fs.FileDescriptor
function fs.fd_from_rwf(reader, writer, finalizer, ioctl)
	---@type Kocos.fs.FileDescriptor
	return {
		read = reader,
		write = writer,
		close = finalizer,
		ioctl = ioctl,
		flags = 0,
	}
end

---@param path string
---@param perms integer
---@param uid integer
---@param gid integer
---@return boolean?, string?
function fs.touch(path, perms, uid, gid)
	local m, p = fs.resolve(path)
	if not m.driver then
		return nil, Kocos.errno.EHWPOISON
	end
	if fs.ftype(path) == fs.FTYPE_DIR then
		return nil, Kocos.errno.EISDIR
	end
	-- still modifies mtime
	return m.driver("FS-touch", m.driverData, p, perms, uid, gid)
end

---@param path string
---@param perms integer
---@param uid integer
---@param gid integer
---@return boolean?, string?
function fs.mkdir(path, perms, uid, gid)
	local m, p = fs.resolve(path)
	if not m.driver then
		return nil, Kocos.errno.EHWPOISON
	end
	if fs.exists(path, true) then
		return nil, Kocos.errno.EEXIST
	end
	-- still modifies mtime
	return m.driver("FS-mkdir", m.driverData, p, perms, uid, gid)
end

---@param path string
---@return Kocos.fs.ftype?, string?
function fs.ftype(path)
	local m, p = fs.resolve(path, true)
	if not m.driver then
		return nil, Kocos.errno.EHWPOISON
	end
	if m.submounts[p] or p == "" then
		return fs.FTYPE_MNT
	end
	return m.driver("FS-ftype", m.driverData, p)
end

---@param path string
---@return boolean?, string?
function fs.remove(path)
	local ftype, err = fs.ftype(path)
	if not ftype then return nil, err end
	if ftype == fs.FTYPE_NONE then
		return nil, Kocos.errno.ENOENT
	end
	if ftype == fs.FTYPE_MNT then
		return nil, Kocos.errno.EACCESS
	end
	if ftype == fs.FTYPE_DIR then
		local l, err2 = fs.list(path)
		if not l then return nil, err2 end
		if #l > 0 then return nil, Kocos.errno.ENOTEMPTY end
	end
	local m, p = fs.resolve(path)
	if not m.driver then
		return nil, Kocos.errno.EHWPOISON
	end
	return m.driver("FS-remove", m.driverData, p)
end

---@param path string
---@param checklink? boolean
---@return boolean?, string?
function fs.exists(path, checklink)
	local m, p = fs.resolve(path, checklink)
	if not m.driver then
		return nil, Kocos.errno.EHWPOISON
	end
	return m.driver("FS-exists", m.driverData, p)
end

-- super basic managedfs driver
---@param req string
function fs._defaultManagedFS(req, ...)
	if req == "FS-mount" then
		---@type Kocos.device
		local dev = ...
		if dev.type ~= "filesystem" then return end
		return "managedfs", dev
	end
	if req == "FS-listDir" then
		---@type Kocos.device, string
		local dev, path = ...
		if not dev.isDirectory(path) then return nil, Kocos.errno.ENOTDIR end
		return dev.list(path)
	end
	if req == "FS-exists" then
		---@type Kocos.device, string
		local dev, path = ...
		return dev.exists(path)
	end
	if req == "FS-remove" then
		---@type Kocos.device, string
		local dev, path = ...
		return dev.remove(path)
	end
	if req == "FS-ftype" then
		---@type Kocos.device, string
		local dev, path = ...
		if not dev.exists(path) then return fs.FTYPE_NONE end
		if dev.isDirectory(path) then return fs.FTYPE_DIR end
		return fs.FTYPE_REGF
	end
	if req == "FS-touch" then
		---@type Kocos.device, string, integer, integer, integer
		local dev, path, perms, uid, gid = ...
		local f, err = dev.open(path, dev.exists(path) and "w" or "a")
		if not f then return false, err end
		dev.close(f)
		return true
	end
	if req == "FS-mkdir" then
		---@type Kocos.device, string, integer, integer, integer
		local dev, path, perms, uid, gid = ...
		return dev.makeDirectory(path)
	end
	if req == "FS-stat" then
		---@type Kocos.device, string
		local dev, path = ...
		---@type Kocos.fs.stat
		return {
			deviceAddress = dev.address,
			deviceType = dev.type,
			size = dev.size(path) or 0, -- dirs are 0-sized lol
			createdAt = 0,
			lastModified = dev.lastModified(path),
			diskUsed = dev.spaceUsed(),
			diskTotal = dev.spaceTotal(),
			inode = math.random(0, 2^32-1),
			perms = 0,
		}
	end
	if req == "FS-openFile" then
		---@type Kocos.device, string, string
		local dev, path, mode = ...
		if dev.isDirectory(path) then return nil, Kocos.errno.EISDIR end
		local fd, err = dev.open(path, mode)
		if not fd then return err end
		---@type Kocos.fs.FileDescriptor
		return {
			write = function(_, data)
				return dev.write(fd, data)
			end,
			read = function(_, len)
				return dev.read(fd, len)
			end,
			seek = function(_, whence, off)
				return dev.seek(fd, whence, off)
			end,
			close = function()
				dev.close(fd)
			end,
			flags = 0,
		}
	end
end

Kocos.fs = fs

Kocos.printk(Kocos.L_DEBUG, "filesystem subsystem loaded")

Kocos.printk(Kocos.L_INFO, "registering default drivers")
Kocos.addDriver(fs._defaultManagedFS)
Kocos.printk(Kocos.L_INFO, "managedfs driver registered")

-- At this point we're supposed to mount the bootfs, either ramfs image or actual root
Kocos.printk(Kocos.L_INFO, "mounting boot filesystem at /")

local rootDev

if Kocos.args.ramfs then
	rootDev = Kocos.addRamfsComponent(Kocos.args.ramfs, "ramfs")
	Kocos.printk(Kocos.L_DEBUG, "mounting as ramfs tmp root")
else
	rootDev = Kocos.args.root or computer.getBootAddress()
	Kocos.printk(Kocos.L_DEBUG, "mounting as managedfs true root")
end

do
	local dev = assert(component.proxy(rootDev))
	fs.root = assert(fs.mount(dev), Kocos.errno.ENODRIVER)
end
