-- Default executable formats

-- Header: --!lua (6 bytes)
-- Links in: the runtime
---@param ev "PROC-binfmt"
---@param path string
---@param f Kocos.fs.FileDescriptor
---@param namespace _G
---@return Kocos.process.image?, string?
function Kocos._default_luaExec(ev, path, f, namespace)
	if ev ~= "PROC-binfmt" then return end

	-- TODO: maybe buffer? Weird FS impl might cause weird shit
	local code = Kocos.fs.read(f, 6)
	if code ~= "--!lua" then return end

	while true do
		local data, err = Kocos.fs.read(f, math.huge)
		if err then return nil, err end

		if not data then break end
		code = code .. data
	end

	local init, err = load(code, "=" .. path, nil, namespace)
	if not init then return nil, err end

	---@type Kocos.process.image
	return {
		init = function()
			require(Kocos.args.luaExecRT or "luart")
			local ok, exitcode = xpcall(init, debug.traceback, table.unpack(Kocos.process.current.args))
			if ok then
				if type(exitcode) == "number" then
					Kocos.process.current.exitcode = math.floor(exitcode)
				else
					Kocos.process.current.exitcode = 0
				end
			else
				syscall("write", 2, tostring(exitcode) .. "\n")
				Kocos.process.current.exitcode = 1
			end
		end,
		deps = {Kocos.args.luaExecRTF},
		modules = {
			["_start"] = {
				data = code,
				src = path,
			},
		},
	}
end

Kocos.addDriver(Kocos._default_luaExec)
