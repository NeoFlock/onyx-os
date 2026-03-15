-- Virtual Abstract File System library
-- Useful for implementing unmanaged filesystems

---@class vafs.inode
---@field size integer
---@field disksize integer
---@field perms integer
---@field uid integer
---@field gid integer
---@field type Kocos.filetype
---@field linkCount integer
---@field state any

---@class vafs.fileState
---@field fdCount integer
---@field ino integer
---@field inode vafs.inode

---@class vafs.inodeCache
---@field path string
---@field ino integer
---@field inode vafs.inode
---@field lastAcc integer

---@class vafs.filedesc: Kocos.descriptor
---@field _state vafs.state
---@field _path string
---@field _cur integer

---@class vafs.interface
---@field maxInodeCache integer
---@field maxFileDesc integer
--- Flush inodes whenever modified.
---@field flushOnModify boolean
---@field init fun(dev: Kocos.dev, cmdline: string): vafs.interface?, string?
---@field deinit fun(self)
--- Half-synchronize state. This is meant to write pending queues.
--- It is assumed that any read-caches would be retained.
---@field flush fun(self): boolean, string?
--- Synchronize state. This is called after vafs synchronizes its caches.
--- It is assumed block caches will be used, which is why this method exists.
---@field sync fun(self): boolean, string?
--- Should return the ino and inode struct
--- of the root directory.
--- vafs.inode.type MUST be "directory"
---@field rootInode fun(self): integer, vafs.inode
---@field inodeAt fun(self, ino: integer): vafs.inode
--- Returns a table of entries and inode numbers. "." and ".." are completely ignored.
--- It should be a table with the file entries and their inos.
--- trueNames means the entry names should be exact, as in, no / suffix for directories.
--- If trueNames is false, do append a / for entries containing directories.
---@field list fun(self, ino: integer, inode: vafs.inode, trueNames: boolean): table<string, integer>
--- Returns the size of a block.
---@field getBlockSize fun(self): integer
--- block is 0 for the first block.
--- It is the current index of the blocks making up the file data.
---@field readBlock fun(self, ino: integer, inode: vafs.inode, block: integer): string
--- Writes a block of data for a file.
--- It is always in bounds, however if your filesystem does lazy allocation,
--- it should be allocated, and thus can fail due to ENOSPC.
--- #data may be less than the block size, in which case, feel free to pad it with whatever.
---@field writeBlock fun(self, ino: integer, inode: vafs.inode, block: integer, data: string): boolean, string?
--- Attempts to truncate a file to a specific number of blocks.
--- open(path, "w") will call this with 0.
--- inode.size <= blocks * getBlockSize()
---@field truncateBlocks fun(self, ino: integer, inode: vafs.inode, blocks: integer): boolean, string?
--- Save an inode
---@field saveInode fun(self, ino: integer, inode: vafs.inode)
--- Allocate a new inode in a directory. This may be in the root inode.
--- The name is checked to not have existed before.
---@field allocInode fun(self, dirIno: integer, dirInode: vafs.inode, name: string, inode: vafs.inode): boolean, string?
--- Make a hardlink to an inode by ino.
--- This should increase the linkCount by 1 if successful.
--- VAFS will pretend this is the case when managing the cache.
---@field linkInode fun(self, dirIno: integer, dirInode: vafs.inode, name: string, ino: integer): boolean, string?

local vafs = {}
vafs.DEFAULT_MAX_INOCACHE = 128
vafs.DEFAULT_MAX_FILEDESC = 16

---@class vafs.state
---@field control vafs.interface
---@field dev Kocos.dev
---@field fileStates table<string, vafs.fileState>
---@field fileStateNo integer
---@field inodeCache vafs.inodeCache[]
local state = {}
state.__index = state

---@param controlClass vafs.interface
---@param dev Kocos.dev
---@param cmdline string
---@return vafs.state?, string?
function state.init(controlClass, dev, cmdline)
	local control, err = controlClass.init(dev, cmdline)
	if err then return nil, err end
	if not control then return end
	return setmetatable({
		control = control,
		dev = dev,
		fileStates = {},
		fileStateNo = 0,
		inodeCache = {},
	}, state), nil
end

---@param ino integer
---@param inode vafs.inode
function state:flushIno(ino, inode)
	self.control:saveInode(ino, inode)
end

function state:modifiedIno(ino, inode)
	if self.control.flushOnModify then
		self:flushIno(ino, inode)
	end
end

function state:flushInternalCaches()
	for _, ino in ipairs(self.inodeCache) do
		self:flushIno(ino.ino, ino.inode)
	end
end

function state:flush()
	self:flushInternalCaches()
	self.control:flush()
end

function state:sync()
	self:flushInternalCaches()
	self.inodeCache = {}
	self.control:sync()
end

function state:deinit()
	self:flush()
	self.control:deinit()
end

---@param path string
---@param ino integer
---@param inode vafs.inode
function state:cacheIno(path, ino, inode)
	---@type vafs.inodeCache
	local ent = {
		path = path,
		ino = ino,
		inode = inode,
		lastAcc = k.uptime(),
	}

	table.insert(self.inodeCache, ent)
	if #self.inodeCache <= self.control.maxInodeCache then return end
	if #self.inodeCache == 0 then return end

	local lowestAcc = 1
	for i, cache in ipairs(self.inodeCache) do
		local curBest = self.inodeCache[lowestAcc]
		if curBest.lastAcc > cache.lastAcc then
			lowestAcc = i
		end
	end
	table.remove(self.inodeCache, lowestAcc)
end

---@param path string
---@return string, string?
function state:parentPath(path)
	if path == "" then return "", nil end
	local parts = string.split(path, "/")
	if #parts == 1 then return "", path end
	local parent = table.concat(parts, "/", 1, #parts-1)
	return parent, parts[#parts]
end

---@param path string
---@return integer?, vafs.inode?
function state:pathToInoSlow(path)
	if path == "" then
		return self.control:rootInode()
	end
	-- we use this recursive approach such that
	-- if a/b/c is not cached but a/b is,
	-- which it most likely is as the kernel will
	-- spam us with stats for the whole path,
	-- we will not traverse all of a/b/c but instead
	-- yoink a/b and only have c as a cold-read.
	local parent, name = self:parentPath(path)
	local dirino, dirnode = self:pathToIno(parent)
	if not dirino then return end
	assert(dirnode)

	local l = self.control:list(dirino, dirnode, true)
	local ino = l[name]
	if not ino then return end
	return ino, self.control:inodeAt(ino)
end

---@param path string
---@return integer?, vafs.inode?
function state:pathToIno(path)
	for _, cached in ipairs(self.inodeCache) do
		if cached.path == path then
			cached.lastAcc = k.uptime()
			return cached.ino, cached.inode
		end
	end

	local ino, node = self:pathToInoSlow(path)
	if ino and node then
		self:cacheIno(path, ino, node)
	end
	return ino, node
end

---@param ino integer
---@return vafs.inode
function state:inoToNode(ino)
	for _, cached in ipairs(self.inodeCache) do
		if cached.ino == ino then
			return cached.inode
		end
	end

	-- completely uncached
	return self.control:inodeAt(ino)
end

---@param path string
function state:fixpath(path)
	return k.canonical(path):sub(2)
end

---@param interface vafs.interface
function vafs.driverFor(interface)

end

return vafs
