-- virtual components

do
	local cmethods = component.methods
	local cinvoke = component.invoke
	local cproxy = component.proxy
	local cfields = component.fields
	local cdoc = component.doc
	local cslot = component.slot
	local ctype = component.type
	local clist = component.list

	---@class Kocos.vdevice
	---@field address string
	---@field type string
	---@field slot integer
	---@field methods table<string, {getter: boolean, setter: boolean, direct: boolean, doc?: string}>
	---@field invoke fun(method: string, ...): ...

	---@type table<string, Kocos.vdevice>
	local vComponents = {}

	--- Code copied from or heavily based off https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/resources/assets/opencomputers/lua/machine.lua
	local vproxyCache = setmetatable({}, {__mode="v"})

	local componentProxy = {
	  __index = function(self, key)
		if self.fields[key] and self.fields[key].getter then
		  return self.invoke(key)
		end
	  end,
	  __newindex = function(self, key, value)
		if self.fields[key] and self.fields[key].setter then
		  return self.invoke(key, value)
		elseif self.fields[key] and self.fields[key].getter then
		  error("field is read-only")
		else
		  rawset(self, key, value)
		end
	  end,
	  __pairs = function(self)
		local keyProxy, keyField, value
		return function()
		  if not keyField then
			repeat
			  keyProxy, value = next(self, keyProxy)
			until not keyProxy or keyProxy ~= "fields"
		  end
		  if not keyProxy then
			keyField, value = next(self.fields, keyField)
		  end
		  return keyProxy or keyField, value
		end
	  end
	}

	local componentCallback = {
	  __call = function(self, ...)
		return component.invoke(self.address, self.name, ...)
	  end,
	  __tostring = function(self)
		return component.doc(self.address, self.name) or "function"
	  end
	}

	---@param vdev Kocos.vdevice
	function component.add(vdev)
		if component.type(vdev.address) then return end
		vComponents[vdev.address] = vdev
		Kocos.event.push("component_added", vdev.address, vdev.type)
		return vdev.address
	end

	---@param address string
	function component.remove(address)
		local v = vComponents[address]
		if not v then return end
		vComponents[address] = nil
		Kocos.event.push("component_removed", v.address, v.type)
	end

	---@param address string
	function component.isVirtual(address)
		return vComponents[address] ~= nil
	end

	---@param address string
	function component.slot(address)
		checkArg(1, address, "string")
		local v = vComponents[address]
		if v then
			return v.slot
		end
		return cslot(address)
	end

	---@param address string
	function component.type(address)
		checkArg(1, address, "string")
		local v = vComponents[address]
		if v then
			return v.type
		end
		return ctype(address)
	end

	---@param address string
	---@param method string
	function component.doc(address, method)
		checkArg(1, address, "string")
		checkArg(2, method, "string")
		local v = vComponents[address]
		if v then
			if not v.methods[method] then return nil, "no such method" end
			return v.methods[method].doc
		end
		return cdoc(address, method)
	end

	---@param address string
	function component.methods(address)
		checkArg(1, address, "string")
		local v = vComponents[address]
		if v then
			local methods = {}
			for name, m in pairs(v.methods) do
				if not m.getter and not m.setter then
					methods[name] = m.direct
				end
			end
			return methods
		end
		return cmethods(address)
	end

	---@param address string
	function component.fields(address)
		checkArg(1, address, "string")
		local v = vComponents[address]
		if v then
			local fields = {}
			for name, m in pairs(v.methods) do
				if m.getter or m.setter then
					-- no overwriting kernel memory for you!
					fields[name] = {getter = m.getter, setter = m.setter}
				end
			end
			return fields
		end
		return cfields(address)
	end

	---@param address string
	---@param method string
	---@return ...
	function component.invoke(address, method, ...)
		checkArg(1, address, "string")
		checkArg(2, method, "string")
		local v = vComponents[address]
		if v then
			local m = v.methods[method]
			if not m then return nil, "no such method" end
			if m.getter or m.setter then return nil, "no such method" end -- its a field!
			return v.invoke(method, ...)
		end
		return cinvoke(address, method, ...)
	end

	function component.proxy(address)
		if not component.isVirtual(address) then return cproxy(address) end
		local type, reason = component.type(address)
		if not type then
		  return nil, reason
		end
		local slot, reason = component.slot(address)
		if not slot then
		  return nil, reason
		end
		if vproxyCache[address] then
		  return vproxyCache[address]
		end
		local fields, reason = component.fields(address)
		if not fields then
		  return nil, reason
		end
		local proxy = {address = address, type = type, slot = slot, fields = fields, invoke = vComponents[address].invoke}
		local methods, reason = component.methods(address)
		if not methods then
		  return nil, reason
		end
		for method in pairs(methods) do
			proxy[method] = setmetatable({address=address,name=method}, componentCallback)
		end
		setmetatable(proxy, componentProxy)
		vproxyCache[address] = proxy
		return proxy
	end

	---@param filter? string
	---@param exact? boolean
	function component.list(filter, exact)
		local t = clist(filter, exact)
		for addr, v in pairs(vComponents) do
			if filter then
				if exact then
					if v.type == filter then
						t[addr] = v.type
					end
				else
					if string.match(v.type, filter) then
						t[addr] = v.type
					end
				end
			else
				t[addr] = v.type
			end
		end
		return t
	end
end

local primCache = {}

function component._defaultHandler(ev, addr, type)
	if ev == "component_removed" then
		if not primCache[type] then return end
		if primCache[type].address ~= addr then return end
		primCache[type] = nil
	end
end

setmetatable(component, {__index = function(t, key)
	if type(key) ~= "string" then return end
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
