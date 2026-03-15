-- Lua preprocessor

local luapp = {}

local luatok = require("luatok")

---@alias luapp.definition luatok.token[] | (fun(toks: luatok.token[]): luatok.token[])

---@type luatok.tt[]
local theBig3 = {"identifier", "keyword", "number"}

---@param toks luatok.token[]
---@return string
function luapp.mergeTokens(toks)
	local buf = {}
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

function luapp.resolveAsArgs(toks)
	return table.deserialize(luapp.mergeTokens(toks))
end

---@param src string
---@param defs table<string, luapp.definition>
---@return string
function luapp.preprocess(src, defs)
	defs = table.copy(defs) or {}

	local toks = assert(luatok.tokenize(src, true))

	---@type luatok.token[]
	local outToks = {}

	local i = 1
	while toks[i] do
		local cur = toks[i]
		local defined = defs[cur.data]

		if type(defined) == "function" then
			i = i + 1
			if toks[i] and toks[i].data == "(" then
				local paramDepth = 1
				i = i + 1
				---@type luatok.token[]
				local args = {}
				while paramDepth > 0 do
					if not toks[i] then error("unfinished macro") end
					if toks[i].data == ")" then
						paramDepth = paramDepth - 1
					elseif toks[i].data == "(" then
						paramDepth = paramDepth + 1
					else
						table.insert(args, toks[i])
					end
					i = i + 1
				end
				local out = defined(args)
				for _, t in ipairs(out) do
					table.insert(outToks, t)
				end
			else
				table.insert(outToks, cur)
			end
		elseif type(defined) == "table" then
			for _, t in ipairs(defined) do
				table.insert(outToks, t)
			end
			i = i + 1
		else
			table.insert(outToks, cur)
			i = i + 1
		end
	end

	return luapp.mergeTokens(outToks)
end

return luapp
