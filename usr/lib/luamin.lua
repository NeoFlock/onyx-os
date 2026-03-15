-- Lua minification library

local luatok = require("luatok")
local luapp = require("luapreproc")

---@param code string
---@return string
return function(code)
	local toks, err, loc = luatok.tokenize(code, false)
	if not toks then
		error("byte " .. loc .. ":" .. err)
	end
	assert(toks)

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
	return luapp.mergeTokens(toks)
end
