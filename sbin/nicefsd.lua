--!lua

-- NiceFS driver

local LEN_MAX = 2^20
local R = 1
local W = 2
local X = 4
local D = 8
local ENTRY_SIZE = 32

---@class nicefs.entry
---@field name string
---@field fileSize integer
---@field mode integer
---@field firstBlock integer

---@class nicefs.filestate
---@field openHandles integer
---@field sector integer
---@field idx integer
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

---@type table<string, fun(state: nicefs.state, ...): ...>
local nicefs = {}

function nicefs.sync(state)
	nicefs.syncSuperblock(state)
	for _, block in ipairs(state.cache) do
		nicefs.syncBlock(state, block)
	end
end

function nicefs.syncSuperblock(state)
	local data = "NiceFS1\0" .. string.pack(">I2>I2>I2", state.nextFreeBlock, state.freeList, state.activeBlockCount) .. nicefs.encodeEntry(state, state.rootDir)
	nicefs.writeSector(state, 2, data)
end

---@param cache nicefs.cachedBlock
function nicefs.syncBlock(state, cache)
	if cache.dirty then
		state.dev.writeSector(cache.sector, cache.data)
	end
	cache.dirty = false
end

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
function nicefs.parseEntry(state, data)
	local fileSizeAndMode, firstBlock = string.unpack(">I3>I2", data, 17)
	---@type nicefs.entry
	return {
		name = data:sub(1, 16):gsub("\0", ""),
		fileSize = fileSizeAndMode % LEN_MAX,
		mode = math.floor(fileSizeAndMode / LEN_MAX),
		firstBlock = firstBlock,
	}
end

---@param entry nicefs.entry
---@return string
function nicefs.encodeEntry(state, entry)
	local fileSizeAndMode = entry.fileSize + entry.mode * LEN_MAX
	return string.pack("c16>I3>I2", entry.name, fileSizeAndMode, entry.firstBlock)
end

assert(k.mkdriver(function(req, ...)
	if req == "FS-mount" then
		---@type Kocos.fs.partition
		local dev = ...
		if dev.type ~= "drive" and dev.type ~= "partition" then return end
		local mainSector = dev.readSector(2)
		if mainSector:sub(1, 8) ~= "NiceFS1\0" then return end
		local nextFree, freeList, active = string.unpack(">I2>I2>I2", mainSector, 9)
		local rootDir = nicefs.parseEntry(_, mainSector:sub(15, 46))
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
		}
		return "nicefs", state
	end
	if req == "FS-listDir" then
		---@type nicefs.state, string
		local state, path = ...
		-- trust me bro
		if path == "" then return {} end
	end
	if req == "FS-stat" then
		---@type nicefs.state, string
		local state, path = ...
		-- trust me bro
		local diskUsed = state.activeBlockCount * state.sectorSize
		local diskTotal = state.dev.getCapacity()
		if path == "" then
			---@type Kocos.fs.stat
			return {
				deviceAddress = state.dev.address,
				deviceType = state.dev.type,
				size = 0,
				-- not stored
				createdAt = 0,
				lastModified = 0,
				-- peak
				diskUsed = diskUsed,
				diskTotal = diskTotal,
				inode = 0,
				perms = 0,
			}
		end
	end
	if req == "FS-exists" then
		---@type nicefs.state, string
		local state, path = ...
		if path == "" then return true end
	end
	if req == "FS-unmount" or req == "FS-syncAll" then
		---@type nicefs.state
		local state = ...
		nicefs.sync(state)
	end
end))

-- service done loading

k.invokeDaemon("initd", "markComplete")
k.kill(k.getpid(), "SIGSTOP")
coroutine.yield()
