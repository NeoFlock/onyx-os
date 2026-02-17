--!lua
-- This display manager only handles default GPUs

local errnos = require("errnos")

---@class displayd.screen
---@field fg integer
---@field bg integer
---@field w integer
---@field h integer

---@class displayd.buffer
---@field fg integer
---@field bg integer
---@field w integer
---@field h integer

---@type table<string, displayd.screen>
local screens = {}

---@type table<integer, displayd.buffer>
local bufs = {}

local displayd = {}

local utils = {}

function utils.getGPU()
	return assert(k.cprimary"gpu")
end

---@param addr string
function utils.switchToScreen(addr)
	local gpu = utils.getGPU()
	if gpu.getScreen() ~= addr or gpu.getActiveBuffer() ~= 0 then
		local screen = screens[addr]
		gpu.bind(addr)
		gpu.setActiveBuffer(0)
		gpu.setForeground(screen.fg)
		gpu.setBackground(screen.bg)
	end
end

---@param id integer
function utils.switchToBuffer(id)
	local gpu = utils.getGPU()
	if gpu.getActiveBuffer() ~= id then
		local buf = bufs[id]
		gpu.setActiveBuffer(id)
		gpu.setForeground(buf.fg)
		gpu.setBackground(buf.bg)
	end
end

---@param target string|integer
function utils.switchToTarget(target)
	if type(target) == "string" then
		utils.switchToScreen(target)
	else
		utils.switchToBuffer(target)
	end
end

---@type integer?
local signalPid = nil

---@param ev string
function utils.signal(ev, ...)
	if signalPid then
		assert(k.kill(signalPid, ev, ...))
	end
end

function displayd.hasBuffer(buffer)
	return bufs[buffer] ~= nil
end

function displayd.hasScreen(screen)
	return screens[screen] ~= nil
end

---@return string[]
function displayd.getScreens()
	local s = {}
	for id in pairs(screens) do table.insert(s, id) end
	return s
end

---@return integer[]
function displayd.getBuffers()
	local b = {}
	for id in pairs(bufs) do table.insert(b, id) end
	return b
end

---@param target string|integer
---@param x integer
---@param y integer
---@param v string
---@param vert boolean
function displayd.set(target, x, y, v, vert)
	utils.switchToTarget(target)
	utils.getGPU().set(x, y, v, vert)
	return true
end

---@param target string|integer
---@param x integer
---@param y integer
---@param w integer
---@param h integer
---@param c string
function displayd.fill(target, x, y, w, h, c)
	utils.switchToTarget(target)
	utils.getGPU().fill(x, y, w, h, c)
	return true
end

---@param target string|integer
---@param x integer
---@param y integer
---@param w integer
---@param h integer
---@param tx integer
---@param ty integer
function displayd.copy(target, x, y, w, h, tx, ty)
	utils.switchToTarget(target)
	utils.getGPU().copy(x, y, w, h, tx, ty)
	return true
end

---@param target string|integer
---@param c integer
function displayd.setForeground(target, c)
	utils.switchToTarget(target)
	if type(target) == "string" then
		screens[target].fg = c
	end
	if type(target) == "number" then
		bufs[target].fg = c
	end
	utils.getGPU().setForeground(c)
	return true
end

---@param target string|integer
---@param c integer
function displayd.setBackground(target, c)
	utils.switchToTarget(target)
	if type(target) == "string" then
		screens[target].bg = c
	end
	if type(target) == "number" then
		bufs[target].bg = c
	end
	utils.getGPU().setBackground(c)
	return true
end

---@param target string|integer
function displayd.getResolution(target)
	utils.switchToTarget(target)
	return utils.getGPU().getBufferSize()
end

---@param target string|integer
function displayd.maxResolution(target)
	utils.switchToTarget(target)
	return utils.getGPU().maxResolution()
end

---@param target string|integer
---@param x integer
---@param y integer
function displayd.get(target, x, y)
	utils.switchToTarget(target)
	return utils.getGPU().get(x, y)
end

---@param target string|integer
function displayd.getForeground(target)
	utils.switchToTarget(target)
	return utils.getGPU().getForeground()
end

---@param target string|integer
function displayd.getBackground(target)
	utils.switchToTarget(target)
	return utils.getGPU().getBackground()
end

---@param screen string
---@param w integer
---@param h integer
function displayd.setResolution(screen, w, h)
	utils.switchToScreen(screen)
	utils.getGPU().setResolution(w, h)
	return true
end

function displayd.freeMemory()
	return utils.getGPU().freeMemory()
end

function displayd.totalMemory()
	return utils.getGPU().totalMemory()
end

function displayd.freeAllBuffers()
	utils.getGPU().freeAllBuffers()
	bufs = {}
	return true
end

---@param buf integer
function displayd.freeBuffer(buf)
	utils.getGPU().freeBuffer(buf)
	bufs[buf] = nil
	return true
end

---@param w integer
---@param h integer
---@return integer?, string?
function displayd.allocateBuffer(w, h)
	local buf, err = utils.getGPU().allocateBuffer(w, h)
	if buf then
		bufs[buf] = {
			w = w,
			h = h,
			fg = utils.getGPU().getForeground(),
			bg = utils.getGPU().getBackground(),
		}
	end
	return buf, err
end

---@param dst string|integer
---@param col integer
---@param row integer
---@param w integer
---@param h integer
---@param src string|integer
---@param fromCol integer
---@param fromRow integer
function displayd.bitblt(dst, col, row, w, h, src, fromCol, fromRow)
	if type(dst) == "string" then
		utils.switchToScreen(dst)
		dst = 0
	end
	if type(src) == "string" then
		utils.switchToScreen(src)
		src = 0
	end
	return utils.getGPU().bitblt(dst, col, row, w, h, src, fromCol, fromRow)
end

---@type table<string, string[]>
local kbCache = {}

---@param screen string
function displayd.getKeyboards(screen)
	if kbCache[screen] then return kbCache[screen] end
	local l, err = k.cinvoke(screen, "getKeyboards")
	if not l then return l, err end
	kbCache[screen] = l
	return l
end

---@param screen string
function displayd.turnOn(screen)
	return k.cinvoke(screen, "turnOn")
end

---@param screen string
function displayd.turnOff(screen)
	return k.cinvoke(screen, "turnOff")
end

---@param screen string
function displayd.isOn(screen)
	return k.cinvoke(screen, "isOn")
end

local evs = {}

---@param addr string
---@param type string
function evs.component_added(addr, type)
	if type ~= "screen" then return end
	---@type displayd.screen
	local s = {
		fg = 0xFFFFFF,
		bg = 0x000000,
		w = 0,
		h = 0,
	}
	screens[addr] = s
	utils.switchToScreen(addr)
	s.w, s.h = utils.getGPU().getResolution()
	utils.signal("SIGSCRADD", addr)
end

---@param addr string
---@param type string
function evs.component_removed(addr, type)
	if type == "screen" then
		kbCache[addr] = nil -- no point
		screens[addr] = nil -- bye bye bye
		utils.signal("SIGSCRREM", addr)
	end
	if type == "keyboard" then
		for _, l in pairs(kbCache) do
			for i=#l,1,-1 do
				if l[i] == addr then table.remove(l, i) end
			end
		end
	end
end

function evs.screen_resized(addr, w, h)
	screens[addr].w = w
	screens[addr].h = h
	utils.signal("SIGWINCH", addr, w, h)
end

function evs.touch(screen, x, y, button)
	utils.signal("SIGWINTOUCH", screen, x, y, button)
end

function evs.drag(screen, x, y, button)
	utils.signal("SIGWINDRAG", screen, x, y, button)
end

function evs.drop(screen, x, y, button)
	utils.signal("SIGWINDROP", screen, x, y, button)
end

function evs.scroll(screen, x, y, dir)
	utils.signal("SIGWINSCROLL", screen, x, y, dir)
end

function evs.walk(screen, x, y)
	utils.signal("SIGWINWALK", screen, x, y)
end

function evs.key_down(keyboard, char, code)
	utils.signal("SIGKEYDOWN", keyboard, char, code)
end

function evs.key_up(keyboard, char, code)
	utils.signal("SIGKEYUP", keyboard, char, code)
end

function evs.clipboard(keyboard, value)
	utils.signal("SIGKEYPASTE", keyboard, value)
end

assert(k.registerDaemon("displayd", function(cpid, action, ...)
	if not k.isproot(cpid) then
		--return nil, errnos.EACCESS
	end

	-- NASTY, might be a compromised process!
	if type(action) ~= "string" then
		return nil, errnos.EINVAL
	end

	if action == "mksignaler" then
		signalPid = cpid
		return true
	end

	if not displayd[action] then
		return nil, errnos.EPROTONOSUPPORT
	end

	return displayd[action](...)
end))

assert(k.mklistener(function(ev, ...)
	if evs[ev] then
		evs[ev](...)
	end
end))

for addr, type in k.clist() do
	evs.component_added(addr, type)
end

k.invokeDaemon("initd", "disableLogger")
k.invokeDaemon("initd", "markComplete")

k.kill(k.getpid(), "SIGSTOP")
coroutine.yield()
