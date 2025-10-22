-- Lua minification library

local luatok = require("luatok")

---@type luatok.tt[]
local theBig3 = {"identifier", "keyword", "number"}

---@param code string
---@return string
return function(code)
	---@type string[]
	local buf = {}
	---@type luatok.tt
	local lastToken = "whitespace"

	do
		local i = 1
		while true do
			local tok, err = luatok.tokenAt(code, i)
			if err then error("byte " .. i .. ": " .. err) end
			if not tok then break end

			local data = code:sub(i, i+tok.len-1)

			if tok.type ~= "comment" and tok.type ~= "whitespace" then
				if table.contains(theBig3, tok.type) and table.contains(theBig3, lastToken) then
					table.insert(buf, " ")
				end
				table.insert(buf, data)
				lastToken = tok.type
			end

			i = i + tok.len
		end
	end

	return table.concat(buf)
end
