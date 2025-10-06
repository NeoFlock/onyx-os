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
	return process.fork(process.current, f).pid
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

	process.current.deadline = computer.uptime() + time
	coroutine.yield()
	return true
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

---@param pid integer
---@return integer
function syscalls.waitpid(pid)
	local proc = process.allProcs[pid]
	if not proc then return 0 end
	-- theoretically a signal can fuck us up however we do not care
	process.blockUntil(process.current, function()
		return not process.isRunning(proc)
	end)
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
---@field hostname string
---@field memtotal integer
---@field memfree integer

function syscalls.sysinfo()
	---@type Kocos.sysinfoResult
	return {
		kernel = _KVERSION,
		os = _OSVERSION,
		bootAddress = computer.getBootAddress(),
		memfree = computer.freeMemory(),
		memtotal = computer.totalMemory(),
		rootAddress = Kocos.fs.root.dev.address,
		hostname = Kocos.hostname,
	}
end

---@param addr string
function syscalls.chboot(addr)
	if type(addr) ~= "string" then
		return nil, errno.EINVAL
	end
	computer.setBootAddress(addr)
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
