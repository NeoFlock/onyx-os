local conf = {}

---@param t table<string, string>
---@return string
function conf.encode(t)
	local s = ""
	for k, v in pairs(t) do
		s = s .. tostring(k) .. "=" .. tostring(v) .. "\n"
	end
	return s
end

---@param s string
function conf.decode(s)
	---@type table<string, string>
	local t = {}
	local lines = string.split(s, "\n")

	for _, line in ipairs(lines) do
		local eql = string.find(line, "=")
		if eql then
			local k = line:sub(1, eql-1)
			local v = line:sub(eql+1)
			t[k] = v
		end
	end

	return t
end

return conf
