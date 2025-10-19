--!lua
-- Make a NiceFS filesystem

local args = {...}

---@type integer?
local sectorSize
---@type integer
local nextFreeBlock = 3

local function printHelp()
	print("mkfs.nicefs -b sectorSize -F nextFreeBlock <device>")
end

local MAX_LEN = 2^20
local R = 1
local W = 2
local X = 4
local D = 8

while true do
	---@type string
	local arg = args[1]
	if not arg then break end
	if arg:sub(1, 1) ~= "-" then break end
	table.remove(args, 1)
	if arg == "-b" then
		local n = table.remove(args, 1)
		sectorSize = tonumber(n)
		if not sectorSize then
			print("Bad sector size:", n)
			return 1
		end
	elseif arg == "-F" then
		local n = table.remove(args, 1)
		nextFreeBlock = tonumber(n)
		if not nextFreeBlock then
			print("Bad next free block:", n)
			return 1
		end
	else
		print("Unknown flag:", arg)
		printHelp()
	end
end

local dev = args[1]
if not dev then
	print("Unspecified device")
	return 1
end

local fd = assert(k.open(dev, "w"))
if not sectorSize then
	sectorSize = assert(k.ioctl(fd, "getSectorSize"))
end

-- root sector is irrelevant
assert(k.seek(fd, "set", sectorSize))


local batch = {}

-- add header
table.insert(batch, "NiceFS1\0")
-- Next free block
table.insert(batch, string.pack(">I2", nextFreeBlock))
-- freeList and activeBlockCount (nothing freed, 2 blocks in use)
table.insert(batch, "\0\0\0\2")

-- Root directory
local dirMode = 0 + (R + W + X + D) * MAX_LEN

table.insert(batch, string.rep("\0", 16))
table.insert(batch, string.pack(">I3", dirMode))
-- NULL first block, meaning unallocated space
table.insert(batch, string.pack(">I2", 0))

-- Write the damn stuff
local ok, err = k.write(fd, table.concat(batch))
if not ok then
	print("Error:", err)
	return 1
end
