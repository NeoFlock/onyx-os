--!lua

local luatok = require("luatok")

local files = {...}

if #files == 0 then
	print("highlight - Print files with syntax highlighting")
	print("usage: highlight [files...]")
	return
end

---@type {[luatok.tt]: string}
local colors = {
	whitespace = "\x1b[0m",
	comment = "\x1b[90m",
	keyword = "\x1b[34m",
	identifier = "\x1b[33m",
	string = "\x1b[32m",
	number = "\x1b[92m",
	symbol = "\x1b[97m",
}

for _, file in ipairs(files) do
	if #files > 1 then
		print(file)
	end
	local data = assert(readfile(file))
	local i = 1
	while true do
		local tok, err = luatok.tokenAt(data, i)
		if err then print("Error at byte " .. i .. ": " .. err) return end
		if not tok then break end
		k.write(1, (colors[tok.type] or "\x1b[0m") .. data:sub(i, i + tok.len - 1))
		i = i + tok.len
	end
end
