local primCache = {}

function component._defaultHandler(ev, addr, type)
	if ev == "component_removed" then
		if not primCache[type] then return end
		if primCache[type].address ~= addr then return end
		primCache[type] = nil
	end
end

setmetatable(component, {__index = function(t, key)
	return component.getPrimary(key)
end})

---@param type string
---@return Kocos.device?
function component.getPrimary(type)
	if primCache[type] then return primCache[type] end

	local addr = component.list(type, true)()
	if not addr then return end
	primCache[type] = component.proxy(addr)
	return primCache[type]
end

---@param type string
function component.hasPrimary(type)
	return component.getPrimary(type) ~= nil
end

Kocos.event.listen(component._defaultHandler)
