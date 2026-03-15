-- minimal copy of the /usr/lib/kar.lua decoder

local invtypemap = {
	[0] = "regular",
	[1] = "directory",
	[2] = "symlink",
	[3] = "fifo",
	[4] = "device",
}

---@param data string
---@param off integer
---@return kar.record record, integer len
local function decodeRecord(data, off)
	local nameTerm = string.find(data, "\0", off)
	local name = data:sub(off, nameTerm-1)
	local mode = string.tonumBE(data, 1+nameTerm, 2)
	local uid, gid = string.byte(data, 3+nameTerm, 4+nameTerm)
	local perms = mode % 512
	local ty = invtypemap[math.floor(mode / 512)] or "regular"
	local len = string.tonumBE(data, 5+nameTerm, 4)
	local mtime = string.tonumBE(data, 9+nameTerm, 8)

	local entryLen = #name + 17

	---@type kar.record
	local rec = {
		name = name,
		type = ty,
		perms = perms,
		uid = uid,
		gid = gid,
		mtime = mtime,
	}

	if ty == "directory" then
		rec.entries = {}
		local curOff = 17+nameTerm
		for _=1,len do
			local ent, size = decodeRecord(data, curOff)
			table.insert(rec.entries, ent)
			curOff = curOff + size
			entryLen = entryLen + size
		end
	else
		rec.data = string.sub(data, 17+nameTerm, 16+nameTerm+len)
		entryLen = entryLen + #rec.data
	end

	return rec, entryLen
end

---@param data string
---@return kar.record[]?
local function decode(data)
	---@type kar.record[]
	local recs = {}
	local off = 7
	while off < #data do
		local rec, len = decodeRecord(data, off)
		table.insert(recs, rec)
		off = off + len
	end
	return recs
end

---@param rec kar.record
---@return Kocos.ramNode?, string?
local function ktarToRam(rec)
	if rec.type == "regular" then
		---@type Kocos.ramNode
		return {
			uid = rec.uid,
			gid = rec.gid,
			perms = rec.perms,
			lastModified = rec.mtime,
			regular = rec.data,
		}
	end
	if rec.type == "directory" then
		---@type Kocos.ramNode
		local dir = {
			uid = rec.uid,
			gid = rec.gid,
			perms = rec.perms,
			lastModified = rec.mtime,
			dir = {},
		}
		for _, ent in ipairs(rec.entries) do
			dir.dir[ent.name] = ktarToRam(ent)
		end
		return dir
	end
	return nil, "unsupported type: " .. rec.type
end

---@param req string
---@param data string
---@param cmdline string
return function(req, data, cmdline)
	if req ~= "FS-ramfs" then return end
	if data:sub(1, 6) ~= "KAR\0\0\0" then return end
	local parsed = decode(data)
	if not parsed then return nil, "bad kar" end

	---@type Kocos.ramNode
	local node = {
		perms = 511,
		uid = 0,
		gid = 0,
		lastModified = 0,
		dir = {},
	}
	for _, ent in ipairs(parsed) do
		node.dir[ent.name] = ktarToRam(ent)
	end
	return node
end
