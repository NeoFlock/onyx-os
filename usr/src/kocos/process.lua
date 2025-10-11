local process = {}

process.npid = 0

-- File descriptors / resources with special meanings
--- The standard input stream
process.STDIN = 0
--- The standard output stream
process.STDOUT = 1
--- The standard error stream
process.STDERR = 2
--- The standard terminal stream
process.STDTERM = 3

---@class Kocos.process.module
---@field data string
---@field src string

---@class Kocos.process.sharedLib
---@field modules table<string, Kocos.process.module>
---@field deps Kocos.process.sharedLib[]

---@class Kocos.resource
---@field refc integer
---@field opts integer
---@field file? Kocos.fs.FileDescriptor
---@field socket? Kocos.net.socket

---@alias Kocos.process.condition fun(): boolean

---@class Kocos.process
---@field state "running"|"dying"|"dead"|"finished"
---@field pid integer
---@field uid integer
---@field gid integer
---@field euid integer
---@field egid integer
---@field thread thread
---@field namespace _G
---@field args string[]
---@field blockUntil Kocos.process.condition[]
---@field env table<string, string>
---@field modules table<string, Kocos.process.module>
---@field deps Kocos.process.sharedLib[]
---@field driver? function
---@field fds table<integer, Kocos.resource>
---@field signals table<string, function>
---@field children table<integer, Kocos.process>
---@field parent? Kocos.process
---@field stopped boolean
---@field cwd string
---@field exe? string
---@field exitcode integer
---@field tracer? Kocos.process
---@field daemon? string
---@field ev_listener? function

---@type table<integer, Kocos.process>
process.allProcs = {}

---@class Kocos.process.daemon
---@field proc Kocos.process
---@field callback fun(cpid: integer, ...): ...

---@type table<string, Kocos.process.daemon>
process.daemons = {}

function process.nextPid()
	if Kocos.args.useExtremelySecurePidGeneration then
		local pid = math.random(1, 2^32-1)
		while process.allProcs[pid] do
			pid = math.random(1, 2^32-1)
		end
		return pid
	end
	local pid = process.npid
	process.npid = process.npid + 1
	return pid
end

---@param thread thread
---@param namespace _G
---@param uid integer
---@param gid integer
---@return Kocos.process
function process.create(thread, namespace, uid, gid)
	local pid = process.nextPid()

	---@type Kocos.process
	local proc = {
		pid = pid,
		uid = uid,
		gid = gid,
		euid = uid,
		egid = gid,
		thread = thread,
		namespace = namespace,
		args = {},
		env = {},
		modules = {},
		deps = {},
		fds = {},
		signals = {},
		children = {},
		stopped = false,
		state = "running",
		cwd = "/",
		exitcode = 0,
		blockUntil = {},
	}


	process.allProcs[pid] = proc

	return proc
end

---@param proc Kocos.process
---@param func function
---@return Kocos.process
function process.fork(proc, func)
	local forked = process.create(coroutine.create(func), proc.namespace, proc.uid, proc.gid)
	forked.euid = proc.euid
	forked.egid = proc.egid
	forked.args = table.copy(proc.args)
	forked.env = table.copy(proc.env)
	forked.blockUntil = table.copy(proc.blockUntil)
	-- no table.copy cuz they're immutable anyways
	forked.modules = proc.modules
	forked.deps = proc.deps
	-- driver is not copied over
	-- resources are retained
	for fd, res in pairs(proc.fds) do
		forked.fds[fd] = res
		res.refc = res.refc + 1
	end
	forked.stopped = proc.stopped
	forked.cwd = proc.cwd
	forked.exitcode = proc.exitcode
	forked.tracer = proc.tracer
	forked.parent = proc
	forked.exe = proc.exe
	proc.children[forked.pid] = forked
	return forked
end

---@param proc Kocos.process
---@param parent Kocos.process
function process.isDecendantOf(proc, parent)
	while parent do
		if proc.parent == parent then return true end
		parent = parent.parent
	end
	return false
end

process.SIGABRT = "SIGABRT" -- process closed
process.SIGALRM = "SIGALRM" -- alarm
process.SIGTERM = "SIGTERM" -- terminate
process.SIGKILL = "SIGKILL" -- die
process.SIGUSR1 = "SIGUSR1" -- user specified
process.SIGUSR2 = "SIGUSR2" -- user specified 2
process.SIGCHLD = "SIGCHLD" -- child died
process.SIGINT = "SIGINT" -- interrupted
process.SIGPIPE = "SIGPIPE" -- the pipe is gone
process.SIGQUIT = "SIGQUIT" -- quit process
process.SIGSTOP = "SIGSTOP" -- stop process
process.SIGTSTP = "SIGTSTP" -- stop process too
process.SIGSYS = "SIGSYS" -- bad syscall
process.SIGWINCH = "SIGWINCH" -- window changed
process.SIGURG = "SIGURG" -- urgent stuff
process.SIGTRAP = "SIGTRAP" -- a trap
process.SIGCONT = "SIGCONT" -- continue
process.SIGSYSC = "SIGSYSC" -- when tracing, traced process did a system call
process.SIGSYSR = "SIGSYSR" -- when tracing, traced process did a system return
process.SIGPWR = "SIGPWR" -- shutdown or reboot

---@param proc Kocos.process
---@param signal string
function process.raise(proc, signal, ...)
	if not proc then return end
	if signal == process.SIGSTOP then
		proc.stopped = true
		if process.current == proc then coroutine.yield() end
		return
	end
	if signal == process.SIGKILL then
		process.terminate(proc)
		return
	end
	if signal == process.SIGCONT then
		proc.stopped = false
		return
	end
	if proc.stopped then return end -- nope
	if proc.signals[signal] then
		-- Handler!!!!!!!
		process.pcall(proc, proc.signals[signal], ...)
		-- no return to allow unmodifiable behavior
	else
		-- Default handlers
		if signal == process.SIGINT then
			process.terminate(proc)
			return
		end
		if signal == process.SIGPIPE then
			process.terminate(proc)
			return
		end
		if signal == process.SIGUSR1 then
			process.terminate(proc)
			return
		end
		if signal == process.SIGUSR2 then
			process.terminate(proc)
			return
		end
		if signal == process.SIGTRAP then
			local err = ...
			if type(err) == "string" then
				process.pcall(proc, syscall, "write", process.STDERR, err .. "\n")
			end
			process.terminate(proc)
			return
		end
		if signal == process.SIGTERM then
			process.terminate(proc)
			return
		end
	end

	-- Unmodifiable behavior
	if signal == process.SIGABRT then
		process.terminate(proc, 1)
		return
	end
end

---@param proc Kocos.process
---@param f fun(...): ...
---@param msgh fun(s: any): any
---@return boolean, ...
function process.xpcall(proc, f, msgh, ...)
	local oldCurProc = process.current
	process.current = proc
	-- OOM problem!!!!
	local t = {xpcall(f, msgh, ...)}
	process.current = oldCurProc
	return table.unpack(t)
end

---@param proc Kocos.process
---@param f fun(...): ...
---@return boolean, ...
function process.pcall(proc, f, ...)
	return process.xpcall(proc, f, tostring, ...)
end

---@param res Kocos.resource
function process.closeResource(res)
	res.refc = res.refc - 1
	if res.refc > 0 then return end

	if res.file then
		Kocos.fs.close(res.file)
	end
	if res.socket then
		Kocos.net.close(res.socket)
	end
end

---@param proc Kocos.process
---@param res Kocos.resource
function process.moveResource(proc, res)
	local fd = #proc.fds
	while proc.fds[fd] do fd = fd + 1 end
	proc.fds[fd] = res
	return fd
end

---@param proc Kocos.process
---@param exit? integer
function process.terminate(proc, exit)
	if proc.state ~= "running" then return end -- nice try, signal handler
	proc.state = "finished"
	proc.exitcode = exit or 1
	if proc == process.root then
		Kocos.panickf("KERNEL EXITED: %d", proc.exitcode)
		return
	end
	if proc == Kocos.process.init then
		Kocos.panickf("INIT EXITED: %d", proc.exitcode)
		return
	end
	if proc.parent then
		process.raise(proc.parent, process.SIGCHLD, proc.pid, proc.exitcode)
	end

	process.raise(proc, process.SIGABRT)

	if proc.driver then
		Kocos.removeDriver(proc.driver)
		proc.driver = nil
	end
	if proc.ev_listener then
		Kocos.event.forget(proc.ev_listener)
		proc.ev_listener = nil
	end

	if proc.daemon then
		-- daemon is gone
		process.daemons[proc.daemon] = nil
	end

	for _, res in pairs(proc.fds) do
		process.closeResource(res)
	end
	proc.fds={}

	if process.current == proc then
		coroutine.yield()
		return
	end
end

---@param proc Kocos.process
function process.close(proc)
	if proc.state == "dying" then return end -- nice try, signal handler
	if not process.allProcs[proc.pid] then return end -- somehow died twice???
	process.terminate(proc, 1)
	proc.state = "dying" -- to prevent bad shit

	---@type Kocos.process[]
	local allChildren = {}
	for _, child in pairs(proc.children) do table.insert(allChildren, child) end

	for _, child in ipairs(allChildren) do
		process.close(child)
	end

	if proc.parent then
		proc.parent.children[proc.pid] = nil
	end


	process.allProcs[proc.pid] = nil -- and he's gone
	proc.state = "dead"
end

---@param proc Kocos.process
---@param path string
function process.resolve(proc, path)
	if path:sub(1,1) == "/" then
		return Kocos.fs.canonical(path)
	end
	return Kocos.fs.join(proc.cwd, path)
end

---@param lib Kocos.process.sharedLib
---@param module string
---@param refs? table
---@return Kocos.process.module?
function process.libreadmod(lib, module, refs)
	refs = refs or {}
	-- in case of cyclical bullshit dependencies
	if refs[lib] then return end
	refs[lib] = true

	---@type Kocos.process.module?
	local mod = lib.modules[module]
	if mod then return mod end

	for _, dep in ipairs(lib.deps) do
		mod = process.libreadmod(dep, module, refs)
		if mod then return mod end
	end
end

---@param proc Kocos.process
---@param module string
---@return Kocos.process.module?
function process.readmod(proc, module)
	---@type Kocos.process.module?
	local mod = proc.modules[module]
	if mod then return mod end

	local refs = {}

	for _, dep in ipairs(proc.deps) do
		mod = process.libreadmod(dep, module, refs)
		if mod then return mod end
	end
end

---@class Kocos.process.image
---@field init function
---@field modules table<string, Kocos.process.module>
---@field deps string[]

---@param proc Kocos.process
---@param argv string[]
---@param env table<string, string>
---@param namespace _G
---@return boolean?, string?
function process.exec(proc, path, argv, env, namespace)
	local f, err = Kocos.fs.open(path, "r")
	if not f then return nil, err end
	for _, driver in ipairs(Kocos.drivers) do
		Kocos.fs.seek(f, "set", 0)
		-- PROC-binfmt
		---@type Kocos.process.image?, string?
		local img, err2 = driver("PROC-binfmt", path, f, namespace)
		if err2 then
			-- actual error instead of being ignored
			Kocos.fs.close(f)
			return nil, err2
		end
		if img then
			Kocos.fs.close(f)
			-- if this is nil and err2 is also nil, means driver ignored it
			proc.exe = path
			proc.args = argv
			proc.env = env
			proc.namespace = namespace
			if proc.driver then
				Kocos.removeDriver(proc.driver)
				proc.driver = nil
			end
			proc.thread = coroutine.create(img.init)
			proc.modules = img.modules
			proc.deps = {} -- TODO: deps
			proc.signals = {} -- Signal handlers are ignored
			---@type integer[]
			local toClose = {}
			for fd, res in pairs(proc.fds) do
				-- TODO: check cloexec
				if (res.opts & Kocos.fs.O_CLOEXEC) ~= 0 then
					table.insert(toClose, fd)
				end
			end
			for _, fd in ipairs(toClose) do
				local res = proc.fds[fd]
				process.closeResource(res)
				proc.fds[fd] = nil
			end
			return true
		end
	end

	Kocos.fs.close(f)

	return nil, Kocos.errno.ENOEXEC
end

--- A function which can be used as the thread when no special
--- initialization needs to happen
function process.basicThread()
	require("_start", true)
end

---@param pid integer
function process.isDead(pid)
	return not process.allProcs[pid]
end

---@param proc Kocos.process
function process.isRunning(proc)
	return proc.state == "running"
end

---@param proc Kocos.process
function process.isBlocked(proc)
	while #proc.blockUntil > 0 do -- best feature in all of gaming
		if proc.blockUntil[1]() then
			-- holy shit we're free
			table.remove(proc.blockUntil, 1)
		else
			-- darn
			return true
		end
	end
	return false
end

---@param proc Kocos.process
---@param condition Kocos.process.condition
function process.blockUntil(proc, condition)
	table.insert(proc.blockUntil, condition)
	if proc.thread == coroutine.running() then
		coroutine.yield()
	elseif process.current.pid == proc.pid then
		-- it seems as if we are in a signal handler or callback on another process' thread
		-- this is like categorically awful situation, but we can still work with it
		while process.isBlocked(proc) do
			coroutine.yield()
		end
	end
end

---@param proc Kocos.process
function process.resume(proc)
	if proc.stopped then return end
	if process.isBlocked(proc) then return end
	if not process.isRunning(proc) then return end
	while #proc.blockUntil > 0 do -- best feature in all of gaming
		if proc.blockUntil[1]() then
			-- holy shit we're free
			table.remove(proc.blockUntil, 1)
		else
			-- darn
			return
		end
	end
	if coroutine.status(proc.thread) ~= "suspended" then return end
	local old = process.current
	process.current = proc
	local ok, err = coroutine.resume(proc.thread)
	process.current = old
	if not ok then
		Kocos.printkf(Kocos.L_ERROR, "Process %d crashed: %s", proc.pid, debug.traceback(proc.thread, err))
		process.raise(proc, process.SIGTRAP, debug.traceback(proc.thread, err))
		return
	end
	if not process.isRunning(proc) then return end
	if coroutine.status(proc.thread) == "dead" then
		local exit = err
		if type(exit) ~= "number" then exit = 0 end
		process.terminate(proc, exit)
	end
end

---@param proc Kocos.process
function process.isRoot(proc)
	return proc.uid == 0 or proc.euid == 0
end

function process.run()
	for _, proc in pairs(process.allProcs) do
		process.resume(proc)
	end
end

local rawload = load

-- safe version of load

---@param chunk function|string
---@param chunkname? string
---@param mode? "t"|"b"|"bt"
---@param env? table
---@return function?, string? error_message
function load(chunk, chunkname, mode, env)
	return rawload(chunk, chunkname, mode, env or process.current.namespace)
end

Kocos.printk(Kocos.L_DEBUG, "process system loaded")

Kocos.printk(Kocos.L_DEBUG, "creating kernel process")
process.current = process.create(coroutine.running(), _G, 0, 0)
process.root = process.current

Kocos.process = process
