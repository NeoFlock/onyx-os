Kocos = {}

_KVERSION = "Kocos v0.-1.1"
_OSVERSION = _OSVERSION or "Unknown KOCOS"

local argv = {...}

---@alias Kocos.device {address: string, type: string, slot: integer}|table

Kocos.biotBootTime = computer.uptime()

---@type table<string, string>
Kocos.cmdline = {}

---@type string?
Kocos.ramfs = nil

---@param cmdline string
---@return table<string, string>
function Kocos.parseCmdline(cmdline)
	if cmdline == "" then return {} end
	local parts = string.split(cmdline, "\t")
	local t = {}

	for _, part in ipairs(parts) do
		local eql = string.find(part, "=")
		assert(eql, "malformed cmdline")
		local name, val = string.sub(part, 1, eql-1), string.sub(part, eql+1)
		t[name] = val
	end

	return t
end

---@param cmdline table<string, string>
---@return string
function Kocos.encodeCmdline(cmdline)
	local pairs = {}
	for k, v in pairs(cmdline) do
		table.insert(pairs, k .. "=" .. v)
	end
	return table.concat(pairs, "\t")
end

---@param name string
---@param default boolean
---@return boolean
function Kocos.getCmdlineBool(name, default)
	if Kocos.cmdline[name] == nil then return default end
	return Kocos.cmdline[name] == "true"
end

---@param name string
---@param default number
---@return number
function Kocos.getCmdlineNum(name, default)
	return tonumber(Kocos.cmdline[name]) or default
end

---@param name string
---@param default string
---@return string
function Kocos.getCmdlineStr(name, default)
	return Kocos.cmdline[name] or default
end

if argv[1] == "kocos" then
	Kocos.cmdline = Kocos.parseCmdline(argv[2] or "")
	Kocos.ramfs = argv[3]
elseif not argv[1] then
	-- generic boot protocol
else
	error("Unknown boot protocol")
end

Kocos.disableScreen = Kocos.getCmdlineBool("NO_SCR", false)
Kocos.disableDefaultPanicHandler = Kocos.getCmdlineBool("CUSTOM_PANIC", false)

Kocos.L_DEBUG = 0
Kocos.L_INFO = 1
Kocos.L_AUTOFIX = 2
Kocos.L_WARN = 3
Kocos.L_ERROR = 4
Kocos.L_PANIC = 5
Kocos.L_RAWTEXT = 6

Kocos.minLog = Kocos.getCmdlineNum("MIN_LOG", 0)

local oc = component.list("ocelot")()
local serial = component.list("serial")()

local gpu, screen = component.list("gpu")(), component.list("screen")()
if gpu and screen then
	component.invoke(gpu, "bind", screen)
end
local currentY = 0

function Kocos.clearscr()
	if not gpu then return end
	local w, h = component.invoke(gpu, "getResolution")
	component.invoke(gpu, "fill", 1, 1, w, h, " ")
	gpu = nil
	screen = nil
end

function Kocos.setprintcolor(clr)
	if gpu then
		component.invoke(gpu, "setForeground", clr)
	end
end

function Kocos.printk(severity, msg)
	local uptime = computer.uptime()

	if Kocos.notifyListeners then Kocos.notifyListeners("kocos_log", uptime, severity, msg) end

	if severity < Kocos.minLog then return end

	local names = {
		[Kocos.L_DEBUG] = "DEBUG",
		[Kocos.L_INFO] = "INFO",
		[Kocos.L_AUTOFIX] = "AUTOFIX",
		[Kocos.L_WARN] = "WARN",
		[Kocos.L_ERROR] = "ERROR",
		[Kocos.L_PANIC] = "PANIC",
	}

	local rawText = severity == Kocos.L_RAWTEXT and msg or string.format("[%5.3f %s] %s", uptime, names[severity] or "UNKNOWN", msg)
	if oc then
		component.invoke(oc, "log", rawText)
	end
	if serial then
		component.invoke(serial, "write", rawText .. "\n")
	end
	if gpu and screen and not Kocos.disableScreen then
		local w, h = component.invoke(gpu, "getResolution")

		currentY = currentY + 1
		while currentY >= h do
			component.invoke(gpu, "copy", 1, 1, w, h-1, 0, -1)
			currentY = currentY - 1
			component.invoke(gpu, "fill", 1, currentY, w, 1, " ")
		end
		component.invoke(gpu, "set", 1, currentY, rawText)
	end

	if severity == Kocos.L_PANIC then
		if Kocos.disableDefaultPanicHandler and Kocos.notifyListeners then
			Kocos.notifyListeners("kocos_panic", uptime, msg)
			return
		end
		Kocos.pull(5)
		computer.shutdown(true)
	end
end

function Kocos.printkf(severity, fmt, ...)
	Kocos.printk(severity, string.format(fmt, ...))
end

function Kocos.panick(msg)
	Kocos.printk(Kocos.L_PANIC, msg)
end

function Kocos.panickf(fmt, ...)
	Kocos.panick(string.format(fmt, ...))
end

Kocos.printk(Kocos.L_INFO, "Initializing...")

package.path = Kocos.getCmdlineStr("LD_PATH", package.path)
package.cpath = Kocos.getCmdlineStr("LD_CPATH", package.cpath)

Kocos.printkf(Kocos.L_DEBUG, "package.path: %s", package.path)
Kocos.printkf(Kocos.L_DEBUG, "package.cpath: %s", package.cpath)

---@diagnostic disable:lowercase-global
---@type table<string, function>
syscalls = {} -- syscalls defined later in other files

Kocos.execDeadline = math.huge

---@diagnostic disable: lowercase-global
---@param sysname string
---@return ...
function syscall(sysname, ...)
	-- TODO: syscall impl
	local proc = Kocos.currentProcess()
	if proc.state == "dead" then Kocos.sysyield() end

	local now = computer.uptime()
	if now > Kocos.execDeadline then Kocos.sysyield() end

	if proc.debugger then
		Kocos.sendSignal(proc.debugger, "SYSCALL", sysname, {...})
	end

	local sysfunc = syscalls[sysname]
	if not sysfunc then return nil, Kocos.ESRCH end

	local t = {pcall(sysfunc, ...)}

	if proc.debugger then
		Kocos.sendSignal(proc.debugger, "SYSRET", sysname, {...}, t)
	end

	if t[1] then
		return table.unpack(t, 2)
	end
	return nil, t[2]
end

function syscalls.syscalls()
	local t = {}
	for k in pairs(syscalls) do table.insert(t, k) end
	return t
end

-- file descriptor system

Kocos.O_NONBLOCK = 1
Kocos.O_CLOEXEC = 2

---@alias Kocos.descriptorReq "close"|"read"|"write"|"seek"|"accept"|"connect"|"listen"|"ioctl"

---@alias Kocos.descriptorEv "data_recv"|"data_written"|"connected"|"closed"|"accepting"

---@class Kocos.fileListener
---@field pid integer
---@field callback fun(ev: Kocos.descriptorEv, ...)

---@class Kocos.descriptor
---@field type "file"|"pipe"|"device"|"socket"
---@field state string
---@field rc integer
---@field flags integer
---@field pid integer
---@field handler fun(desc: Kocos.descriptor, ev: Kocos.descriptorReq, ...): ...
---@field evbuf? table[]
---@field listener? Kocos.fileListener

Kocos.MAX_HEVBUF = Kocos.getCmdlineNum("MAX_HEVBUF", 8)

---@param fd Kocos.descriptor
---@param ev Kocos.descriptorEv
function Kocos.notifyDescriptor(fd, ev, ...)
	if not fd.listener then
		fd.evbuf = fd.evbuf or {}
		table.insert(fd.evbuf, {ev, ...})
		while #fd.evbuf > Kocos.MAX_HEVBUF do table.remove(fd.evbuf, 1) end
		return
	end

	local proc = Kocos.processes[fd.listener.pid]
	if not proc then return end -- no one to notify

	Kocos.procCall(proc, fd.listener.callback, ev, ...)
end

---@param listener? Kocos.fileListener
function Kocos.setDescriptorListener(fd, listener)
	if listener and fd.evbuf then
		local proc = Kocos.processes[listener.pid]
		for _, ev in ipairs(fd.evbuf) do
			Kocos.procCall(proc, listener.callback, table.unpack(ev))
		end
		fd.evbuf = nil
	end
	fd.listener = listener
end

---@param fd Kocos.descriptor
---@param req Kocos.descriptorReq
---@return ...
function Kocos.handleDescriptorRequest(fd, req, ...)
	local proc = Kocos.processes[fd.pid]
	if not proc then return end
	local t = Kocos.procCall(proc, fd.handler, fd, req, ...)
	if t[1] then
		return table.unpack(t, 2)
	else
		return nil, tostring(t[2])
	end
end

---@param fd Kocos.descriptor
function Kocos.closeDescriptor(fd)
	fd.rc = fd.rc - 1
	if fd.rc > 0 then return end
	return Kocos.handleDescriptorRequest(fd, "close")
end
