-- Virtual filesystem.
-- Also handles the open/read/write/close/etc. syscalls

Kocos.P_EXECUTABLE = 1
Kocos.P_WRITABLE = 2
Kocos.P_READABLE = 4
Kocos.P_MASK = 7
Kocos.P_GROUPSHIFT = 3
Kocos.P_OWNERSHIFT = 6

function Kocos.permCheck(permBits, bit, owned, grouped)
	if owned then
		permBits = permBits >> Kocos.P_OWNERSHIFT
	elseif grouped then
		permBits = permBits >> Kocos.P_GROUPSHIFT
	end
	permBits = permBits & Kocos.P_MASK
	return (permBits & bit) ~= 0
end

---@class Kocos.dev
---@field address string
---@field type string
---@field slot integer

---@class Kocos.blockdev: Kocos.dev
---@field type "drive"
---@field getCapacity fun(): integer
---@field getSectorSize fun(): integer
---@field getPlatterCount fun(): integer
---@field readSector fun(sector: integer): string
---@field writeSector fun(sector: integer, data: string)
---@field readByte fun(index: integer): integer
---@field writeByte fun(index: integer, byte: integer)

---@class Kocos.partdev: Kocos.blockdev
---@field type "partition"
---@field getStorageDevice fun(): string
---@field isReadonly fun(): string
---@field getPartitionType fun(): string
---@field getSectorOffset fun(): integer

---@param blockdev Kocos.blockdev
---@param partaddr string
---@param sectorOff integer
---@param capacity integer
function Kocos.mkblockpart(blockdev, partaddr, sectorOff, capacity)
	-- TODO: register blockdev
end

---@param blockdev Kocos.blockdev
---@param partitions string[]
function Kocos.retainpartof(blockdev, partitions)
	local allparts = {}
	for addr in component.list("partition", true) do
		---@type Kocos.partdev
		local part = component.proxy(addr)
		if part.getStorageDevice() == blockdev.address then
			table.insert(allparts, addr)
		end
	end
	for _, addr in ipairs(allparts) do
		if not table.contains(partitions, addr) then
			component.remove(addr)
		end
	end
end

---@class Kocos.mountState
---@field device string
---@field driver Kocos.module
---@field state any
---@field linkcache table<string, string>

--- The keys are the paths without the leading /
---@type table<string, Kocos.mountState>
Kocos.mounts = {}

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

---@alias Kocos.filetype "none"|"regular"|"directory"|"symlink"|"socket"|"fifo"

---@class Kocos.fstat
---@field deviceAddress string
---@field deviceType string
---@field inode integer
---@field size integer
---@field disksize integer
---@field type Kocos.filetype
---@field perms integer
---@field uid integer
---@field gid integer
---@field lastModified integer
---@field createdAt integer
---@field diskUsed integer
---@field diskTotal integer

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

---@param path string
---@param uid integer
---@param gid integer
---@param permbit integer
---@param keepLink boolean
---@return Kocos.mountState?, string
function Kocos.resolvePath(path, uid, gid, permbit, keepLink)
	path = Kocos.canonicalPath(path)
	local checkPerms = Kocos.getCmdlineBool("FS_RECURSIVEPERM", false)
	local maxLinkCount = Kocos.getCmdlineNum("FS_MAXLINK", 4)
	local linkCount = 0

	local root = Kocos.mounts[""]
	if not root then return nil, Kocos.ENOENT end

	if path == "" then return root, "" end

	while true do
		if linkCount > maxLinkCount then return nil, Kocos.ELOOP end
		local mount, subpath = Kocos.resolveMount(path, keepLink)
		-- TODO: use linkcache

		-- Scan for symlink or violations
		local parts = string.split(subpath, "/")
		local looped = false
		for idx=1, #parts do
			local checkpath = table.concat(parts, "/", 1, idx)
			---@type Kocos.fstat?, string
			local stat, err = mount.driver("FS-stat", mount.state, checkpath)
			if not stat then return nil, err end
			if idx == #parts or checkPerms then
				if not Kocos.permCheck(stat.perms, permbit, stat.uid == uid, stat.gid == gid) then
					return nil, Kocos.EACCESS
				end
			end
			if stat.type == "none" then
				return nil, Kocos.ENOENT
			elseif stat.type == "symlink" and (idx < #parts or not keepLink) then
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
