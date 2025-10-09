-- Requiring files!!!

local process = Kocos.process

---@param modname string
---@param uncached? boolean
---@param env? _G
---@return any, string
function require(modname, uncached, env)
	--- Prob very temporary, will need to be tweaked later
	env = env or process.current.namespace

	if env.package.loaded[modname] ~= nil and not uncached then
		return env.package.loaded[modname], ':loaded:'
	end

	local mod = process.readmod(process.current, modname)

	if mod then
		local f = assert(load(mod.data, "=" .. mod.src))
		local v = f(modname, uncached)
		if v == nil then v = true end
		if not uncached then env.package.loaded[modname] = v end
		return v, ':module:'
	end

	local luaCode = package.searchpath(modname, process.current.env["LUA_PATH"] or env.package.path)

	if luaCode then
		local v = dofile(luaCode, modname, uncached)
		if v == nil then v = true end
		if not uncached then env.package.loaded[modname] = v end
		return v, luaCode
	end

	error("could not find module: " .. modname, 2)
end
