-- Ash as a library, useful for various shell things

local ash = {}

ash.whitespace = " \n\t\r\f\v"
ash.arraySplit = " \n\t"
ash.bannedSubstituteLetters = ".-()[]{}:=\"\'"
ash.bannedWordLetters = "=$(;><&|\"\'" .. ash.whitespace

ash.shellWords = {
	"while",
	"done",
	"if",
	"then",
	"else",
	"elif",
	"fi",
	"case",
	"in",
	"esac",
	"return",
}

ash.shellSymbols = {
	"$?",
	"$$",
	"$@",
	"$#",
	"$*",
	"$(",
	"(",
	")",
	"=",
	"&&",
	"||",
	">>",
	"<<",
	">",
	"<",
	"|",
}

---@class ash.argument
---@field value? string
---@field substitution? string
---@field command? ash.command
---@field compound? ash.argument[]

---@class ash.command
--- echo hi
---@field simple? ash.argument[]
--- while condition; <block>; done;
---@field while? {condition: ash.command, body: ash.command[]}
--- if condition; then; <block>; fi
---@field if? {checks: {condition: ash.command, body: ash.command[]}[], fallback: ash.command[]}
--- name() {return 0}
---@field funcdef? {name: string, args: string[], body: ash.command[]}
--- Returning an exit
---@field return? ash.argument[]
--- op |
---@field pipeTo? ash.command
--- op > file
---@field outputTo? {fd: integer, file: ash.argument}
--- op >> file
---@field appendTo? {fd: integer, file: ash.argument}
--- op < file
---@field readFrom? string
--- op &&
---@field both? {left: ash.command, right: ash.command}
--- op ||
---@field either? {left: ash.command, right: ash.command}

---@alias ash.tt "text"|"word"|"substitution"|"symbol"|"space"|"command-end"|"string"

---@class ash.token
---@field tt ash.tt
---@field data string
---@field loc integer

---@param data string
---@param off integer 0-based
---@return integer
function ash.lineOfOffset(data, off)
	local l = 1
	for i=1,off do
		local c = data:sub(i, i)
		if c == "\n" then l = l + 1 end
	end
	return l
end

---@param data string
---@param off integer 0-based
---@return ash.token?, string? error, integer? errloc
function ash.tokenat(data, off)
	local c = data:sub(off+1, off+1)
	if c == "\n" or c == ";" then
		---@type ash.token
		return {
			tt = "command-end",
			data = c,
			loc = off,
		}
	end
	if c == "#" then
		local len = 1
		while true do
			local n = data:sub(off+len+1, off+len+1)
			if n == "" then break end
			if n == "\n" then break end
			len = len + 1
		end
		---@type ash.token
		return {
			tt = "space",
			data = data:sub(off+1, off+len),
			loc = off,
		}
	end
	if string.find(ash.whitespace, c, nil, true) then
		local len = 1
		while true do
			local n = data:sub(off+len+1, off+len+1)
			if n == "" then break end
			if not string.find(ash.whitespace, n, nil, true) then break end
			len = len + 1
		end
		---@type ash.token
		return {
			tt = "space",
			data = data:sub(off+1, off+len),
			loc = off,
		}
	end
	for _, sym in ipairs(ash.shellSymbols) do
		if data:sub(off+1, off+#sym) == sym then
			---@type ash.token
			return {
				tt = "symbol",
				data = data:sub(off+1, off+#sym),
				loc = off,
			}
		end
	end

	if not string.find(ash.bannedWordLetters, c) then
		local len = 1
		while true do
			local n = data:sub(off+len+1, off+len+1)
			if n == "" then break end
			if string.find(ash.bannedWordLetters, n) then break end
			len = len + 1
		end

		local s = data:sub(off+1, off+len)
		---@type ash.token
		return {
			tt = table.contains(ash.shellWords, s) and "word" or "text",
			data = s,
			loc = off,
		}
	end

	if c == "$" then
		-- substitution!
		-- since its after the shellSymbols check,
		-- $( is already handled.
		local len = 1
		if data:sub(off+2, off+2) == "{" then
			while true do
				local n = data:sub(off+len+1, off+len+1)
				if n == "" then return nil, "unfinished ${", off end
				len = len + 1
				if n == "}" then break end
			end
		else
			while true do
				local n = data:sub(off+len+1, off+len+1)
				if n == "" then break end
				if string.find(ash.bannedSubstituteLetters, n) then break end
				if string.find(ash.whitespace, n) then break end
				len = len + 1
			end
		end

		local s = data:sub(off+1, off+len)
		if s == "$" then
			---@type ash.token
			return {
				tt = "text",
				data = s,
				loc = off,
			}
		end
		---@type ash.token
		return {
			tt = "substitution",
			data = s,
			loc = off,
		}
	end

	if c == "'" or c == '"' then
		-- raw string
		local len = 1
		while true do
			local n = data:sub(off+len+1, off+len+1)
			if n == "" then
				return nil, "unfinished raw string", off+len
			end
			len = len + 1
			if n == c then break end
		end
		---@type ash.token
		return {
			tt = "string",
			data = data:sub(off+1, off+len),
			loc = off,
		}
	end
	---@type ash.token
	return {
		tt = "text",
		data = c,
		loc = off,
	}
end

---@param data string
---@return ash.token[]? tokens, string? error, integer? errloc
function ash.lex(data)
	---@type ash.token[]
	local toks = {}
	local off = 0
	while off < #data do
		local t, err, loc = ash.tokenat(data, off)
		if not t then return nil, err, loc end
		table.insert(toks, t)
		off = off + #t.data
	end
	return toks
end

---@param tokens ash.token[]
---@param dataLen integer Offset of EoF
---@return ash.command[]? commands, string? error, integer? errloc
function ash.parseTokens(tokens, dataLen)
	---@type ash.command[]
	local cmds = {}

	local parser = {}

	---@return ash.token?
	function parser.peekToken()
		return tokens[1]
	end

	---@return ash.token?
	function parser.nextToken()
		return table.remove(tokens, 1)
	end

	---@param inSub boolean
	---@return ash.argument?, string?, integer?
	function parser.nextArgument(inSub)
		local first = parser.peekToken()
		if not first then return nil, "argument expected", dataLen end

		---@type ash.argument[]
		local parts = {}
		while true do
			local t = parser.peekToken()
			if not t then break end
			---@type ash.argument
			local part = {}
			if t.tt == "command-end" then
				parser.nextToken()
				break
			elseif t.data == ")" and inSub then
				parser.nextToken()
				break
			elseif t.tt == "space" then
				break
			elseif t.tt == "text" then
				parser.nextToken()
				part.value = t.data
			elseif t.tt == "word" then
				parser.nextToken()
				part.value = t.data
			elseif t.tt == "substitution" then
				parser.nextToken()
				if t.data:sub(2, 2) == "{" then
					part.substitution = t.data:sub(3, -2)
				else
					part.substitution = t.data:sub(2)
				end
			elseif t.tt == "string" then
				parser.nextToken()
				part.value = t.data:sub(2, -2)
			elseif t.data == "$?" or t.data == "$$" or t.data == "$@" or t.data == "$#" or t.data == "$*" then
				parser.nextToken()
				part.substitution = t.data
			else
				parser.nextToken()
				part.value = t.data
			end
			table.insert(parts, part)
		end

		if #parts == 1 then return parts[1] end
		---@type ash.argument
		return {
			compound = parts,
		}
	end

	---@param inSub boolean
	---@return ash.command?, string?, integer?
	function parser.nextCommand(inSub)
		local first = parser.peekToken()
		if not first then return nil, "command expected", dataLen end

		if first.tt == "word" then
			parser.nextToken()
			-- special shell word
			return nil, "awkward shell word", first.loc
		end

		---@type ash.command
		local cmd = {simple = {}}

		while true do
			local t = parser.peekToken()
			if not t then break end
			if t.tt == "space" then
				parser.nextToken()
			else
				if t.tt == "command-end" then parser.nextToken() break end
				if t.data == ")" and inSub then parser.nextToken() break end

				local arg, err, loc = parser.nextArgument(inSub)
				if not arg then return nil, err, loc end

				table.insert(cmd.simple, arg)
			end
		end

		return cmd
	end

	while #tokens > 0 do
		local cmd, err, loc = parser.nextCommand(false)
		if not cmd then return nil, err, loc end
		table.insert(cmds, cmd)
	end

	return cmds
end

---@param data string
---@return ash.command[]? commands, string? error, integer? errloc
function ash.parse(data)
	local tok, err, loc = ash.lex(data)
	if not tok then return nil, err, loc end
	return ash.parseTokens(tok, #data)
end

return ash
