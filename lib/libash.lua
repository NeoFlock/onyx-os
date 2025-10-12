-- An entire shell parser, in one file

local lexer = {}
local parser = {}

---@alias libash.tt "whitespace"|"comment"|"command-end"|"text"|"var"|"string"|"rawstring"|"eof"|libash.kw

---@alias libash.kw "$?"|"$@"|"$$"|"$arg"|"&"|"|"|"<"|">"|"2>"|"if"|"then"|"else"|"do"|"end"|"for"|"in"|"while"|"function"|"$("|")"

---@class libash.token
---@field type libash.tt
---@field start integer
---@field len integer

lexer.varnameChars="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
lexer.whitespaceChars=" \t\r\f\v\a\b"
lexer.commandSeps = {"\n", ";"}
lexer.keywords = {
	"if", "then", "else", "do", "end", "for", "in", "while", "function",
}

---@return integer
function lexer.escapeLen(str, start)
	return 1
end

---@param str string
---@param start integer
---@return libash.token
function lexer.lexAt(str, start)
	if start > #str then
		---@return libash.token
		return {
			type = "eof",
			start = start,
			len = 0,
		}
	end
	local startC = str:sub(start, start)
	if table.contains(lexer.commandSeps, startC) then
		---@return libash.token
		return {
			type = "command-end",
			start = start,
			len = 1,
		}
	end
	if startC == ")" then
		---@return libash.token
		return {
			type = ")",
			start = start,
			len = 1,
		}
	end
	if startC == "<" then
		---@return libash.token
		return {
			type = "<",
			start = start,
			len = 1,
		}
	end
	if startC == ">" then
		---@return libash.token
		return {
			type = ">",
			start = start,
			len = 1,
		}
	end
	if startC == "|" then
		---@return libash.token
		return {
			type = "|",
			start = start,
			len = 1,
		}
	end
	if startC == "&" then
		---@return libash.token
		return {
			type = "&",
			start = start,
			len = 1,
		}
	end
	if startC == "2" and str:sub(start+1, start+1) == ">" then
		---@return libash.token
		return {
			type = "2>",
			start = start,
			len = 2,
		}
	end
	if startC == "$" then
		local n = str:sub(start+1, start+1)
		if n == "?" then
			---@return libash.token
			return {
				type = "$?",
				start = start,
				len = 2,
			}
		end
		if n == "@" then
			---@return libash.token
			return {
				type = "$@",
				start = start,
				len = 2,
			}
		end
		if n == "$" then
			---@return libash.token
			return {
				type = "$$",
				start = start,
				len = 2,
			}
		end
		if n == "(" then
			---@return libash.token
			return {
				type = "$(",
				start = start,
				len = 2,
			}
		end
		local len = 1
		while true do
			local c = str:sub(start+len, start+len)
			if c == "" then break end
			if not string.find(lexer.varnameChars, c) then break end
			len = len + 1
		end
		local s = str:sub(start, start+len-1)
		if s == "$" then
			---@return libash.token
			return {
				type = "text",
				start = start,
				len = 1,
			}
		end
		if tonumber(s:sub(2)) then
			---@return libash.token
			return {
				type = "$arg",
				start = start,
				len = len,
			}
		end
		---@return libash.token
		return {
			type = "var",
			start = start,
			len = len,
		}
	end
	if startC == '"' then
		-- good string
		local len = 1
		while true do
			local c = str:sub(start+len, start+len)
			if c == "" then break end -- we're allowing it but we don't like it
			len = len + lexer.escapeLen(str, start+len)
			if c == '"' then break end
		end
		---@return libash.token
		return {
			type = "string",
			start = start,
			len = len,
		}
	end
	if startC == "'" then
		-- raw string
		local len = 1
		while true do
			local c = str:sub(start+len, start+len)
			if c == "" then break end -- we're allowing it but we don't like it
			len = len + 1
			if c == "'" then break end
		end
		---@return libash.token
		return {
			type = "rawstring",
			start = start,
			len = len,
		}
	end
	if startC == "#" then
		local len = 1
		while true do
			local c = str:sub(start+len, start+len)
			if c == "" then break end
			len = len + 1
			if c == "\n" then break end
		end
		---@return libash.token
		return {
			type = "comment",
			start = start,
			len = len,
		}
	end
	if string.find(lexer.whitespaceChars, startC, nil, true) then
		local len = 1
		while true do
			local c = str:sub(start+len, start+len)
			if c == "" then break end
			if not string.find(lexer.whitespaceChars, c, nil, true) then break end
			len = len + 1
		end
		---@return libash.token
		return {
			type = "whitespace",
			start = start,
			len = len,
		}
	end
	if string.find(lexer.varnameChars, startC, nil, true) then
		local len = 1
		while true do
			local c = str:sub(start+len, start+len)
			if c == "" then break end
			if not string.find(lexer.varnameChars, c, nil, true) then break end
			len = len + 1
		end
		local v = str:sub(start, start+len-1)
		if table.contains(lexer.keywords, v) then
			---@return libash.token
			return {
				type = v,
				start = start,
				len = len,
			}
		end
		---@return libash.token
		return {
			type = "text",
			start = start,
			len = len,
		}
	end
	---@return libash.token
	return {
		type = "text",
		start = start,
		len = 1,
	}
end

return {
	lexer = lexer,
	parser = parser,
}
