--!lua

local libash = require("libash")
local path = ...

local c = assert(readfile(path))

local start = 1
while true do
	local t = libash.lexer.lexAt(c, start)
	if t.type == "eof" then break end
	print(string.format("%d. %s %d %q", t.start, t.type, t.len, c:sub(t.start, t.start+t.len-1)))
	start = start + t.len
end
