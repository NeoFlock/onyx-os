local hex = {}
hex.dictionary = "0123456789abcdef"

---@param n integer 0-15
---@return string
function hex.char(n)
	return hex.dictionary:sub(n+1,n+1)
end

---@param s string
---@return string
function hex.dump(s)
	local t = {}
	for i=1,#s do
		local c = s:byte(i,i)
		table.insert(t, hex.char(math.floor(c / 16)))
		table.insert(t, hex.char(c % 16))
	end
	return table.concat(t)
end

---@param s string
---@return string
function hex.undump(s)
	local t = {}
	for i=1,#s,2 do
		local n = s:sub(i, i+1)
		table.insert(t, string.char(tonumber(n, 16) or 0))
	end
	return table.concat(t)
end

return hex
