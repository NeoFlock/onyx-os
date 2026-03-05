---@alias Kocos.module fun(req: string, ...): ...

---@type table<string, Kocos.module>
Kocos.mods = {}

---@param mod string
function Kocos.hasModule(mod)
	return Kocos.mods[mod] ~= nil
end

---@return boolean, string?
function Kocos.loadModule(mod, code, chunkname)
	-- remove old one
	Kocos.removeModule(mod)

	local f, err = load(code, chunkname, nil, _G)
	if not f then return false, err end

	local ok, handler = pcall(f)
	if not ok then return false, handler end
	if type(handler) ~= "function" then return false, Kocos.EINVAL end
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
