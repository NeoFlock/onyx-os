--!lua

local files = {...}

for _, file in ipairs(files) do
	local ok, err = k.remove(file)
	if not ok then
		k.write(2, "error: " .. err .. "\n")
		return 1
	end
end
