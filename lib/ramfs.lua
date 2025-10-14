local ramfs = {}

---@param path string
---@return Kocos.ramfs.node?
function ramfs.readTree(path)
	if k.ftype(path) == "regular" then
		return {
			fileData = assert(readfile(path))
		}
	end
	if k.ftype(path) == "directory" then
		local items = {}
		local files = assert(k.list(path))
		for _, file in ipairs(files) do
			local name = file
			if string.endswith(name, "/") then name = name:sub(1, -2) end
			items[name] = ramfs.readTree(assert(k.join(path, name)))
		end
		return {
			items = items,
		}
	end
end

return ramfs
