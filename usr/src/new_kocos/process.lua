local sysyieldobj = {}

function Kocos.sysyield()
	coroutine.yield(sysyieldobj)
end

Kocos.resume = coroutine.resume

-- Magic
coroutine.resume = function(co, ...)
	while true do
		local t = {Kocos.resume(co, ...)}
		if t[1] and sysyieldobj == t[2] then
			Kocos.sysyield()
		else
			return table.unpack(t)
		end
	end
end

---@class Kocos.procmod
---@field data string
---@field src string

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
---@field sleepUntil number

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
	sleepUntil = 0,
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
	if proc.ev_listener then
		Kocos.forget(proc.ev_listener)
	end

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
		Kocos.sysyield()
		return
	end
end

---@param proc Kocos.vmproc
---@param sig string
function Kocos.sendSignal(proc, sig, ...)
	-- forbidden.
	-- This prevends pkilling the kernel or init.
	if proc.pid == 0 or proc.pid == 1 then return end
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

	-- Reparent children
	while true do
		local cpid, child = next(proc.children)
		if not cpid or not child then break end

		proc.children[cpid] = nil -- remove child
		child.parent = Kocos.processes[1] or Kocos.processes[0]
		child.parent.children[cpid] = child
	end

	if proc.parent then
		proc.parent.children[proc.pid] = nil
	end

	Kocos.processes[proc.pid] = nil -- rip
	proc.state = "dead"
end

---@class Kocos.procimage
---@field init function
---@field modules table<string, Kocos.procmod>

---@param proc Kocos.vmproc
function Kocos.resumeProcess(proc)
	if proc.state ~= "running" then return end
	if proc.stopped then return end
	if not proc.coro then return end
	if coroutine.status(proc.coro) ~= "running" then return end
	Kocos.pushProcess(proc)
	Kocos.execDeadline = computer.uptime() + 0.1
	local ok, err = Kocos.resume(proc.coro)
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

function syscalls.proclocal()
	return Kocos.currentProcess().proclocal
end

---@return integer[]
function syscalls.getprocs()
	local pids = {}
	for pid in pairs(Kocos.processes) do
		table.insert(pids, pid)
	end
	return pids
end

function syscalls.getuid()
	return Kocos.currentProcess().uid
end

function syscalls.getgid()
	return Kocos.currentProcess().gid
end
