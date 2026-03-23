-- New process system

local sched = {}

local nid = 0
function sched.nextID()
	nid = nid + 1
	return nid
end

---@class Kocos.schedThread
---@field coro thread
---@field tid integer
---@field pid integer
---@field pendingSyscall? thread

---@type table<integer, Kocos.schedThread>
sched.threads = {}

---@class Kocos.schedProc
---@field state "alive"|"exited"|"dying"|"dead"
---@field pid integer
---@field uid integer
---@field gid integer
---@field argv string[]
---@field env table<string, string>
---@field parent? Kocos.schedProc
---@field children table<integer, Kocos.schedProc>
---@field stopped boolean
---@field cwd string
---@field root string
---@field exe string
---@field exitcode integer
---@field debugger? Kocos.schedProc
---@field daemon? string
---@field evListener? function
---@field signalHandlers table<string, function>
---@field proclocal table
---@field fds table<integer, Kocos.descriptor>
---@field namespace _G
---@field threads integer[]
--- Coroutines for signal handlers
---@field pendingSignals thread[]
--- Pending daemon invokes
---@field pendingInvokes integer[]
---@field waitingOnDaemon integer[]

---@type table<integer, Kocos.schedProc>
sched.procs = {}

---@class Kocos.schedInvoke
---@field daemonPid integer
---@field clientPid integer
---@field coro thread

---@type table<integer, Kocos.schedInvoke>
sched.invokes = {}

local kernelExec = Kocos.getCmdlineStr("KPATH", "/boot/vmkocos")

---@type Kocos.schedProc
sched.kernel = {
	state = "alive",
	pid = 0,
	uid = 0,
	gid = 0,
	argv = {[0] = kernelExec},
	env = {},
	exe = kernelExec,
	cwd = "/",
	root = "/",
	parent = nil,
	children = {},
	exitcode = 0,
	fds = {},
	namespace = _G,
	pendingInvokes = {},
	pendingSignals = {},
	proclocal = {},
	signalHandlers = {},
	stopped = false,
	threads = {},
	daemon = nil,
	debugger = nil,
	evListener = nil,
	waitingOnDaemon = {},
}

sched.procs[0] = sched.kernel

sched.current = sched.kernel

---@param proc Kocos.schedProc
---@param handle Kocos.descriptor
---@return integer
function sched.moveFd(proc, handle)
	local fd = 0
	while proc.fds[fd] do fd = fd + 1 end
	proc.fds[fd] = handle
	return fd
end

---@param proc Kocos.schedProc
---@param exit integer
function sched.exitProcess(proc, exit)
	if proc.state ~= "alive" then return end
	proc.state = "exited"
	proc.exitcode = exit
	if proc.parent then
	end

	for _, f in pairs(proc.fds) do
		Kocos.closeDescriptor(f)
	end
	proc.fds = {}

	if sched.current == proc then
		Kocos.sysyield()
		return
	end
end

Kocos.sched = sched
