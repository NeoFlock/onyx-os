-- Default executable formats

-- Header: --!lua (6 bytes)
-- Links in: the runtime
---@param ev "PROC-binfmt"
---@param path string
---@param data string
---@param namespace _G
---@return Kocos.process.image?, string?
function Kocos._default_luaExec(ev, path, data, namespace)
	if ev ~= "PROC-binfmt" then return end

	if data:sub(1, 6) ~= "--!lua" then return end

	local init, err = load(data, "=" .. path, nil, namespace)
	if not init then return nil, err end

	---@type Kocos.process.image
	return {
		init = function()
			require(Kocos.args.luaExecRT or "luart")
			local ok, exitcode = xpcall(init, debug.traceback, table.unpack(Kocos.process.current.args))
			if ok then
				if type(exitcode) == "number" then
					Kocos.process.terminate(Kocos.process.current, exitcode)
				else
					Kocos.process.terminate(Kocos.process.current, 0)
				end
			else
				Kocos.process.raise(Kocos.process.current, "SIGTRAP", exitcode)
			end
		end,
		deps = {Kocos.args.luaExecRTF},
		modules = {},
	}
end

-- Header: #! (2 bytes)
-- Links in: nothing
---@param ev "PROC-binfmt"
---@param path string
---@param data string
---@param namespace _G
---@return Kocos.process.image?, string?
function Kocos._default_shebang(ev, path, data, namespace)
	if ev ~= "PROC-binfmt" then return end
	if data:sub(1, 2) ~= "#!" then return end

	local nl = string.find(data, "\n")
	if nl then
		data = string.sub(data, 1, nl-1)
	end

	local cmd = data:sub(3)
	local args = string.split(cmd, " ")
	cmd = table.remove(args, 1)
	table.insert(args, path)
	return {
		init = function()
			local ok, err = syscall("exec", cmd, args)
			if ok then
				Kocos.process.terminate(Kocos.process.current, 0)
			else
				Kocos.process.raise(Kocos.process.current, "SIGTRAP", err)
			end
		end,
		deps = {},
		modules = {},
	}
end

Kocos.addDriver(Kocos._default_luaExec)
Kocos.addDriver(Kocos._default_shebang)
