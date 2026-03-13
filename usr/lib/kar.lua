-- Kocos ARchive
-- Used by ramfs
-- TODO: Document the format in docs/kar.md

---@class kar.record
---@field name string
---@field type Kocos.filetype
---@field uid integer
---@field gid integer
---@field perms integer
---@field mtime integer
---@field data? string
---@field entries? kar.record[]

local kar = {}

kar.header = "KAR\0"
kar.version = 0

---@type table<Kocos.filetype, integer>
kar.typemap = {
	regular = 0,
	directory = 1,
	symlink = 2,
	fifo = 3,
	device = 4,
}

---@type table<integer, Kocos.filetype>
kar.invtypemap = {}
for k, v in pairs(kar.typemap) do kar.invtypemap[v] = k end

---@param record kar.record
---@param buf string[]
function kar.encodeRecordInto(record, buf)
	table.insert(buf, record.name .. "\0")
	local mode = record.perms + (kar.typemap[record.type] or 0) * 512
	table.insert(buf, string.fromnumBE(mode, 2))
	table.insert(buf, string.char(record.uid, record.gid))
	local len = 0
	if record.data then len = #record.data end
	if record.entries then len = #record.entries end
	table.insert(buf, string.fromnumBE(len, 4))
	table.insert(buf, string.fromnumBE(record.mtime, 8))
	if record.data then
		table.insert(buf, record.data)
	elseif record.entries then
		for _, entry in ipairs(record.entries) do
			kar.encodeRecordInto(entry, buf)
		end
	end
end

---@param records kar.record[]
function kar.encode(records)
	---@type string[]
	local buf = {kar.header, string.fromnumBE(kar.version, 2)}

	for _, record in ipairs(records) do
		kar.encodeRecordInto(record, buf)
	end

	return table.concat(buf)
end

---@param data string
---@param off integer
---@return kar.record record, integer len
function kar.decodeRecord(data, off)
	local nameTerm = string.find(data, "\0", off)
	local name = data:sub(off, nameTerm-1)
	local mode = string.tonumBE(data, 1+nameTerm, 2)
	local uid, gid = string.byte(data, 3+nameTerm, 4+nameTerm)
	local perms = mode % 512
	local ty = kar.invtypemap[math.floor(mode / 512)] or "regular"
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
			local ent, size = kar.decodeRecord(data, curOff)
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
function kar.decode(data)
	if data:sub(1, 6) ~= (kar.header .. string.fromnumBE(kar.version, 2)) then return end
	---@type kar.record[]
	local recs = {}
	local off = 7
	while off < #data do
		local rec, len = kar.decodeRecord(data, off)
		table.insert(recs, rec)
		off = off + len
	end
	return recs
end

---@type kar.record
--- A test record for testing
kar.testFile = {
	name = "testfile",
	type = "regular",
	uid = 1,
	gid = 3,
	mtime = 157,
	perms = 6*64 + 6*8 + 6,
	data = "test data here",
}

---@type kar.record
--- A more complex test record for testing
kar.testDirectory = {
	name = "testdir",
	type = "directory",
	uid = 0,
	gid = 0,
	mtime = 0,
	perms = 511,
	entries = {
		{
			name = "etc",
			type = "directory",
			uid = 0,
			gid = 0,
			mtime = 0,
			perms = 497,
			entries = {
				{
					name = "a",
					type = "regular",
					uid = 0,
					gid = 0,
					mtime = 0,
					perms = 497,
					data = "stuff",
				},
			},
		},
		{
			name = "a",
			type = "regular",
			uid = 0,
			gid = 0,
			mtime = 0,
			perms = 497,
			data = "stuff 2",
		},
	},
}

---@return kar.record?
function kar.toRecord(path)
	local stat = k.stat(path)
	if not stat then return end
	local _, name = k.parentPath(path)
	if not name then return end

	local ty = assert(k.ftype(path))

	---@type kar.record
	local rec = {
		name = name,
		type = ty,
		uid = stat.uid,
		gid = stat.gid,
		mtime = stat.lastModified,
		perms = stat.perms,
	}

	if ty == "regular" then
		rec.data = assert(readfile(path))
	elseif ty == "directory" then
		local l = assert(k.list(path))
		rec.entries = {}
		for _, ent in ipairs(l) do
			local entrec = kar.toRecord(k.join(path, ent))
			if not entrec then return end
			table.insert(rec.entries, entrec)
		end
	end
	return rec
end

return kar
