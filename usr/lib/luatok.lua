-- Lua 5.4 tokenization
-- Its Lua 5.4 because Lua syntax is pretty backwards compatible,
-- so might as well support the latest version theoretically applicable
-- Can be used for highlighting

---@alias luatok.tt "whitespace"|"comment"|"keyword"|"identifier"|"string"|"number"|"symbol"

---@class luatok.token
---@field type luatok.tt
---@field len integer

local lib = {}

---@type string[]
lib.keywords = {
	"and",
	"break",
	"do",
	"else",
	"elseif",
	"end",
	"false",
	"for",
	"function",
	"goto",
	"if",
	"in",
	"local",
	"nil",
	"not",
	"or",
	"repeat",
	"return",
	"then",
	"true",
	"until",
	"while",
}

---@type string[]
lib.ops = {
	"+",
	"-",
	"*",
	"/",
	"//",
	"^",
	"%",
	"=",
	"==",
	"~=",
	">=",
	">",
	"<=",
	"<",
	">>",
	"<<",
	"|",
	"&",
	":",
	",",
	".",
	"..",
	"...",
	"(",
	")",
	"[",
	"]",
	"{",
	"}",
	";",
	"#",
}

table.sort(lib.ops, function(a, b) return #a > #b end)

---@param c string
function lib.isalpha(c)
	c = c:lower()
	local b = c:byte()
	return b >= string.byte('a') and b <= string.byte('z')
end

---@param c string
function lib.isnum(c, hex)
	c = c:lower()
	local b = c:byte()
	if hex then
		if b >= string.byte('a') and b <= string.byte('f') then return true end
	end
	return b >= string.byte('0') and b <= string.byte('9')
end

---@param c string
function lib.iswhitespace(c)
	local b = c:byte()
	if not b then return true end
	return b < 33
end

---@param code string
---@param i integer
---@return luatok.token?, string?
function lib.tokenAt(code, i)
	if i > #code then return end
	local c = code:sub(i, i)
	if c == "" then return end
	if lib.iswhitespace(c) then
		local len = 1
		while true do
			local c2 = code:sub(i+len, i+len)
			if c2 == "" then break end
			if not lib.iswhitespace(c2) then break end
			len = len + 1
		end
		---@type luatok.token
		return {
			type = "whitespace",
			len = len,
		}
	end
	if code:sub(i, i+1) == "--" then
		-- TODO: multi-line
		local len = 2
		while true do
			if code:sub(i+len, i+len) == "\n" then break end
			if code:sub(i+len, i+len) == "" then break end
			len = len + 1
		end
		---@type luatok.token
		return {
			type = "comment",
			len = len,
		}
	end
	-- TODO: proper multi-line strings
	if code:sub(i, i+1) == "[[" then
		local len = 2
		while true do
			local c2 = code:sub(i+len, i+len+1)
			if c2 == "]]" then break end
			if #c2 < 2 then break end
			len = len + 1
		end
		---@type luatok.token
		return {
			type = "string",
			len = len+2,
		}
	end
	if c == '"' or c == "'" then
		local len = 1
		while true do
			local c2 = code:sub(i+len, i+len)
			if c2 == c then break end
			if c2 == "" then break end
			len = len + 1
		end
		---@type luatok.token
		return {
			type = "string",
			len = len+1,
		}
	end
	for _, op in ipairs(lib.ops) do
		if code:sub(i, i+#op-1) == op then
			---@type luatok.token
			return {
				type = "symbol",
				len = #op,
			}
		end
	end
	if lib.isalpha(c) or c == "_" then
		local len = 1
		while true do
			local c2 = code:sub(i+len, i+len)
			if c2 == "" then break end
			local isIdent = (c2 == "_") or lib.isalpha(c2) or lib.isnum(c2)
			if not isIdent then break end
			len = len + 1
		end
		local n = code:sub(i, i+len-1)
		---@type luatok.token
		return {
			type = table.contains(lib.keywords, n) and "keyword" or "identifier",
			len = len,
		}
	end
	if lib.isnum(c) then
		local len = 1
		local hex = false
		if code:sub(i, i+1) == "0x" then
			len = 2
			hex = true
		end
		while true do
			local c2 = code:sub(i+len, i+len)
			if c2 == "" then break end
			if not lib.isnum(c2, hex) then break end
			len = len + 1
		end
		if c:sub(i+len, i+len) == "." then
			len = len + 1
			while true do
				local c2 = code:sub(i+len, i+len)
				if c2 == "" then break end
				if not lib.isnum(c2) then break end
				len = len + 1
			end
		end
		if c:sub(i+len, i+len) == "e" then
			len = len + 1
			if c:sub(i+len, i+len) == "+" or c:sub(i+len, i+len) == "-" then
				len = len + 1
			end
			while true do
				local c2 = code:sub(i+len, i+len)
				if c2 == "" then break end
				if not lib.isnum(c2) then break end
				len = len + 1
			end
		end
		---@type luatok.token
		return {
			type = "number",
			len = len,
		}
	end
	return nil, "bad characater"
end

return lib
