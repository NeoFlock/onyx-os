---@alias Kocos.module fun(req: string, ...): ...

---@type table<string, Kocos.module>
Kocos.mods = {}

Kocos.modulePath = Kocos.getCmdlineStr("MODPATH", "/lib/modules")

---@param mod string
function Kocos.hasModule(mod)
	return Kocos.mods[mod] ~= nil
end

---@param mod string
---@param reload? boolean
---@return boolean, string?
function Kocos.loadModule(mod, reload)
	local path = Kocos.canonicalPath(Kocos.modulePath .. "/" .. mod .. ".lua")
	Kocos.pushProcess(Kocos.kernelProcess)
	local code, err = readfile(path)
	Kocos.popProcess()
	if not code then return false, err end

	if Kocos.hasModule(mod) and not reload then
		return true
	end

	return Kocos.loadModuleCode(mod, code, "=" .. path)
end

---@param mod string
---@param code string
---@param chunkname? string
---@return boolean, string?
function Kocos.loadModuleCode(mod, code, chunkname)
	chunkname = chunkname or ("=" .. mod)
	-- remove old one
	Kocos.removeModule(mod)

	local f, err = load(code, chunkname, nil, _G)
	if not f then return false, err end

	local ok, handler = pcall(f)
	if not ok then return false, tostring(handler) end
	if type(handler) ~= "function" then return false, Kocos.EHWPOISON end
	Kocos.mods[mod] = handler
	-- init after module is defined.
	-- This allows a parititon table driver to re-load partitions for example
	pcall(handler, "dkms_init")
	Kocos.notifyListeners("dkms_added", mod, handler)
	return true
end

function Kocos.removeModule(mod)
	local old = Kocos.mods[mod]
	if old then
		old("dkms_close")
		Kocos.notifyListeners("dkms_removed", mod, old)
	end
	Kocos.mods[mod] = nil
end

function syscalls.dkms_list()
	return table.keysof(Kocos.mods)
end

function syscalls.dkms_loaded(mod)
	return Kocos.hasModule(mod)
end

---@param mod string
---@param reload boolean
function syscalls.dkms_load(mod, reload)
	if Kocos.currentProcess().uid ~= 0 then return false, Kocos.EACCESS end
	return Kocos.loadModule(mod, reload)
end

---@param mod string
---@param code string
---@param file? string
function syscalls.dkms_loadcode(mod, code, file)
	if Kocos.currentProcess().uid ~= 0 then return false, Kocos.EACCESS end
	return Kocos.loadModuleCode(mod, code, file)
end

---@param mod string
---@return boolean, string?
function syscalls.dkms_unload(mod)
	if Kocos.currentProcess().uid ~= 0 then return false, Kocos.EACCESS end
	Kocos.removeModule(mod)
	return true
end

---@param module string
---@param sig string
function syscalls.invokeModule(module, sig, ...)
	return Kocos.mods[module]("dkms_invoke", sig, ...)
end
