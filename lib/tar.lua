-- USTAR Tar, based off https://en.wikipedia.org/wiki/Tar_(computing)#POSIX.1-2001 and xxding the output of GNU tar
-- This handles decoding and encoding
-- Changes from normal TAR:
-- To work with the tar files I made with GNU tar, the ustar header has been changed from "ustar\x0000" to "ustar\x20\x20\x00", matching GNU tar.

---@alias tar.type "regular"|"hardlink"|"symlink"|"chardev"|"blockdev"|"directory"|"fifo"|"contiguous"|"g"|"x"

---@class tar.record
---@field name string
---@field mode integer
---@field uid integer
---@field gid integer
---@field data string
---@field mtime integer
---@field type tar.type
---@field linkpath? string
---@field owningUserName string
---@field owningGroupName string
---@field filenamePrefix string

local tar = {}
tar.sectorSize = 512
tar.checksumPlaceholder = string.rep(" ", 8)
tar.devPlaceholder = string.rep("\0", 8)
tar.terminatorHeader = string.rep("\0", tar.sectorSize)

---@type table<tar.type, string>
tar.typeTable = {
	regular = "0",
	hardlink = "1",
	symlink = "2",
	chardev = "3",
	blockdev = "4",
	directory = "5",
	fifo = "6",
	-- no idea what they mean by this
	contiguous = "7",
	-- these may be hard to remember
	g = "g",
	x = "x",
}

---@type table<string, tar.type>
tar.invTypeTable = {}
for t, c in pairs(tar.typeTable) do
	tar.invTypeTable[c] = t
end

---@param s string
---@param i? integer
---@param j? integer
function tar.eraseNULs(s, i, j)
	return s:sub(i or 1,j):gsub("\0", "")
end

---@param buf string
---@return tar.record[]
function tar.parse(buf)
	---@type tar.record[]
	local records = {}
	local off = 0
	while off < #buf do
		local header = buf:sub(off+1, off+tar.sectorSize)
		if header == tar.terminatorHeader then break end -- technically there should be 2 but idc
		local name = tar.eraseNULs(header, 1, 100)
		local mode = tonumber(tar.eraseNULs(header, 101, 108), 8) or 0
		local uid = tonumber(tar.eraseNULs(header, 109, 116), 8) or 0
		local gid = tonumber(tar.eraseNULs(header, 117, 124), 8) or 0
		local len = tonumber(tar.eraseNULs(header, 125, 136), 8) or 0
		local mtime = tonumber(tar.eraseNULs(header, 137, 148), 8) or 0
		-- todo: check chksum
		local chksum = tonumber(tar.eraseNULs(header, 149, 156), 8) or 0
		local type = tar.invTypeTable[header:sub(157, 157)]
		local linkedFile = tar.eraseNULs(header, 158, 257)
		local user = tar.eraseNULs(header, 266, 297)
		local group = tar.eraseNULs(header, 298, 328)
		off = off + tar.sectorSize
		local data = buf:sub(off+1, off+len)
		off = off + math.align(len, tar.sectorSize)
		-- we just kinda assume ustar
		local filenamePrefix = tar.eraseNULs(header, 346, 500)
		records[#records+1] = {
			name = name,
			mode = mode,
			uid = uid,
			gid = gid,
			mtime = mtime,
			type = type,
			linkpath = linkedFile,
			owningUserName = user,
			owningGroupName = group,
			data = data,
			filenamePrefix = filenamePrefix,
		}
	end
	return records
end

--- A record to use as a test
--- Mostly used internally for, well, testing
---@type tar.record
tar.testRecord = {
	type = "regular",
	data = "print('Hello, world!')\n",
	filenamePrefix = "",
	name = "test.lua",
	uid = 1,
	gid = 1,
	mode = tonumber("777", 8) or 0,
	mtime = 0,
	owningGroupName = "group",
	owningUserName = "user",
	linkpath = nil,
}

---@type tar.record
tar.testDir = {
	type = "directory",
	data = "",
	filenamePrefix = "",
	name = "stuff",
	uid = 1,
	gid = 1,
	mode = tonumber("777", 8) or 0,
	mtime = 0,
	owningGroupName = "group",
	owningUserName = "user",
	linkpath = nil,
}

---@param n integer
---@param minlen integer
---@return string
function tar.intToOctal(n, minlen)
	if n == 0 then return string.rep("0", minlen) end
	local digits = {}
	while n > 0 do
		table.insert(digits, n % 8) -- stored as integers for performance, appended to the end for O(log N) complexity
		n = math.floor(n / 8)
	end
	table.reverse(digits) -- O(N) operation
	return string.rep("0", minlen - #digits) .. table.concat(digits)
end

---@param t string[]
---@return integer
function tar.evalChecksum(t)
	local sum = 0
	for _, s in ipairs(t) do
		for i=1,#s do
			sum = sum + s:byte(i,i)
		end
	end
	return sum
end

---@param record tar.record
---@param t string[]
function tar.encodeRecordInto(record, t)
	local header = {}
	-- TODO: support longer filenames
	-- also TODO: optimize even further, for fun and profit
	-- AND ALSO TODO: error when we get into REALLY BAD situations like files being too big!
	table.insert(header, string.rightpad(record.name, 100, "\0"))
	table.insert(header, tar.intToOctal(record.mode, 7))
	table.insert(header, "\0")
	table.insert(header, tar.intToOctal(record.uid, 7))
	table.insert(header, "\0")
	table.insert(header, tar.intToOctal(record.gid, 7))
	table.insert(header, "\0")
	table.insert(header, tar.intToOctal(#record.data, 11))
	table.insert(header, "\0")
	table.insert(header, tar.intToOctal(record.mtime, 11))
	table.insert(header, "\0")
	table.insert(header, tar.checksumPlaceholder)
	local chksumidx = #header
	table.insert(header, tar.typeTable[record.type])
	table.insert(header, string.rightpad(tar.linkpath or "", 100, "\0"))

	-- end of normal tar header, beginning of ustar header
	table.insert(header, "ustar  \0") -- GNU tar did it so...
	table.insert(header, string.rightpad(record.owningUserName, 32, "\0"))
	table.insert(header, string.rightpad(record.owningGroupName, 32, "\0"))
	-- no one actually cares about these anymore
	table.insert(header, tar.devPlaceholder)
	table.insert(header, tar.devPlaceholder)
	-- well they do care about this
	table.insert(header, string.rightpad(record.filenamePrefix, 155, "\0"))

	-- we must compute the header afterwards
	local sum = tar.evalChecksum(header)
	header[chksumidx] = tar.intToOctal(sum, 6) .. "\0 "

	table.insert(t, string.rightpad(table.concat(header), tar.sectorSize, "\0"))
	if #record.data > 0 then
		table.insert(t, string.rightpad(record.data, math.align(#record.data, tar.sectorSize), "\0"))
	end
end

---@param records tar.record[]
---@return string
function tar.encode(records)
	-- For those wondering, concatenating N strings in a row is O(N^2+N), while table.concat is O(N log N)
	---@type string[]
	local encoded = {}
	for _, record in ipairs(records) do
		tar.encodeRecordInto(record, encoded)
	end
	-- at least 2!
	table.insert(encoded, tar.terminatorHeader)
	table.insert(encoded, tar.terminatorHeader)
	return table.concat(encoded)
end

return tar
