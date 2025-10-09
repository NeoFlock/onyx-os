local process = Kocos.process
local errno = Kocos.errno

---@class Kocos.syscalls
local syscalls = {}

---@param path string
---@param mode "r"|"a"|"w"
---@param opts? integer
function syscalls.open(path, mode, opts)
	-- TODO: validate permissions

	if type(path) ~= "string" or type(mode) ~= "string" then
		return nil, errno.EINVAL
	end

	if mode ~= "r" and mode ~= "w" and mode ~= "a" then
		return nil, errno.EINVAL
	end
	opts = opts or 0
	if type(opts) ~= "number" or math.floor(opts) ~= opts then
		return nil, errno.EINVAL
	end

	path = process.resolve(process.current, path)

	local file, err = Kocos.fs.open(path, mode)
	if not file then return nil, err end

	---@type Kocos.resource
	local res = {refc = 1, opts = 0, file = file}
	process.setResourceFlags(res, opts)

	return process.moveResource(process.current, res)
end

---@param path string
---@return boolean?, string?
function syscalls.mkdir(path)
	if type(path) ~= "string" then
		return nil, errno.EINVAL
	end
	path = process.resolve(process.current, path)
	return Kocos.fs.mkdir(path)
end

---@param path string
---@param addr string
---@return boolean?, string?
function syscalls.mountDev(path, addr)
	if type(path) ~= "string" then
		return nil, errno.EINVAL
	end
	if type(addr) ~= "string" then
		return nil, errno.EINVAL
	end
	path = process.resolve(process.current, path)
	if Kocos.fs.ftype(path) ~= Kocos.fs.FTYPE_DIR then
		return nil, errno.ENOTDIR
	end
	local parentmnt, p = Kocos.fs.resolve(path)
	local dev = component.proxy(addr)
	if not dev then return nil, errno.ENODEV end
	local mnt = Kocos.fs.mount(dev)
	if not mnt then
		return nil, errno.ENODRIVER
	end
	parentmnt.submounts[p] = mnt
	return true
end

--- Returns a map of paths obtained from depth-first search to device addresses
function syscalls.getMounts()
	---@type table<string, string>
	local t = {}

	---@type string[]
	local queue = {"/"}

	while true do
		local p = table.remove(queue, 1)
		if not p then break end

		local dev = Kocos.fs.resolve(p)
		if not t[dev.dev.address] then
			t[dev.dev.address] = p
			for mp in pairs(dev.submounts) do
				table.insert(queue, Kocos.fs.join(p, mp))
			end
		end
	end

	return t
end

---@param fd integer
---@param length integer
---@return string?, string?
function syscalls.read(fd, length)
	if type(fd) ~= "number" then
		return nil, errno.EINVAL
	end
	if type(length) ~= "number" then
		return nil, errno.EINVAL
	end
	local proc = process.current
	local f = proc.fds[fd]
	if f then
		if f.file then
			return Kocos.fs.read(f.file, length)
		end
		-- TODO: other resource types
	end
	return nil, errno.EBADF
end

---@param fd integer
---@param data string
---@return boolean?, string?
function syscalls.write(fd, data)
	if type(fd) ~= "number" then
		return nil, errno.EINVAL
	end
	if type(data) ~= "string" then
		return nil, errno.EINVAL
	end
	local proc = process.current
	local f = proc.fds[fd]
	if f then
		if f.file then
			return Kocos.fs.write(f.file, data)
		end
		-- TODO: other resource types
	end
	return nil, errno.EBADF
end

---@param fd integer
---@return boolean?, string?
function syscalls.close(fd)
	if type(fd) ~= "number" then
		return nil, errno.EINVAL
	end
	local proc = process.current
	local f = proc.fds[fd]
	if not f then return nil, errno.EBADF end
	proc.fds[fd] = nil
	process.closeResource(f)
	return true
end

---@param path string
---@return string[]?, string?
function syscalls.list(path)
	path = process.resolve(process.current, path)
	return Kocos.fs.list(path)
end

---@param path string
---@return Kocos.fs.ftype?, string?
function syscalls.ftype(path)
	path = process.resolve(process.current, path)
	return Kocos.fs.ftype(path)
end

---@param path string
---@return boolean?, string?
function syscalls.exists(path)
	path = process.resolve(process.current, path)

	return Kocos.fs.exists(path, true)
end

---@param path string
---@return string
function syscalls.absolutepath(path)
	return process.resolve(process.current, path)
end

---@param path string
---@return boolean?, string?
function syscalls.validlink(path)
	path = process.resolve(process.current, path)

	return Kocos.fs.exists(path)
end

---@param f function
---@return integer Returns pid of new process
function syscalls.fork(f)
	local pid = process.fork(process.current, f).pid
	coroutine.yield() -- give child a chance to shine
	return pid
end

function syscalls.environ()
	-- mutating it is fine
	return process.current.env
end

function syscalls.argv()
	-- mutating it is technically fine but please don't
	return process.current.args
end

function syscalls.sleep(time)
	if type(time) ~= "number" then
		return nil, errno.EINVAL
	end

	local deadline = computer.uptime() + time
	process.blockUntil(process.current, function()
		return computer.uptime() >= deadline
	end)
	return true
end

---@return number
function syscalls.uptime()
	return computer.uptime()
end

---@param path string
---@param argv string[]?
---@param env table<string, string>?
---@param namespace _G?
---@return boolean?, string?
function syscalls.exec(path, argv, env, namespace)
	if type(path) ~= "string" then
		return nil, errno.EINVAL
	end

	argv = argv or {[0] = path}
	argv[0] = argv[0] or path
	env = env or table.copy(process.current.env)
	namespace = namespace or process.current.namespace

	path = process.resolve(process.current, path)

	-- TODO: check read + exec perms

	local ok, err = process.exec(process.current, path, argv, env, namespace)
	if not ok then return nil, err end

	coroutine.yield() -- and, its gone.
end

---@param module string
---@return string?, string?
function syscalls.readmod(module)
	if type(module) ~= "string" then return nil, errno.EINVAL end

	local mod = process.readmod(process.current, module)
	if mod then
		return mod.data, mod.src
	end
	return nil, errno.ENOENT
end

---@param filter? string
---@param exact? boolean
function syscalls.clist(filter, exact)
	---@type table<string, string>
	local t = {}
	for addr, type in component.list(filter, exact) do
		t[addr] = type
	end
	local k
	setmetatable(t, {
		__call = function()
			k = next(t, k)
			return k, t[k]
		end,
	})
	return t
end

---@param shortform string
---@param filter? string
---@param exact? boolean
---@return string?, string?
function syscalls.caddress(shortform, filter, exact)
	if type(shortform) ~= "string" then
		return nil, errno.EINVAL
	end
	local l, err = syscalls.clist(filter, exact)
	if err then return nil, err end
	for addr in l do
		if string.startswith(addr, shortform) then
			return addr
		end
	end
	return nil, errno.ENODEV
end

function syscalls.cmethods(addr)
	return component.methods(addr)
end

function syscalls.cinvoke(addr, method, ...)
	return component.methods(addr, method, ...)
end

---@return Kocos.device?
function syscalls.cproxy(addr)
	return component.proxy(addr)
end

---@return Kocos.device?
function syscalls.cprimary(type)
	return component.getPrimary(type)
end

function syscalls.cfields(addr)
	return component.fields(addr)
end

function syscalls.cdoc(addr, method)
	return component.doc(addr, method)
end

function syscalls.cslot(addr)
	return component.slot(addr)
end

function syscalls.ctype(addr)
	return component.type(addr)
end

---@param pid integer
---@return integer
function syscalls.waitpid(pid)
	local proc = process.allProcs[pid]
	if not proc then return 0 end
	-- theoretically a signal can fuck us up however we do not care
	process.blockUntil(process.current, function()
		return not process.isRunning(proc)
	end)
	process.close(proc)
	return proc.exitcode
end

---@param pid integer
---@param condition Kocos.process.condition
function syscalls.blockUntil(pid, condition)
	local p = process.allProcs[pid]
	if not p then return nil, errno.ESRCH end
	if type(condition) ~= "function" then return nil, errno.EINVAL end

	local cur = process.current
	if cur.uid ~= 0 and not process.isDecendantOf(p, cur) then
		return nil, errno.EPERM
	end

	process.blockUntil(p, function()
		local ok, s = pcall(condition)
		if not ok then return false end
		return s
	end)
	return true
end

---@param dir string
---@return string?, string?
function syscalls.chdir(dir)
	if type(dir) ~= "string" then
		return nil, errno.EINVAL
	end
	if dir == "." then return process.current.cwd end
	dir = process.resolve(process.current, dir)
	process.current.cwd = dir
	return dir
end

---@class Kocos.sysinfoResult
---@field kernel string
---@field os string
---@field bootAddress string
---@field rootAddress string
---@field tmpAddress string
---@field hostname string
---@field memtotal integer
---@field memfree integer
---@field kernelPID integer
---@field initPID integer
---@field energy number
---@field maxEnergy number

function syscalls.sysinfo()
	---@type Kocos.sysinfoResult
	return {
		kernel = _KVERSION,
		os = _OSVERSION,
		bootAddress = computer.getBootAddress(),
		rootAddress = Kocos.fs.root.dev.address,
		tmpAddress = computer.tmpAddress(),
		memfree = computer.freeMemory(),
		memtotal = computer.totalMemory(),
		hostname = Kocos.hostname,
		kernelPID = process.root.pid,
		initPID = process.init.pid,
		energy = computer.energy(),
		maxEnergy = computer.maxEnergy(),
	}
end


---@param addr? string
function syscalls.chboot(addr)
	if addr then
		if type(addr) ~= "string" then
			return nil, errno.EINVAL
		end
		if process.current.euid ~= 0 then
			return nil, errno.EPERM
		end
		computer.setBootAddress(addr)
	end
	return computer.getBootAddress()
end

---@param hostname string?
---@return string?, string?
function syscalls.hostname(hostname)
	if hostname then
		if process.current.euid ~= 0 then
			return nil, errno.EACCESS
		end
		Kocos.hostname = hostname
	end
	return Kocos.hostname
end

---@return string[]
function syscalls.syscalls()
	local s = {}
	for k in pairs(syscalls) do table.insert(s, k) end
	return s
end

---@param daemon string
---@param callback fun(cpid: integer, ...): ...
function syscalls.registerDaemon(daemon, callback)
	local d = process.daemons[daemon]
	if d then return nil, errno.EADDRINUSE end
	if process.current.daemon then
		return nil, errno.EALREADY
	end
	process.daemons[daemon] = {
		proc = process.current,
		callback = callback,
	}
	process.current.daemon = daemon
	return true
end

---@param daemon string
---@return integer?, string?
function syscalls.getDaemonPid(daemon)
	local d = process.daemons[daemon]
	if not d then return nil, errno.ESRCH end
	return d.proc.pid
end

---@return string[]
function syscalls.listDaemons()
	local daemons = {}
	for addr in pairs(process.daemons) do
		table.insert(daemons, addr)
	end
	return daemons
end

---@param daemon string
---@return ...
function syscalls.invokeDaemon(daemon, ...)
	local d = process.daemons[daemon]
	if not d then return nil, errno.ESRCH end
	local t = {process.pcall(d.proc, d.callback, process.current.pid, ...)}
	if t[1] then
		return table.unpack(t, 2)
	end
	return nil, table.unpack(t, 2)
end

---@return integer[]
function syscalls.getprocs()
	local pids = {}
	for pid in pairs(process.allProcs) do
		table.insert(pids, pid)
	end
	return pids
end

function syscalls.getpid()
	return process.current.pid
end

function syscalls.getuid()
	return process.current.uid
end

function syscalls.getgid()
	return process.current.gid
end

function syscalls.geteuid()
	return process.current.euid
end

function syscalls.getegid()
	return process.current.egid
end

---@param uid integer
---@param pid? integer
---@return boolean, string?
function syscalls.setuid(uid, pid)
	local cur = process.current
	local target = process.allProcs[pid or cur.pid]
	if not target then return false, errno.ESRCH end
	if not process.isDecendantOf(target, cur) then
		return false, errno.EPERM
	end
	if uid == 0 and not process.isRoot(cur) then
		return false, errno.EPERM
	end
	target.uid = uid
	return true
end

---@param gid integer
---@param pid? integer
---@return boolean, string?
function syscalls.setgid(gid, pid)
	local cur = process.current
	local target = process.allProcs[pid or cur.pid]
	if not target then return false, errno.ESRCH end
	if not process.isDecendantOf(target, cur) then
		return false, errno.EPERM
	end
	if gid == 0 and not process.isRoot(cur) then
		return false, errno.EPERM
	end
	target.gid = gid
	return true
end

---@param uid integer
---@param pid? integer
---@return boolean, string?
function syscalls.seteuid(uid, pid)
	local cur = process.current
	local target = process.allProcs[pid or cur.pid]
	if not target then return false, errno.ESRCH end
	if not process.isDecendantOf(target, cur) then
		return false, errno.EPERM
	end
	if uid == 0 then
		target.euid = target.uid
		return true
	end
	target.euid = uid
	return true
end

---@param gid integer
---@param pid? integer
---@return boolean, string?
function syscalls.setegid(gid, pid)
	local cur = process.current
	local target = process.allProcs[pid or cur.pid]
	if not target then return false, errno.ESRCH end
	if not process.isDecendantOf(target, cur) then
		return false, errno.EPERM
	end
	if gid == 0 then
		target.egid = target.gid
		return true
	end
	target.egid = gid
	return true
end

---@class Kocos.process.info
---@field argv? string[]
---@field environ? table<string, string>
---@field uid? integer
---@field euid? integer
---@field gid? integer
---@field egid? integer
---@field parent? integer
---@field driver? boolean
---@field daemon? string
---@field tracer? integer
---@field exitcode? integer
---@field cwd? string
---@field exe? string
---@field namespace? _G
---@field children? integer[]
---@field signals? string[]

---@param pid integer
---@vararg "args"|"env"|"uid"|"gid"|"parent"|"tree"|"state"|"namespace"|"signals"
---@return Kocos.process.info?, string?
function syscalls.getprocinfo(pid, ...)
	local proc = process.allProcs[pid]
	if not proc then return nil, errno.ESRCH end
	local isTrusted = process.current.euid == 0 or process.isDecendantOf(proc, process.current)
	---@type Kocos.process.info
	local info = {}
	local vlen = select("#", ...)
	for i=1, vlen do
		local v = select(i, ...)
		if v == "args" then
			info.argv = table.copy(proc.args)
		elseif v == "env" then
			info.environ = table.copy(proc.env)
		elseif v == "uid" then
			info.uid = proc.uid
			info.euid = proc.euid
		elseif v == "gid" then
			info.gid = proc.gid
			info.egid = proc.egid
		elseif v == "parent" then
			if proc.parent then info.parent = proc.parent.pid end
		elseif v == "tree" then
			if proc.parent then info.parent = proc.parent.pid end
			info.children = {}
			for cpid in pairs(proc.children) do
				table.insert(info.children, cpid)
			end
		elseif v == "state" then
			if proc.parent then info.parent = proc.parent.pid end
			if proc.tracer then info.tracer = proc.tracer.pid end
			info.driver = not not proc.driver
			info.exitcode = proc.exitcode
			info.exe = proc.exe
			info.cwd = proc.cwd
		elseif v == "namespace" then
			if isTrusted then info.namespace = proc.namespace end
		elseif v == "signals" then
			info.signals = {}
			for sig in pairs(proc.signals) do
				table.insert(info.signals, sig)
			end
		end
	end
	return info
end

Kocos.syscalls = syscalls

---@diagnostic disable: lowercase-global
---@param sysname string
---@return ...
function syscall(sysname, ...)
	local cur = process.current
	if process.isDead(cur.pid) then return nil, errno.ECHILD end
	if not syscalls[sysname] then return nil, errno.ENOSYS end
	if cur.tracer then
		-- inform the tracer
		process.raise(cur.tracer, process.SIGSYSC, cur.pid, sysname, {...})
	end
	local t = {pcall(syscalls[sysname], ...)}

	if cur.tracer then
		-- inform the tracer
		local ret = t[1] and {table.unpack(t, 2)} or {nil, t[2]}
		process.raise(cur.tracer, process.SIGSYSR, cur.pid, sysname, {...}, ret)
	end

	if not process.isRunning(process.current) then
		coroutine.yield() -- we're dead
	end

	if t[1] then
		return table.unpack(t, 2)
	end
	return nil, t[2]
end
