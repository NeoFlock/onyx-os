local process = Kocos.process
local errno = Kocos.errno

---@class Kocos.syscalls
local syscalls = {}

---@param path string
---@param mode "r"|"a"|"w"
function syscalls.open(path, mode)
	-- TODO: validate permissions

	if type(path) ~= "string" or type(mode) ~= "string" then
		return nil, errno.EINVAL
	end

	if mode ~= "r" and mode ~= "w" and mode ~= "a" then
		return nil, errno.EINVAL
	end

	path = process.resolve(process.current, path)

	local file, err = Kocos.fs.open(path, mode)
	if not file then return nil, err end

	---@type Kocos.resource
	local res = {refc = 1, opts = 0, file = file}

	return process.moveResource(process.current, res)
end

---@param path string
---@param perms integer
---@return boolean?, string?
function syscalls.touch(path, perms)
	if type(path) ~= "string" then
		return nil, errno.EINVAL
	end
	if type(perms) ~= "number" then
		return nil, errno.EINVAL
	end
	perms = math.floor(perms)
	path = process.resolve(process.current, path)
	return Kocos.fs.touch(path, perms, process.current.uid, process.current.gid)
end

---@param path string
---@param perms integer
---@return boolean?, string?
function syscalls.mkdir(path, perms)
	if type(path) ~= "string" then
		return nil, errno.EINVAL
	end
	if type(perms) ~= "number" then
		return nil, errno.EINVAL
	end
	perms = math.floor(perms)
	path = process.resolve(process.current, path)
	return Kocos.fs.mkdir(path, perms, process.current.uid, process.current.gid)
end

---@param path string
---@return boolean?, string?
function syscalls.remove(path)
	if type(path) ~= "string" then
		return nil, errno.EINVAL
	end
	path = process.resolve(process.current, path)
	return Kocos.fs.remove(path)
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
	local parentmnt, p = Kocos.fs.resolve(path, true)
	local dev = component.proxy(addr)
	if not dev then return nil, errno.ENODEV end
	local mnt = Kocos.fs.mount(dev)
	if not mnt then
		return nil, errno.ENODRIVER
	end
	parentmnt.submounts[p] = mnt
	return true
end

---@param path string
---@return boolean, string?
function syscalls.unmount(path)
	if type(path) ~= "string" then
		return false, errno.EINVAL
	end
	path = process.resolve(process.current, path)
	local parentmnt, p = Kocos.fs.resolve(path, true)
	local mnt = parentmnt.submounts[p]
	if not mnt then
		return false, errno.EISDIR
	end
	Kocos.fs.unmount(mnt)
	parentmnt.submounts[p] = nil
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
			if f.file.read then
				return f.file:read(length)
			end
			return nil, errno.EBADF
		end
		if f.socket then
			return Kocos.net.read(f.socket, length)
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
		if f.socket then
			return Kocos.net.write(f.socket, data)
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

---@param fd integer
---@param whence seekwhence
---@param off integer
---@return integer?, string?
function syscalls.seek(fd, whence, off)
	if type(fd) ~= "number" then
		return nil, errno.EINVAL
	end
	local proc = process.current
	local f = proc.fds[fd]
	if not f then return nil, errno.EBADF end
	if f.file then
		return Kocos.fs.seek(f.file, whence, off)
	end
	return nil, errno.EBADF
end

---@param fd integer
---@param action string
---@return ...
function syscalls.ioctl(fd, action, ...)
	if type(fd) ~= "number" then
		return nil, errno.EINVAL
	end
	local proc = process.current
	local f = proc.fds[fd]
	if not f then return nil, errno.EBADF end
	if f.file then
		return Kocos.fs.ioctl(f.file, action, ...)
	end
	if f.socket then
		return Kocos.net.ioctl(f.socket, action, ...)
	end
	return nil, errno.EBADF
end

---@param domain string
---@param protocol string
---@param host string
--- Either a name of an application-layer protocol or the port number
---@param service? string|integer
---@return Kocos.net.addrinfo?, string?
function syscalls.getaddrinfo(domain, protocol, host, service)
	if type(domain) ~= "string" then
		return nil, errno.EINVAL
	end
	if type(protocol) ~= "string" then
		return nil, errno.EINVAL
	end
	if type(host) ~= "string" then
		return nil, errno.EINVAL
	end
	if type(service) ~= "string" and type(service) ~= "number" and type(service) ~= "nil" then
		return nil, errno.EINVAL
	end
	return Kocos.net.getaddrinfo(domain, protocol, host, service)
end

---@param domain string
---@param socktype string
---@param protocol? string
---@return integer?, string?
function syscalls.socket(domain, socktype, protocol)
	if type(domain) ~= "string" then
		return nil, errno.EINVAL
	end
	if type(socktype) ~= "string" then
		return nil, errno.EINVAL
	end
	if type(protocol) ~= "string" and type(protocol) ~= "nil" then
		return nil, errno.EINVAL
	end
	local sock, err = Kocos.net.socket(domain, socktype, protocol)
	if not sock then return nil, err end

	return Kocos.process.moveResource(Kocos.process.current, {
		refc = 1,
		opts = 0,
		socket = sock,
	})
end

---@param fd integer
function syscalls.accept(fd)
	local res = process.current.fds[fd]
	if not res then return nil, errno.EBADF end
	local s = res.socket
	if not s then return nil, errno.ENOTSOCK end

	local client, err = Kocos.net.accept(s)
	if not client then return nil, err end

	return Kocos.process.moveResource(Kocos.process.current, {
		refc = 1,
		opts = 0,
		socket = client,
	})
end

---@param fd integer
---@param addrinfo Kocos.net.addrinfo
function syscalls.connect(fd, addrinfo)
	-- prevents some security issues
	setmetatable(addrinfo, nil)

	local res = process.current.fds[fd]
	if not res then return nil, errno.EBADF end
	local s = res.socket
	if not s then return nil, errno.ENOTSOCK end

	return Kocos.net.connect(s, addrinfo)
end

---@param fd integer
---@param addrinfo Kocos.net.addrinfo
function syscalls.listen(fd, addrinfo)
	-- prevents some security issues
	setmetatable(addrinfo, nil)

	local res = process.current.fds[fd]
	if not res then return nil, errno.EBADF end
	local s = res.socket
	if not s then return nil, errno.ENOTSOCK end

	return Kocos.net.listen(s, addrinfo)
end

---@return integer?, string?
function syscalls.dup(fd)
	local res = process.current.fds[fd]
	if not res then return nil, errno.EBADF end
	local f = process.moveResource(process.current, res)
	res.refc = res.refc + 1
	return f
end

---@return boolean, string?
function syscalls.dup2(fd, newFd)
	local res = process.current.fds[fd]
	if not res then return false, errno.EBADF end
	if process.current.fds[newFd] then return false, errno.EEXIST end
	process.current.fds[newFd] = res
	res.refc = res.refc + 1
	return true
end

function syscalls.fcntl(fd, action, ...)
	if type(fd) ~= "number" then
		return nil, errno.EINVAL
	end
	local proc = process.current
	local f = proc.fds[fd]
	if not f then return nil, errno.EBADF end
	if action == Kocos.fs.F_SETCB then
		---@type function?
		local listener = ...
		if type(listener) ~= "function" and type(listener) ~= "nil" then
			return nil, errno.EINVAL
		end
		if f.file then
			return Kocos.fs.setlistener(f.file, listener)
		end
		return nil, errno.EBADF
	end
	if action == Kocos.fs.F_GETFL then
		return f.opts
	end
	if action == Kocos.fs.F_SETFL then
		---@type integer
		local flags = ...
		if type(flags) ~= "number" then
			return nil, errno.EINVAL
		end
		flags = math.abs(math.floor(flags))
		f.opts = flags
		if f.file then
			f.file.flags = flags
		end
		if f.socket then
			f.socket.flags = flags
		end
		return true
	end
	if action == Kocos.fs.F_NOTIF then
		---@type string
		local ev = ...
		if type(ev) ~= "string" then
			return nil, errno.EINVAL
		end
		if f.file then
			Kocos.fs.notify(f.file, ...)
			return true
		end
		if f.socket then
			Kocos.net.notify(f.socket, ...)
			return true
		end
		return nil, errno.EBADF
	end
	return nil, errno.EINVAL
end

---@param path string
---@return string[]?, string?
function syscalls.list(path)
	path = process.resolve(process.current, path)
	return Kocos.fs.list(path)
end

---@param path string
---@return Kocos.fs.stat?, string?
function syscalls.stat(path)
	path = process.resolve(process.current, path)
	return Kocos.fs.stat(path)
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
---@return string
function syscalls.canonical(path)
	return Kocos.fs.canonical(path)
end


---@param s string
---@vararg string
---@return string
function syscalls.join(s, ...)
	return Kocos.fs.join(process.resolve(process.current, s), ...)
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
	local child = process.fork(process.current, f)
	process.resume(child) -- give child a chance to shine
	return child.pid
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

function syscalls.sync()
	Kocos.fs.sync()
	return true
end

---@param path string
---@param argv string[]?
---@param env table<string, string>?
---@param namespace _G?
---@return boolean, string?
function syscalls.exec(path, argv, env, namespace)
	if type(path) ~= "string" then
		return false, errno.EINVAL
	end

	local cur = process.current

	argv = argv or {[0] = path}
	argv[0] = argv[0] or path
	env = env or table.copy(cur.env)
	namespace = namespace or cur.namespace

	path = process.resolve(cur, path)

	-- TODO: check read + exec perms

	local ok, err = process.exec(cur, path, argv, env, namespace)
	if not ok then return false, err end

	-- TODO: consider some way to resume it instantly
	--process.resume(cur) -- deadlocks?
	coroutine.yield() -- and, its gone.
	return true
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

---@param dev Kocos.vdevice
function syscalls.cadd(dev)
	if not process.isRoot(process.current) then
		return false, errno.EPERM
	end
	if component.type(dev.address) then
		return false, errno.EADDRINUSE
	end
	component.add(dev)
	return true
end

---@param address string
function syscalls.cremove(address)
	if not process.isRoot(process.current) then
		return false, errno.EPERM
	end
	if not component.isVirtual(address) then
		return false, errno.ENODEV
	end
	component.remove(address)
	return true
end

---@param image Kocos.ramfs.node
---@param label string?
---@param readonly boolean
---@param addr string?
---@return string?, string?
function syscalls.cramfs(image, label, readonly, addr)
	if not process.isRoot(process.current) then
		return nil, errno.EPERM
	end
	return Kocos.addRamfsComponent({
		label = label,
		readonly = readonly,
		fds = {},
		image = image,
	}, addr)
end

function syscalls.cmethods(addr)
	return component.methods(addr)
end

function syscalls.cinvoke(addr, method, ...)
	return component.invoke(addr, method, ...)
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
	process.resume(proc)
	-- theoretically a signal can fuck us up however we do not care
	process.blockUntil(process.current, function()
		return not process.isRunning(proc)
	end)
	process.close(proc)
	return proc.exitcode
end

---@param pid integer
---@param condition Kocos.process.condition
---@return boolean, string?
function syscalls.blockUntil(pid, condition)
	local p = process.allProcs[pid]
	if not p then return false, errno.ESRCH end
	if type(condition) ~= "function" then return false, errno.EINVAL end

	-- optimization
	if condition() then return true end

	local cur = process.current
	if cur.uid ~= 0 and not process.isDecendantOf(p, cur) then
		return nil, errno.EPERM
	end

	process.blockUntil(p, function()
		local ok, s = process.pcall(cur, condition)
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
	dir = Kocos.fs.fromRoot(dir, process.current.root)
	process.current.cwd = dir
	return dir
end

---@param dir string
---@return string?, string?
function syscalls.chroot(dir)
	if type(dir) ~= "string" then
		return nil, errno.EINVAL
	end
	if dir == "." then return process.current.cwd end
	dir = process.resolve(process.current, dir)
	process.current.root = dir
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

---@param addr string
---@return boolean, string?
function syscalls.chsysroot(addr)
	if type(addr) ~= "string" then
		return false, errno.EINVAL
	end
	if process.current.euid ~= 0 then
		return false, errno.EPERM
	end
	local proxy = component.proxy(addr)
	if not proxy then return false, errno.ENODEV end
	local newRoot = Kocos.fs.mount(proxy)
	if not newRoot then return false, errno.ENODRIVER end
	local oldRoot = Kocos.fs.root
	Kocos.fs.root = newRoot
	if oldRoot then Kocos.fs.unmount(oldRoot) end
	return true
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

--- Set the tracer to process at [pid]
---@param pid integer
---@return boolean, string?
function syscalls.strace(pid)
	local p = process.allProcs[pid]
	if not p then return false, errno.ESRCH end
	if not process.isDecendantOf(process.current, p) then
		return false, errno.EPERM
	end
	process.current.tracer = p
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
	if not process.isDecendantOf(target, cur) and not process.isRoot(cur) then
		return false, errno.EPERM
	end
	if uid == 0 and not process.isRoot(cur) then
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
	if not process.isDecendantOf(target, cur) and not process.isRoot(cur) then
		return false, errno.EPERM
	end
	if gid == 0 and not process.isRoot(cur) then
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

function syscalls.proclocal()
	return process.current.proclocal
end

---@param pid integer
---@param signal string
function syscalls.kill(pid, signal, ...)
	local cur = process.current
	local target = process.allProcs[pid]
	if not target then return nil, errno.ESRCH end
	-- signals that are just not sendable even by root,
	-- cuz their meaning would be violated
	if signal == "SIGTRAP" then return nil, errno.EPERM end
	if signal == "SIGCHLD" then return nil, errno.EPERM end
	if signal == "SIGABRT" then return nil, errno.EPERM end
	local allowed = process.isRoot(cur) or cur.uid == target.uid or cur.euid == target.euid or cur.euid == target.uid
	if not allowed then
		return nil, errno.EPERM
	end
	process.raise(target, signal, ...)
	return true
end

---@param sig string
---@param f function
function syscalls.signal(sig, f)
	process.current.signals[sig] = f
	return true
end

function syscalls.abort()
	process.raise(process.current, process.SIGABRT)
end

---@param code? integer
function syscalls.exit(code)
	code = code or 0
	process.terminate(process.current, code)
	return 0
end

---@param driver? function
---@return boolean?, string?
function syscalls.mkdriver(driver)
	local cur = process.current
	if cur.euid ~= 0 then
		return nil, errno.EPERM
	end
	if cur.driver then
		Kocos.removeDriver(driver)
	end
	cur.driver = driver
	Kocos.addDriver(driver)
	return true
end

---@param listener? function
---@return boolean?, string?
function syscalls.mklistener(listener)
	local cur = process.current
	if cur.euid ~= 0 then
		return nil, errno.EPERM
	end
	if cur.ev_listener then
		Kocos.event.forget(cur.ev_listener)
	end
	cur.ev_listener = listener
	Kocos.event.listen(listener)
	return true
end

function syscalls.errnos()
	return table.copy(Kocos.errno)
end

---@param pid integer
---@return boolean, string?
function syscalls.resume(pid)
	local proc = process.allProcs[pid]
	if not proc then return false, errno.ESRCH end
	process.resume(proc)
	return true
end

Kocos.syscalls = syscalls

---@diagnostic disable: lowercase-global
---@param sysname string
---@return ...
function syscall(sysname, ...)
	local cur = process.current

	if cur.executionDeadline and computer.uptime() > cur.executionDeadline then
		coroutine.yield()
	end

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
