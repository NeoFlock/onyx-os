do
	Kocos.printk(Kocos.L_INFO, "debugger subsystem loaded")

	local event = Kocos.event

	---@param resp string
	local function respond(resp)
		event.push("kgdb_resp", resp)
	end

	---@param fmt string
	local function respondf(fmt, ...)
		respond(string.format(fmt, ...))
	end

	---@type {args: any[], rets?: any[], bt: string, last: table?}?
	_BreakInfo = nil

	function _WRAP_BREAKPOINT(f, name)
		if type(f) == "table" then
			return f.func
		else
			return setmetatable({
				func = f,
			}, {
				__tostring = function() return tostring(f) end,
				__call = function(t, ...)
					_BreakInfo = {args = {...}, bt = debug.traceback(name), last = _BreakInfo}
					respondf("Hit breakpoint %s", name or "unnamed")
					while true do
						local e = Kocos.event.pull(math.huge)
						if e == "kgdb_go" then
							break
						end
					end
					local ret = {f(...)}
					_BreakInfo.rets = ret
					while true do
						local e = Kocos.event.pull(math.huge)
						if e == "kgdb_go" then
							_BreakInfo = _BreakInfo.last
							break
						end
					end
					respondf("Breakpoint %s over", name or "unnamed")
					return table.unpack(ret)
				end,
			})
		end
	end

	---@param ev string
	---@param command string
	event.listen(function(ev, command)
		if ev ~= "kgdb_msg" then return end
		if command == "h" then
			respond([[
h - Display this help page
l <code> - Run Lua code as a statement
x <code> - Run Lua code as an expression (or comma-separated series of expressions) and display results
r - Reboot
R - Shutdown
m - View memory usage
e - View battery status
c - List known device hardware
c <filter> - Like c, except using a fuzzy match identical to component.list()'s
bp <expression> - Wrap a function to trigger a breakpoint. This will replace the function with a table with the __call metamethod.
bt - Print the backtrace saved from the latest breakpoint
ba - Print the arguments saved from the latest breakpoint
br - Print the returns saved from the latest breakpoint
g - Go, aka, run past breakpoint
gc - Go, but only past the call. Still break on return. br will print the returns
]])
			return
		end
		if command:sub(1, 3) == "bp " then
			local name = command:sub(4)
			local expr = string.format("%s = _WRAP_BREAKPOINT(%s, %q)", name, name, name)
			local f, err = load(expr, "=bp")
			if not f then
				respondf("Error: %s", err)
				return
			end
			local ok, err2 = xpcall(f, debug.traceback)
			if err then
				respondf("Error: %s", err2)
				return
			end
			respondf("Toggled breakpoint %s", name)
			return
		end
		if command == "gc" then
			if _BreakInfo.rets then return respond("Call already resumed") end
			Kocos.event.push("kgdb_go")
			return respond("Call skipped")
		end
		if command == "g" then
			if not _BreakInfo.rets then Kocos.event.push("kgdb_go") end
			Kocos.event.push("kgdb_go")
			return
		end
		if command == "bt" then
			if _BreakInfo then
				return respond(_BreakInfo.bt)
			else
				return respond("No backtrace")
			end
		end
		if command == "ba" then
			if not _BreakInfo then return respond("No breakpoint info") end
			local t = {}
			for i=1,#_BreakInfo.args do t[i] = table.serialize(_BreakInfo.args[i]) end
			return respond(table.concat(t, ", "))
		end
		if command == "br" then
			if not _BreakInfo then return respond("No breakpoint info") end
			if not _BreakInfo.rets then return respond("Call still suspended") end
			local t = {}
			for i=1,#_BreakInfo.rets do t[i] = table.serialize(_BreakInfo.rets[i]) end
			return respond(table.concat(t, ", "))
		end
		if command == "c" or command:sub(1, 2) == "c " then
			local filter = nil
			if command:sub(1, 2) == "c " then
				filter = command:sub(3)
			end
			local buf = {}
			for addr, type in component.list(filter) do
				table.insert(buf, addr .. " = " .. type)
			end
			respond(table.concat(buf, "\n"))
			return
		end
		if command == "m" then
			local total = computer.totalMemory()
			local free = computer.freeMemory()
			local used = total - free
			respondf(
				"Total: %s\nUsed: %s (%3.2f%%)\nFree: %s (%3.2f%%)\n",
				string.memformat(total),
				string.memformat(used),
				used / total * 100,
				string.memformat(free),
				free / total * 100
			)
			return
		end
		if command == "e" then
			local total = computer.maxEnergy()
			local remaining = computer.energy()
			respondf("Energy: %d FE / %d FE (%3.2f%%)", remaining, total, remaining / total * 100)
			return
		end
		if command == "r" then
			respond("Rebooting...")
			Kocos.poweroff(true)
			return
		end
		if command == "R" then
			respond("Shutting down...")
			Kocos.poweroff(false)
			return
		end
		if command:sub(1, 2) == "l " then
			local code = command:sub(3)
			local f, err = load(code, "=kgdb")
			if not f then
				respondf("Error: %s", err)
				return
			end
			local ok, err2 = xpcall(f, debug.traceback)
			if not ok then
				respondf("Error: %s", err2)
				return
			end
			respondf("OK")
			return
		end
		if command == "nproc" then
			local nproc = 0
			for pid in pairs(Kocos.process.allProcs) do
				nproc = nproc + 1
			end
			return respond(tostring(nproc))
		end
		if command == "pids" then
			local pids = {}
			for pid in pairs(Kocos.process.allProcs) do
				table.insert(pids, pid)
			end
			return respond(table.concat(pids, " "))
		end
		if command:sub(1, 2) == "x " then
			local code = command:sub(3)
			local f, err = load("return " .. code, "=kgdb")
			if not f then
				respondf("Error: %s", err)
				return
			end
			local t = {xpcall(f, debug.traceback)}
			if not t[1] then
				respondf("Error: %s", t[2])
				return
			end
			local strs = {}
			for i=2,#t do strs[i-1] = table.serialize(t[i]) end
			if #strs == 0 then strs={"nil"} end
			respond(table.concat(strs, ", "))
			return
		end
	end)

	local kgdb = Kocos.args.debugger

	if kgdb then
		local kgdbType = component.type(kgdb) or "unknown"
		Kocos.printk(Kocos.L_INFO, "Using debugger: " .. kgdb .. " (" .. kgdbType .. ")")
		if kgdbType == "ocelot" then
			event.listen(function(ev, hw, msg)
				if ev == "ocelot_message" and hw == kgdb then
					event.push("kgdb_msg", msg)
				end
				if ev == "kgdb_resp" then
					component.invoke(kgdb, "log", "[KGDB] " .. hw)
				end
			end)
		elseif kgdbType == "tunnel" then
			-- TODO: kgdb over tunnels
		elseif kgdbType == "modem" then
			-- TODO: kgdb over modems
		end

		respond("debugger connection established")
	else
		Kocos.printk(Kocos.L_INFO, "No debugger selected")
	end
end
