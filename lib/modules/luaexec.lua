---@param req string
---@param path string
---@param data string
---@param namespace _G
---@param env table<string, string>
return function(req, path, data, namespace, env)
	if req ~= "PROC-binfmt" then return end
	if data:sub(1, 6) ~= "--!lua" then return end

	local init, err = Kocos.rawLoad(data, "=" .. path, nil, namespace)
	if not init then return nil, err end

	local luaRT = env["LUA_RT"] or Kocos.getCmdlineStr("LUA_RT", "luart")

	---@type Kocos.procimage
	return {
		init = function()
			require(luaRT)
			local proc = Kocos.currentProcess()
			local ok, exitcode = xpcall(init, debug.traceback, table.unpack(proc.argv))
			if ok then
				if type(exitcode) == "number" then
					Kocos.terminateProcess(proc, exitcode)
				else
					Kocos.terminateProcess(proc, 0)
				end
			else
				if proc.pid == 1 then
					Kocos.panickf("Init crashed: %s", exitcode)
				end
				Kocos.sendSignal(proc, "SIGTRAP", exitcode)
				Kocos.terminateProcess(proc, 1)
			end
		end,
		modules = {},
	}
end
