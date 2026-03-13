--!lua

local kar = require("kar")

local path, fmt = ...
fmt = fmt or "kar"
path = path or ("/boot/ramimg-kocos." .. fmt)

local paths = {
	"/sbin",
	"/lib",
	"/etc",
}

if fmt == "kar" then
	---@type kar.record[]
	local records = {}

	for _, f in ipairs(paths) do
		local rec = assert(kar.toRecord(f), "record conversion failed")
		table.insert(records, rec)
	end

	local encoded = kar.encode(records)
	if not k.exists(path) then
		assert(k.touch(path, 6*64, "regular", 0, 0))
	end
	assert(writefile(path, encoded))
	return 0
end
k.write(2, "error: unknown format")
return 1
