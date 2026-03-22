local sysyieldobj = {}
Kocos.coroThread = coroutine.running()

function Kocos.sysyield()
	if coroutine.running() == Kocos.coroThread then return end
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
---@field namespace _G
---@field resumeTo? Kocos.vmproc[]

---@class Kocos.daemon
---@field proc Kocos.vmproc
---@field callback fun(cpid: integer, ...): ...

---@type table<integer, Kocos.vmproc>
Kocos.processes = {}

---@type Kocos.vmproc[]
Kocos.procStack = {}

-- Kernel process
Kocos.kernelProcess = {
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
	namespace = _G,
}

Kocos.processes[0] = Kocos.kernelProcess
Kocos.procStack[1] = Kocos.kernelProcess

Kocos.defaultExecTime = Kocos.getCmdlineNum("EXEC_TIME", 0.1)

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
---@return integer
function Kocos.availableDescriptorFor(proc)
	local fd = 0
	while proc.fds[fd] do fd = fd + 1 end
	return fd
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

		-- forbidden.
		-- This prevends pkilling the kernel or init.
		if proc.pid == 0 or proc.pid == 1 then return end

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
				Kocos.printkf(Kocos.L_WARN, "pid %d crashed: %s", proc.pid, err)
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
	if proc.state == "dying" or proc.state == "dead" then return end
	if not Kocos.processes[proc.pid] then return end
	if proc.state == "running" then Kocos.terminateProcess(proc, 1) end
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

---@param path string
---@param data string
---@param namespace _G
---@param env table<string, string>
---@return Kocos.procimage?, string?
--- Parse the contents of an executable file
function Kocos.parseExecutable(path, data, namespace, env)
	if data:sub(1, 2) == "#!" then
		-- shebang
		local lineTerm = string.find(data, "\n")
		if not lineTerm then return nil, Kocos.ENOEXEC end

		local args = string.split(string.sub(data, 3, lineTerm-1), " ")
		local cmd = table.remove(args, 1)
		if not cmd then return nil, Kocos.ENOEXEC end
		args[0] = cmd
		table.insert(args, path)
		return {
			init = function()
				local proc = Kocos.currentProcess()
				local ok, err = syscall("exec", cmd, args)
				if ok then
					-- exec returned???
					Kocos.terminateProcess(proc, 1)
				else
					-- load error
					Kocos.sendSignal(proc, "SIGTRAP", err)
				end
			end,
			modules = {},
		}
	end
	for _, mod in pairs(Kocos.mods) do
		local img, err = mod("PROC-binfmt", path, data, namespace, env)
		if img or err then return img, err end
	end
	return nil, Kocos.ENOEXEC
end

---@param proc Kocos.vmproc
function Kocos.resumeProcess(proc)
	-- recursive resume is illegal!
	if #Kocos.procStack ~= 1 then error("recursive resume") end
	if proc.state ~= "running" then return end
	if proc.stopped then return end
	if not proc.coro then return end
	if coroutine.status(proc.coro) ~= "suspended" then return end
	Kocos.procStack = proc.resumeTo or {Kocos.kernelProcess, proc}
	Kocos.execDeadline = computer.uptime() + Kocos.defaultExecTime
	local ok, err = Kocos.resume(proc.coro)
	proc.resumeTo = Kocos.procStack
	Kocos.procStack = {Kocos.kernelProcess}

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

---@param proc Kocos.vmproc
---@param victim Kocos.vmproc
function Kocos.isMasterProcessOf(proc, victim)
	if proc.uid == 0 then return true end -- root is master of all
	if proc == victim then return true end
	if victim.parent then return Kocos.isMasterProcessOf(proc, victim.parent) end
	return false
end

function Kocos.tickProcesses()
	for _, proc in pairs(Kocos.processes) do
		Kocos.resumeProcess(proc)
	end
end

---@param code? integer
function syscalls.exit(code)
	code = code or 0
	Kocos.terminateProcess(Kocos.currentProcess(), code)
	Kocos.sysyield()
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

---@param uid integer
---@param pid? integer
---@return boolean, string?
function syscalls.setuid(uid, pid)
	local proc = Kocos.currentProcess()
	if proc.uid ~= 0 then return false, Kocos.EACCESS end
	pid = pid or proc.pid
	local target = Kocos.processes[pid]
	if not target then return false, Kocos.ESRCH end
	target.uid = uid
	return true
end

---@param gid integer
---@param pid? integer
---@return boolean, string?
function syscalls.setgid(gid, pid)
	local proc = Kocos.currentProcess()
	if proc.uid ~= 0 then return false, Kocos.EACCESS end
	pid = pid or proc.pid
	local target = Kocos.processes[pid]
	if not target then return false, Kocos.ESRCH end
	target.gid = gid
	return true
end

function syscalls.getuid()
	return Kocos.currentProcess().uid
end

function syscalls.getgid()
	return Kocos.currentProcess().gid
end

function syscalls.environ()
	return Kocos.currentProcess().env
end

function syscalls.argv()
	return Kocos.currentProcess().argv
end

---@param time number
function syscalls.sleep(time)
	if type(time) ~= "number" then return nil, Kocos.EINVAL end
	local start = computer.uptime()
	local deadline = start + time
	while computer.uptime() < deadline do
		Kocos.sysyield()
	end
	-- Returns exact amount waited
	return computer.uptime() - start
end

---@class Kocos.vmpinfo
---@field argv? string[]
---@field environ? table<string, string>
---@field uid? integer
---@field gid? integer
---@field parent? integer
---@field kmodules? string[]
---@field daemon? string
---@field tracer? integer
---@field exitcode? integer
---@field cwd? string
---@field exe? string
---@field root? string
---@field namespace? _G
---@field children? integer[]
---@field signals? integer[]

---@param pid integer
---@vararg "args"|"env"|"uid"|"gid"|"parent"|"tree"|"state"|"namespace"|"signals"
---@return Kocos.vmpinfo?, string?
function syscalls.getprocinfo(pid, ...)
	local proc = Kocos.currentProcess()
	local target = Kocos.processes[pid]
	if not target then return nil, Kocos.ESRCH end
	local isTrusted = Kocos.isMasterProcessOf(proc, target)
	---@type Kocos.vmpinfo
	local info = {}
	local vlen = select("#", ...)
	for i=1, vlen do
		local v = select(i, ...)
		if v == "args" then
			info.argv = table.copy(target.argv)
		elseif v == "env" then
			info.environ = table.copy(target.env)
		elseif v == "uid" then
			info.uid = target.uid
		elseif v == "gid" then
			info.gid = target.gid
		elseif v == "parent" then
			if target.parent then info.parent = target.parent.pid end
		elseif v == "tree" then
			if target.parent then info.parent = target.parent.pid end
			info.children = table.keysof(target.children)
		elseif v == "state" then
			if target.parent then info.parent = target.parent.pid end
			if target.debugger then info.tracer = target.debugger.pid end
			info.kmodules = table.copy(target.boundKmod)
			info.exitcode = target.exitcode
			info.exe = target.exe
			info.cwd = target.cwd
			info.root = target.root
		elseif v == "namespace" then
			if isTrusted then info.namespace = target.namespace end
		elseif v == "signals" then
			info.signals = table.keysof(info.signals)
		end
	end
	return info
end

---@param f function
---@return integer?, string?
function syscalls.fork(f)
	if type(f) ~= "function" then return nil, Kocos.EINVAL end

	local proc = Kocos.currentProcess()

	---@type Kocos.vmproc
	local child = {
		argv = table.copy(proc.argv),
		env = table.copy(proc.env),
		signalHandlers = {},
		boundKmod = {},
		modules = table.copy(proc.modules),
		pid = npid,
		children = {},
		parent = proc,
		cwd = proc.cwd,
		root = proc.root,
		exe = proc.exe,
		fds = {},
		exitcode = proc.exitcode,
		uid = proc.uid,
		gid = proc.gid,
		namespace = proc.namespace,
		proclocal = {},
		state = "running",
		stopped = false,
		coro = coroutine.create(f),
		daemon = nil,
		debugger = nil,
		desiredExecTime = nil,
		ev_listener = nil,
	}

	-- Copy all the damn file descriptors
	for fd, h in pairs(proc.fds) do
		child.fds[fd] = h
		h.rc = h.rc + 1
	end

	proc.children[child.pid] = child
	Kocos.processes[child.pid] = child
	npid = npid + 1
	return child.pid
end

---@param path string
---@param argv? string[]
---@param env? table<string, string>
---@param namespace? _G
---@return boolean, string?
function syscalls.exec(path, argv, env, namespace)
	local proc = Kocos.currentProcess()
	argv = argv or {}
	env = env or proc.env
	namespace = namespace or proc.namespace
	argv[0] = argv[0] or path

	local stat, err = syscalls.stat(path)
	if not stat then return nil, err end

	if not Kocos.permCheck(stat.perms, Kocos.P_EXECUTABLE, proc.uid == stat.uid, proc.gid == stat.gid) then
		return false, Kocos.EACCESS
	end

	local code, err = readfile(path)
	if not code then return false, err end
	local truepath = Kocos.realPathFor(proc, path)

	local img, err = Kocos.parseExecutable(truepath, code, namespace, env)
	if not img then return false, err end

	local toClose = {}

	for fd, handle in pairs(proc.fds) do
		if (handle.flags & Kocos.O_CLOEXEC) ~= 0 then
			table.insert(toClose, fd)
		end
	end

	for _, fd in ipairs(toClose) do syscalls.close(fd) end

	proc.argv = table.copy(argv)
	proc.env = table.copy(env)
	proc.namespace = namespace
	proc.modules = img.modules
	proc.coro = coroutine.create(img.init)

	-- delete anything else that might've been there, because it's invalid now
	proc.resumeTo = {Kocos.kernelProcess, proc}
	Kocos.sysyield()
	return true
end

function syscalls.signal(signal, handler)
	local proc = Kocos.currentProcess()
	proc.signalHandlers[signal] = handler
	return true
end

function syscalls.registerDaemon(daemon, handler)
	if Kocos.daemons[daemon] then
		return nil, Kocos.EADDRINUSE
	end
	local proc = Kocos.currentProcess()
	if proc.daemon then return nil, Kocos.EADDRINUSE end
	Kocos.daemons[daemon] = {
		proc = proc,
		callback = handler,
	}
	return true
end

---@param daemon string
---@return integer?, string?
function syscalls.getDaemonPid(daemon)
	local d = Kocos.daemons[daemon]
	if not d then return nil, Kocos.ESRCH end
	return d.proc.pid
end

---@return string[]
function syscalls.listDaemons()
	local daemons = {}
	for addr in pairs(Kocos.daemons) do
		table.insert(daemons, addr)
	end
	return daemons
end

---@param daemon string
---@return ...
function syscalls.invokeDaemon(daemon, ...)
	local proc = Kocos.currentProcess()

	local d = Kocos.daemons[daemon]
	if not d then return nil, Kocos.ESRCH end
	local t = Kocos.procCall(d.proc, d.callback, proc.pid, ...)
	if t[1] then
		return table.unpack(t, 2)
	else
		return nil, tostring(t[2])
	end
end

function syscalls.waitpid(pid)
	local proc = Kocos.processes[pid]
	if not proc then return 0 end
	while proc.state == "running" do
		Kocos.sysyield()
	end
	local exit = proc.exitcode
	Kocos.closeProcess(proc)
	return exit
end

---@param f? function
function syscalls.mklistener(f)
	local proc = Kocos.currentProcess()
	if proc.uid ~= 0 then
		return nil, Kocos.EACCESS
	end
	if proc.ev_listener then
		Kocos.forget(proc.ev_listener)
		proc.ev_listener = nil
	end
	if f then
		local function wrapped(...)
			Kocos.procCall(proc, f, ...)
		end
		proc.ev_listener = wrapped
		Kocos.listen(wrapped)
	end
	return true
end

function syscalls.mountDev(path, devAddr, cmdline)
	local l, err = syscalls.list(path)
	if not l then return false, err end
	if #l > 0 then return false, Kocos.ENOTEMPTY end

	if Kocos.isMounted(devAddr) then
		return false, Kocos.EADDRINUSE
	end

	if not component.type(devAddr) then
		return false, Kocos.ENODEV
	end

	local proc = Kocos.currentProcess()
	if proc.uid ~= 0 then return end
	local truepath = Kocos.realPathFor(proc, path)
	local mntpath = truepath:sub(2)

	if Kocos.mounts[mntpath] then
		return false, Kocos.EADDRNOTAVAIL
	end

	local dev = component.proxy(devAddr)
	local mnt, err = Kocos.mountFor(dev, cmdline)
	if not mnt then return false, err end

	Kocos.mounts[mntpath] = mnt
	return true
end

syscalls.sysyield = Kocos.sysyield

function syscalls.kill(pid, signal, ...)
	local cur = Kocos.currentProcess()
	local target = Kocos.processes[pid]
	if not target then return nil, Kocos.ESRCH end
	-- signals that are just not sendable even by root,
	-- cuz their meaning would be violated
	if signal == "SIGTRAP" then return nil, Kocos.EPERM end
	if signal == "SIGCHLD" then return nil, Kocos.EPERM end
	if signal == "SIGABRT" then return nil, Kocos.EPERM end
	local allowed = cur.uid == 0 or cur.uid == target.uid
	if not allowed then
		return nil, Kocos.EACCESS
	end
	Kocos.sendSignal(target, signal, ...)
	return true
end

---@param modname string
---@param module Kocos.module
---@return boolean, string?
function syscalls.registerModule(modname, module)
	if not string.startswith(modname, "DAEMON_") then
		modname = "DAEMON_" .. modname
	end
	local proc = Kocos.currentProcess()
	if proc.uid ~= 0 then return false, Kocos.EACCESS end
	if Kocos.mods[modname] then return false, Kocos.EADDRINUSE end
	table.insert(proc.boundKmod, modname)
	Kocos.mods[modname] = function(...)
		local t = Kocos.procCall(proc, module, ...)
		if t[1] then
			return table.unpack(t, 2)
		else
			return nil, t[2]
		end
	end
	return true
end

Kocos.rawLoad = load
function load(chunk, chunkname, mode, env)
	local proc = Kocos.currentProcess()
	return Kocos.rawLoad(chunk, chunkname, mode, env or proc.namespace)
end

Kocos.loadModuleCode("luaexec", _EMBED_MIN("lib/modules/luaexec.lua"))
