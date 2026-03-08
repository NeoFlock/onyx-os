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

	if Kocos.hasModule(mod) then
		if reload then
			Kocos.removeModule(mod)
		else
			return true
		end
	end

	return Kocos.loadModuleCode(mod, code, "=" .. path)
end

---@return boolean, string?
function Kocos.loadModuleCode(mod, code, chunkname)
	-- remove old one
	Kocos.removeModule(mod)

	local f, err = load(code, chunkname, nil, _G)
	if not f then return false, err end

	local ok, handler = pcall(f)
	if not ok then return false, handler end
	if type(handler) ~= "function" then return false, Kocos.EHWPOISON end
	Kocos.mods[code] = handler
	return true
end

function Kocos.removeModule(mod)
	local old = Kocos.mods[mod]
	if old then
		old("dkms_close")
	end
	Kocos.mods[mod] = nil
end
