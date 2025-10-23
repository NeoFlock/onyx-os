--!lua

-- NiceFS driver

local LEN_MAX = 2^20
local R = 1
local W = 2
local X = 4
local D = 8
local ENTRY_SIZE = 32
local NULL = 0

---@class nicefs.entry
---@field name string
---@field fileSize integer
---@field mode integer
---@field firstBlock integer
---@field sector integer
---@field idx integer

---@class nicefs.filestate
---@field openHandles integer
---@field entry nicefs.entry

---@class nicefs.handle
---@field state nicefs.filestate
---@field cursor integer

---@class nicefs.cachedBlock
---@field sector integer
---@field data string
---@field dirty boolean

local blockCacheSize = tonumber(os.getenv("NICEFS_BCACHE")) or 4096

---@class nicefs.state
---@field dev Kocos.fs.partition
---@field nextFreeBlock integer
---@field freeList integer
---@field activeBlockCount integer
---@field cache nicefs.cachedBlock[]
---@field maxCacheSize integer
---@field sectorSize integer
---@field rootDir nicefs.entry
---@field maxBlock integer

local nicefs = {}

---@param state nicefs.state
function nicefs.sync(state)
	nicefs.syncSuperblock(state)
	for _, block in ipairs(state.cache) do
		nicefs.syncBlock(state, block)
	end
end

---@param state nicefs.state
function nicefs.syncSuperblock(state)
	local data = "NiceFS1\0" .. string.pack(">I2>I2>I2", state.nextFreeBlock, state.freeList, state.activeBlockCount) .. nicefs.encodeEntry(state.rootDir)
	nicefs.writeSector(state, 2, data)
end

---@param state nicefs.state
---@param cache nicefs.cachedBlock
function nicefs.syncBlock(state, cache)
	if cache.dirty then
		state.dev.writeSector(cache.sector, cache.data)
		cache.dirty = false
	end
end

---@param state nicefs.state
---@param sector integer
---@return string
function nicefs.readSector(state, sector)
	for _, block in ipairs(state.cache) do
		if block.sector == sector then
			return block.data
		end
	end
	local data = assert(state.dev.readSector(sector))
	table.insert(state.cache, {
		sector = sector,
		data = data,
		dirty = false,
	})
	while #state.cache > state.maxCacheSize do
		nicefs.syncBlock(state, table.remove(state.cache, 1))
	end
	return data
end

---@param state nicefs.state
---@param sector integer
---@param data string
function nicefs.writeSector(state, sector, data)
	data = string.rightpad(data, state.sectorSize, "\0")
	for _, block in ipairs(state.cache) do
		if block.sector == sector then
			block.dirty = true
			return
		end
	end
	state.dev.writeSector(sector, data)
end

---@param data string
---@return nicefs.entry
function nicefs.parseEntry(data)
	local fileSizeAndMode, firstBlock = string.unpack(">I3>I2", data, 17)
	---@type nicefs.entry
	return {
		name = data:sub(1, 16):gsub("\0", ""),
		fileSize = fileSizeAndMode % LEN_MAX,
		mode = math.floor(fileSizeAndMode / LEN_MAX),
		firstBlock = firstBlock,
		sector = NULL,
		idx = 1,
	}
end

---@param entry nicefs.entry
---@return string
function nicefs.encodeEntry(entry)
	local fileSizeAndMode = entry.fileSize + entry.mode * LEN_MAX
	return string.pack("c16>I3>I2", entry.name, fileSizeAndMode, entry.firstBlock)
end

---@param block string
---@return integer next, string data
function nicefs.splitBlock(block)
	local next = string.unpack(">I2", block)
	return next, block:sub(ENTRY_SIZE+1)
end

---@param next integer
---@param data string
---@return string
function nicefs.mkBlock(next, data)
	return string.rightpad(string.pack(">I2", next), ENTRY_SIZE, "\0") .. data
end

---@param state nicefs.state
---@return integer?, string?
function nicefs.allocBlock(state)
	if state.freeList ~= NULL then
		local allocated = state.freeList
		local block = nicefs.readSector(state, allocated)
		local next = nicefs.splitBlock(block)
		state.freeList = next
		return allocated
	end
	if state.nextFreeBlock > state.maxBlock then
		return nil, "out of space"
	end
	local allocated = state.nextFreeBlock
	state.nextFreeBlock = allocated + 1
	return allocated
end

---@param state nicefs.state
---@param block integer
function nicefs.freeBlock(state, block)
	local lastFree = state.freeList
	nicefs.writeSector(state, block, string.pack(">I2", lastFree))
	state.freeList = block
end

---@param state nicefs.state
---@param block integer
---@return integer
function nicefs.countBlocks(state, block)
	local i = 0
	while block ~= NULL do
		local next = nicefs.splitBlock(nicefs.readSector(state, block))
		i = i + 1
		block = next
	end
	return i
end

---@param state nicefs.state
---@param block integer
function nicefs.freeBlockList(state, block)
	while block ~= NULL do
		local next = nicefs.splitBlock(nicefs.readSector(state, block))
		nicefs.freeBlock(state, block)
		block = next
	end
end

---@param state nicefs.state
---@param block integer
---@return nicefs.entry[]
function nicefs.readAllEntries(state, block)
	---@type nicefs.entry[]
	local entries = {}
	local entriesPerBlock = math.floor(state.sectorSize / ENTRY_SIZE) - 1
	while block ~= NULL do
		local next, data = nicefs.splitBlock(nicefs.readSector(state, block))
		for i=1,entriesPerBlock do
			local o = (i-1) * ENTRY_SIZE
			local entryBuf = data:sub(o+1, o+ENTRY_SIZE)
			local entry = nicefs.parseEntry(entryBuf)
			entry.sector = block
			entry.idx = i
			if entry.name ~= "" then
				entries[#entries+1] = entry
			end
		end
		block = next
	end
	return entries
end

---@param state nicefs.state
---@param block integer
---@param name string
---@return nicefs.entry?
function nicefs.getEntry(state, block, name)
	local entriesPerBlock = math.floor(state.sectorSize / ENTRY_SIZE) - 1
	while block ~= NULL do
		local next, data = nicefs.splitBlock(nicefs.readSector(state, block))
		for i=1,entriesPerBlock do
			local o = (i-1) * ENTRY_SIZE
			local entryBuf = data:sub(o+1, o+ENTRY_SIZE)
			local entry = nicefs.parseEntry(entryBuf)
			entry.sector = block
			entry.idx = i
			if entry.name == name then
				return entry
			end
		end
		block = next
	end
end

---@param state nicefs.state
---@param block integer
---@return nicefs.entry?, string?
function nicefs.getOrAllocFreeEntry(state, block)
	local entriesPerBlock = math.floor(state.sectorSize / ENTRY_SIZE) - 1
	while true do
		local next, data = nicefs.splitBlock(nicefs.readSector(state, block))
		for i=1,entriesPerBlock do
			local o = (i-1) * ENTRY_SIZE
			local entryBuf = data:sub(o+1, o+ENTRY_SIZE)
			local entry = nicefs.parseEntry(entryBuf)
			entry.sector = block
			entry.idx = i
			if entry.name == "" then
				return entry
			end
		end
		if next == NULL then
			local buf, err = nicefs.allocBlock(state)
			if not buf then return nil, err end
			nicefs.writeSector(state, block, nicefs.mkBlock(buf, data))
			nicefs.writeSector(state, buf, nicefs.mkBlock(NULL, ""))
			---@type nicefs.entry
			return {
				name = "",
				sector = buf,
				idx = 1,
				mode = 0,
				fileSize = 0,
				firstBlock = NULL,
			}
		end
		block = next
	end
end

---@param state nicefs.state
---@param entry nicefs.entry
function nicefs.writeEntry(state, entry)
	if entry.sector == NULL then return end
	local o = entry.idx * ENTRY_SIZE
	local i, j = o+1, o+ENTRY_SIZE
	local data = nicefs.readSector(state, entry.sector)
	data = data:sub(1, i-1) .. nicefs.encodeEntry(entry) .. data:sub(j+1)
	nicefs.writeSector(state, entry.sector, data)
end

---@param state nicefs.state
---@param path string
---@return nicefs.entry? file, string? err
function nicefs.entryOf(state, path)
	path = k.canonical(path):sub(2)
	if path == "" then return state.rootDir end
	local parts = string.split(path, "/")
	local current = state.rootDir

	while #parts > 0 do
		if (current.mode & D) ~= D then
			return nil, k.errnos().ENOTDIR
		end
		local part = table.remove(parts, 1)
		local ent = nicefs.getEntry(state, current.firstBlock, part)
		if not ent then
			return nil, k.errnos().ENOENT
		end

		current = ent
	end

	return current
end

---@param state nicefs.state
---@param entry nicefs.entry
---@return boolean, string?
function nicefs.ensureHasBlock(state, entry)
	if entry.firstBlock == NULL then
		local buf, err = nicefs.allocBlock(state)
		if not buf then return false, err end
		nicefs.writeSector(state, buf, "")
	end
	return true
end

assert(k.mkdriver(function(req, ...)
	if req == "FS-mount" then
		---@type Kocos.fs.partition
		local dev = ...
		if dev.type ~= "drive" and dev.type ~= "partition" then return end
		local mainSector = dev.readSector(2)
		if mainSector:sub(1, 8) ~= "NiceFS1\0" then return end
		local nextFree, freeList, active = string.unpack(">I2>I2>I2", mainSector, 9)
		local rootDir = nicefs.parseEntry(mainSector:sub(15, 46))
		local sectorSize = dev.getSectorSize()
		---@type nicefs.state
		local state = {
			dev = dev,
			nextFreeBlock = nextFree,
			freeList = freeList,
			activeBlockCount = active,
			rootDir = rootDir,
			cache = {},
			maxCacheSize = math.floor(blockCacheSize / sectorSize),
			sectorSize = sectorSize,
			maxBlock = math.floor(dev.getCapacity() / sectorSize),
		}
		return "nicefs", state
	end
	if req == "FS-listDir" then
		---@type nicefs.state, string
		local state, path = ...
		-- trust me bro
		---@type nicefs.entry[]
		local entries = {}
		if path == "" then
			entries = nicefs.readAllEntries(state, state.rootDir.firstBlock)
		end
		---@type string[]
		local names = {}
		for _, entry in ipairs(entries) do
			if (entry.mode & D) == D then
				table.insert(names, entry.name .. "/")
			else
				table.insert(names, entry.name)
			end
		end
		return names
	end
	if req == "FS-stat" then
		---@type nicefs.state, string
		local state, path = ...
		-- trust me bro
		local diskUsed = state.activeBlockCount * state.sectorSize
		local diskTotal = state.dev.getCapacity()
		local ent, err = nicefs.entryOf(state, path)
		if not ent then return nil, err end
		---@type Kocos.fs.stat
		return {
			deviceAddress = state.dev.address,
			deviceType = state.dev.type,
			size = ent.fileSize,
			-- not stored
			createdAt = 0,
			lastModified = 0,
			-- peak
			diskSize = nicefs.countBlocks(state, ent.firstBlock) * state.sectorSize,
			diskUsed = diskUsed,
			diskTotal = diskTotal,
			inode = ent.firstBlock,
			perms = ent.mode, -- NOT ACCURATE, TODO: fix
		}
	end
	if req == "FS-mkdir" then
		---@type nicefs.state, string, integer, integer, integer
		local state, path, perms, uid, gid = ...
		if path == "" then return true end
		local parentPath, name = k.parentPath(path)
		local parent, err = nicefs.entryOf(state, parentPath)
		if not parent then
			return nil, err
		end
		local ent = nicefs.getEntry(state, parent.firstBlock, name)
		if ent then return true end

		local ok, err = nicefs.ensureHasBlock(state, parent)
		if not ok then return nil, err end

		ent, err = nicefs.getOrAllocFreeEntry(state, parent.firstBlock)
		if not ent then return nil, err end

		ent.name = name
		-- TODO: parse perms
		ent.mode = R + W + X + D
		return true
	end
	if req == "FS-ftype" then
		---@type nicefs.state, string
		local state, path = ...
		local ent = nicefs.entryOf(state, path)
		if not ent then
			return "none"
		end
		return ((ent.mode & D) == D) and "directory" or "regular"
	end
	if req == "FS-exists" then
		---@type nicefs.state, string
		local state, path = ...
		return nicefs.entryOf(state, path) ~= nil
	end
	if req == "FS-unmount" or req == "FS-syncAll" then
		---@type nicefs.state
		local state = ...
		nicefs.sync(state)
		return
	end
end))

-- service done loading

k.invokeDaemon("initd", "markComplete")
k.kill(k.getpid(), "SIGSTOP")
coroutine.yield()
