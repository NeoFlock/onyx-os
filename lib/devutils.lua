local devutils = {}

---@param device string
---@param dir? string
---@return string?
function devutils.pathToDev(device, dir)
	if not dir then
		return devutils.pathToDev(device, "/dev") or devutils.pathToDev(device, "/dev/components")
	end
	local l = assert(k.list(dir))
	for _, p in ipairs(l) do
		local path = k.join(dir, p)
		local stat = k.stat(path)
		if stat and stat.deviceAddress == device then
			return path
		end
	end
end

return devutils
