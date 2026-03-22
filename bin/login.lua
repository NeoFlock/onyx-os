--!lua

-- Setup log-in prompts or terminals

local vtty = require("vtty")
local errnos = require("errnos")

assert(k.invokeDaemon("displayd", "mksignaler"))

-- TODO: check for greeter program

if k.isatty(3) then
	assert(k.exec("/bin/prompt.lua"))
	return 0
end

---@type table<string, {tty: vtty, master: integer}>
local screenTerms = {}

local ttyNum = 0

---@param screen string
local function setupScreen(screen)
	if screenTerms[screen] then return end
	---@type vtty.controller
	local controller = {
		maxResolution = function()
			return k.invokeDaemon("displayd", "maxResolution", screen)
		end,
		getResolution = function()
			return k.invokeDaemon("displayd", "getResolution", screen)
		end,
		setResolution = function(w, h)
			return k.invokeDaemon("displayd", "setResolution", screen, w, h)
		end,
		fill = function(x, y, w, h, c)
			return k.invokeDaemon("displayd", "fill", screen, x, y, w, h, c)
		end,
		copy = function(x, y, w, h, tx, ty)
			return k.invokeDaemon("displayd", "copy", screen, x, y, w, h, tx, ty)
		end,
		setForeground = function(c)
			return k.invokeDaemon("displayd", "setForeground", screen, c)
		end,
		setBackground = function(c)
			return k.invokeDaemon("displayd", "setBackground", screen, c)
		end,
		getForeground = function()
			return k.invokeDaemon("displayd", "getForeground", screen)
		end,
		getBackground = function()
			return k.invokeDaemon("displayd", "getBackground", screen)
		end,
		set = function(x, y, s)
			return k.invokeDaemon("displayd", "set", screen, x, y, s)
		end,
		get = function(x, y)
			return k.invokeDaemon("displayd", "get", screen, x, y)
		end,
		freeMemory = function()
			return k.invokeDaemon("displayd", "freeMemory")
		end,
		totalMemory = function()
			return k.invokeDaemon("displayd", "totalMemory")
		end,
		allocateBuffer = function(w, h)
			return k.invokeDaemon("displayd", "allocateBuffer", w, h)
		end,
		freeBuffer = function(buf)
			return k.invokeDaemon("displayd", "freeBuffer", buf)
		end,
		freeAllBuffers = function()
			return k.invokeDaemon("displayd", "freeAllBuffers")
		end,
		getActiveBuffer = function()
			return k.invokeDaemon("displayd", "getActiveBuffer")
		end,
		setActiveBuffer = function(buf)
			return k.invokeDaemon("displayd", "setActiveBuffer", buf)
		end,
		bitblt = function (dst, col, row, w, h, src, fromCol, fromRow)
			return k.invokeDaemon("displayd", "bitblt", dst, col, row, w, h, src, fromCol, fromRow)
		end,
		csiFallback = function() end,
		oscFallback = function() end,
	}

	local w, h = controller.maxResolution()

	local term = vtty.create(controller, w, h, "login-term")
	term:initController()
	term.hw[1] = screen

	local pair = assert(k.openpty(term:terminfo()))
	screenTerms[screen] = {tty = term, master = pair.master}

	local c, err = k.fork(function()
		k.close(pair.master)
		assert(k.switchpty(pair.slave))
		assert(k.exec("/bin/prompt.lua"))
	end)

	if c then
		ttyNum = ttyNum + 1
		term:write(string.format("tty #%d (pid %d)\n", ttyNum, c))
		k.invokeDaemon("initd", "log", "INFO", "login " .. screen .. ": new login with pid " .. c)
	else
		term:write("Error: " .. err .. "\n")
		k.invokeDaemon("initd", "log", "ERROR", "login " .. screen .. ": " .. err)
	end
end

---@return string[]
local function getScreens()
	return k.invokeDaemon("displayd", "getScreens")
end

k.signal("SIGSCRADD", setupScreen)

k.signal("SIGKEYDOWN", function(kb, char, code)
	for _, screen in ipairs(getScreens()) do
		local keyboards = k.invokeDaemon("displayd", "getKeyboards", screen) or {}
		if table.contains(keyboards, kb) then
			local term = screenTerms[screen]
			if term then
				term.tty:putEvent("key_down", kb, char, code)
			end
			return
		end
	end
end)

k.signal("SIGKEYUP", function(kb, char, code)
	for _, screen in ipairs(getScreens()) do
		local keyboards = k.invokeDaemon("displayd", "getKeyboards", screen) or {}
		if table.contains(keyboards, kb) then
			local term = screenTerms[screen]
			if term then
				term.tty:putEvent("key_up", kb, char, code)
			end
			return
		end
	end
end)

k.signal("SIGKEYPASTE", function(kb, code)
	for _, screen in ipairs(getScreens()) do
		local keyboards = k.invokeDaemon("displayd", "getKeyboards", screen) or {}
		if table.contains(keyboards, kb) then
			local term = screenTerms[screen]
			if term then
				term.tty:putEvent("clipboard", kb, code)
			end
			return
		end
	end
end)

local screens = getScreens()
for _, screen in ipairs(screens) do setupScreen(screen) end

while true do
	for _, term in pairs(screenTerms) do
		--term.tty:processBlink()
		local data = assert(k.read(term.master, math.huge))
		term.tty:write(data)
		assert(k.write(term.master, term.tty:read(math.huge)))
	end
	coroutine.yield()
end
