-- Lua minification library

local luatok = require("luatok")

---@type luatok.tt[]
local theBig3 = {"identifier", "keyword", "number"}

---@param code string
---@return string
return function(code)
	---@type string[]
	local buf = {}

	---@type luatok.token[]
	local toks = {}

	do -- tokenize
		local i = 1
		while true do
			local tok, err = luatok.tokenAt(code, i)
			if err then error("byte " .. i .. ": " .. err) end
			if not tok then break end
			assert(#tok.data == tok.len)
			i = i + tok.len

			if tok.type ~= "comment" and tok.type ~= "whitespace" then
				table.insert(toks, tok)
			end
		end
	end

	---@type table<string, string>[]
	local scope = {{}}
	local freeList = {}
	local nextName = 0
	local lAlpha = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
	local function numToName(n)
		local s = ""
		while n >= #lAlpha or s == "" do
			local d = n % #lAlpha
			n = math.floor(n / #lAlpha)
			s = s .. lAlpha:sub(d+1,d+1)
		end
		return s
	end
	local function allocName()
		if #freeList > 0 then
			return table.remove(freeList, 1)
		end
		nextName = nextName + 1
		return numToName(nextName)
	end
	local function freeName(name)
		table.insert(freeList, name)
	end

	---@return string
	local function remap(name)
		for i=#scope,1,-1 do
			local locals = scope[i]
			if locals[name] then return name end
			for _, v in pairs(locals) do
				if v == name then
					-- uh-oh, global got mapped to local
					return "_G." .. name
				end
			end
		end
		return name -- global
	end

	do -- local symbol rewriting to reduce versioning
		local i = 1
		while true do
			if not toks[i] then break end
			local tok = toks[i]
			-- main idea
			if tok.type == "identifier" then
				local lastTok = toks[i-1] or tok
				-- if it is, then this is a field, which has runtime implications!
				if lastTok.data ~= "." or lastTok.data ~= ":" then
					tok.data = remap(tok.data)
				end
			-- TODO: check other tokens to compute scope states
			end
			i = i + 1
		::continue::
		end
	end

	do -- combining text in most efficient way
		---@type luatok.tt
		local lastToken = "whitespace"
		for _, tok in ipairs(toks) do
			local data = tok.data

			if table.contains(theBig3, tok.type) and table.contains(theBig3, lastToken) then
				table.insert(buf, " ")
			end
			table.insert(buf, data)
			lastToken = tok.type
		end
	end

	return table.concat(buf)
end
