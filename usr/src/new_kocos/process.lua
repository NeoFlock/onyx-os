---@class Kocos.procmod
---@field data string
---@field src string

---@class Kocos.proclib
---@field modules table<string, Kocos.procmod>
---@field deps Kocos.proclib[]

---@class Kocos.vmproc
---@field state "running"|"dying"|"dead"|"finished"
---@field pid integer
---@field uid integer
---@field gid integer
---@field argv string[]
---@field env table<string, string>
---@field parent? Kocos.vmproc
---@field children table<integer, Kocos.vmproc>
---@field coro? thread
---@field boundKmod string[]
---@field blockUntil (fun(): boolean)[]
---@field modules table<string, Kocos.procmod>
---@field libs Kocos.proclib[]
---@field stopped boolean
---@field cwd string
---@field root string
---@field exe string
---@field exitcode integer
---@field debugger? Kocos.vmproc
---@field daemon? string
---@field ev_listener? function
---@field desiredExecTime? number
---@field signalHandlers table<string, function>
---@field proclocal table
---@field fds table<integer, Kocos.descriptor>

---@class Kocos.daemon
---@field proc Kocos.vmproc
---@field callback fun(cpid: integer, ...): ...

---@type table<integer, Kocos.vmproc>
Kocos.processes = {}

---@type Kocos.vmproc[]
Kocos.procStack = {}

-- Kernel process
Kocos.processes[0] = {
	state = "running",
	pid = 0,
	uid = 0,
	gid = 0,
	argv = {},
	env = {},
	parent = nil,
	children = {},
	-- pretend its already gone
	coro = nil,
	boundKmod = {},
	blockUntil = {},
	modules = {},
	libs = {},
	stopped = false,
	cwd = "/",
	root = "/",
	exe = Kocos.getCmdlineStr("KPATH", "/boot/vmkocos"),
	exitcode = 0,
	debugger = nil,
	daemon = nil,
	ev_listener = nil,
	desiredExecTime = nil,
	signalHandlers = {},
	proclocal = {},
	fds = {},
}

Kocos.procStack[1] = Kocos.processes[0]

Kocos.defaultExecTime = Kocos.getCmdlineNum("EXEC_TIME", 1)

---@type table<string, Kocos.daemon>
Kocos.daemons = {}

local npid = 1

function Kocos.currentProcess()
	return Kocos.procStack[#Kocos.procStack]
end

---@param proc Kocos.vmproc
function Kocos.pushProcess(proc)
	table.insert(Kocos.procStack, proc)
end

function Kocos.popProcess()
	assert(#Kocos.procStack > 1, "out of processes")
	Kocos.procStack[#Kocos.procStack] = nil
end

---@param proc Kocos.vmproc
---@param f function
---@param msgh function
function Kocos.procXCall(proc, f, msgh, ...)
	Kocos.pushProcess(proc)
	local t = {xpcall(f, msgh, ...)}
	Kocos.popProcess()
	return t
end

---@param proc Kocos.vmproc
---@param f function
function Kocos.procCall(proc, f, ...)
	Kocos.pushProcess(proc)
	local t = {pcall(f, ...)}
	Kocos.popProcess()
	return t
end

---@param proc Kocos.vmproc
---@param exit integer
function Kocos.terminateProcess(proc, exit)
	if proc.state ~= "running" then return end
	proc.state = "finished"
	proc.exitcode = exit
	if proc.pid == 0 then
		Kocos.panickf("KERNEL EXITED: %d", exit)
		return
	end
	if proc.pid == 1 then
		Kocos.panickf("INIT EXITED: %d", exit)
		return
	end
	if proc.parent then
		Kocos.sendSignal(proc.parent, "SIGCHLD", proc.pid, exit)
	end
	Kocos.sendSignal(proc, "SIGABRT")

	-- TODO: cleanup
	for _, mod in ipairs(proc.boundKmod) do
		Kocos.removeModule(mod)
	end

	for _, f in pairs(proc.fds) do
		Kocos.closeDescriptor(f)
	end
	proc.fds = {}

	if proc.daemon then
		Kocos.daemons[proc.daemon] = nil
	end

	if Kocos.currentProcess() == proc then
		coroutine.yield()
		return
	end
end

---@param proc Kocos.vmproc
---@param sig string
function Kocos.sendSignal(proc, sig, ...)
	if sig == "SIGSTOP" then
		proc.stopped = true
		if Kocos.currentProcess() == proc then coroutine.yield() end
		return
	end
	if sig == "SIGKILL" then
		Kocos.terminateProcess(proc, 1)
		return
	end
	if sig == "SIGCONT" then
		proc.stopped = false
		return
	end
	if proc.signalHandlers[sig] then
		local t = Kocos.procCall(proc, proc.signalHandlers[sig], ...)
		if not t[1] then
			Kocos.printkf(Kocos.L_WARN, "pid %d: error in handler for signal %s: %s", proc.pid, sig, t[2])
		end
	else
		-- default handlers
		if sig == "SIGINT" then
			Kocos.terminateProcess(proc, 1)
			return
		end
		if sig == "SIGPIPE" then
			Kocos.terminateProcess(proc, 1)
			return
		end
		if sig == "SIGUSR1" then
			Kocos.terminateProcess(proc, 1)
			return
		end
		if sig == "SIGUSR2" then
			Kocos.terminateProcess(proc, 1)
			return
		end
		if sig == "SIGTRAP" then
			local err = ...
			if type(err) == "string" then
				Kocos.procCall(proc, syscall, "write", 2, err .. "\n")
			end
			Kocos.terminateProcess(proc, 1)
			return
		end
		if sig == "SIGTERM" then
			Kocos.terminateProcess(proc, 1)
			return
		end
	end

	-- Unmodifiable behavior
	if sig == "SIGABRT" then
		Kocos.terminateProcess(proc, 1)
		return
	end
end

---@param proc Kocos.vmproc
function Kocos.closeProcess(proc)
	-- nice try
	if proc.state == "dying" then return end
	if not Kocos.processes[proc.pid] then return end
	Kocos.terminateProcess(proc, 1)
	proc.state = "dying"

	local allKids = {}
	for _, child in pairs(proc.children) do table.insert(allKids, child) end
	for _, child in ipairs(allKids) do Kocos.closeProcess(child) end

	if proc.parent then
		proc.parent.children[proc.pid] = nil
	end

	Kocos.processes[proc.pid] = nil -- rip
	proc.state = "dead"
end

---@param lib Kocos.process.sharedLib
---@param module string
---@param refs? table
---@return Kocos.process.module?
function Kocos.libreadmod(lib, module, refs)
	refs = refs or {}
	-- in case of cyclical bullshit dependencies
	if refs[lib] then return end
	refs[lib] = true

	---@type Kocos.process.module?
	local mod = lib.modules[module]
	if mod then return mod end

	for _, dep in ipairs(lib.deps) do
		mod = Kocos.libreadmod(dep, module, refs)
		if mod then return mod end
	end
end

---@param proc Kocos.process
---@param module string
---@return Kocos.process.module?
function Kocos.readmod(proc, module)
	---@type Kocos.process.module?
	local mod = proc.modules[module]
	if mod then return mod end

	local refs = {}

	for _, dep in ipairs(proc.deps) do
		mod = Kocos.libreadmod(dep, module, refs)
		if mod then return mod end
	end
end

---@class Kocos.procimage
---@field init function
---@field modules table<string, Kocos.procmod>
---@field deps string[]

---@param proc Kocos.vmproc
function Kocos.resumeProcess(proc)
	if proc.state ~= "running" then return end
	if proc.stopped then return end
	if not proc.coro then return end
	if coroutine.status(proc.coro) ~= "running" then return end
	Kocos.pushProcess(proc)
	local ok, err = coroutine.resume(proc.coro)
	Kocos.popProcess()

	if not ok then
		Kocos.printkf(Kocos.L_ERROR, "Process %d crashed: %s", proc.pid, err)
		Kocos.sendSignal(proc, "SIGTRAP", debug.traceback(proc.coro, err))
		return
	end

	-- killed
	if proc.state ~= "running" then return end

	-- coroutine gone
	if coroutine.status(proc.coro) == "dead" then
		local exit = err
		if type(exit) ~= "number" then exit = 0 end
		Kocos.terminateProcess(proc, exit)
	end
end

function Kocos.tickProcesses()
	for _, proc in pairs(Kocos.processes) do
		Kocos.resumeProcess(proc)
	end
end

---@param level? integer
function syscalls.getpid(level)
	level = level or 0

	local proc = Kocos.procStack[#Kocos.procStack - level]
	if not proc then return nil, Kocos.ESRCH end
	return proc.pid
end
