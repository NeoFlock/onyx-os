--!lua

-- Setup log-in prompts or terminals

local vtty = require("vtty")

assert(k.invokeDaemon("displayd", "mksignaler"))

-- TODO: check for greeter program

if k.fcntl(0, "F_GETFL") then
	assert(k.exec("/bin/prompt.lua"))
	return 0
end

k.setexectime(4)

---@type table<string, vtty>
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
	}

	local w, h = controller.maxResolution()

	local term = vtty.create(controller, w, h, "login-term")
	screenTerms[screen] = term
	term:initController()
	term.hw[1] = screen

	local c, err = k.fork(function()
		for i=0,3 do k.close(i) end
		local stdout = k.openstream {
			flags = 0,
			write = function(_, data) term:write(data) return true end,
			read = function(_, len) return term:read(len) end,
			ioctl = function(_, action, ...) return term:ioctl(action, ...) end,
		}
		assert(stdout == 0)
		k.dup2(stdout, 1)
		k.dup2(stdout, 2)
		k.dup2(stdout, 3)
		assert(k.exec("/bin/prompt.lua"))
	end)

	if c then
		ttyNum = ttyNum + 1
		term:write(string.format("tty #%d (pid %d)\n", ttyNum, c))
	else
		term:write("Error: " .. err .. "\n")
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
				term:putEvent("key_down", kb, char, code)
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
				term:putEvent("key_up", kb, char, code)
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
				term:putEvent("clipboard", kb, code)
			end
			return
		end
	end
end)

local screens = getScreens()
for _, screen in ipairs(screens) do setupScreen(screen) end

k.kill(k.getpid(), "SIGSTOP")
coroutine.yield()
