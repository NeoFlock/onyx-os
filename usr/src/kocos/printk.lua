Kocos.L_DEBUG = 0
Kocos.L_INFO = 1
Kocos.L_AUTOFIX = 2
Kocos.L_WARN = 3
Kocos.L_ERROR = 4
Kocos.L_PANIC = 5

local oc = component.list("ocelot")()

---@param text string
function Kocos.scr_write(text)
	-- No screen available
end

---@param len integer
---@return string?
function Kocos.scr_read(len)
	return nil -- no input source available
end

function Kocos._scr_reader(...)
	-- nothing to react to
end

---@return string[]
function Kocos.scr_addrs()
	return {}
end

---@param action string
---@param ... any
---@return ...
function Kocos.scr_ioctl(action, ...)

end

local gpu, screen = component.list("gpu")(), component.list("screen")()

if gpu and screen then
	component.invoke(gpu, "bind", screen)

	local x, y = 1, 1
	local w, h = component.invoke(gpu, "maxResolution")

	local buf = ""
	local keybuf = ""

	local targetPid

	local function flush()
		component.invoke(gpu, "set", x - #buf, y, buf)
		buf = ""
	end

	local function color(r, g, b)
		return r * 0x10000 + g * 0x100 + b
	end

	---@type integer?
	local blinkTimer = nil
	local lightOn = false

	local function swapColors()
		local fg = component.invoke(gpu, "getForeground")
		local bg = component.invoke(gpu, "getBackground")
		component.invoke(gpu, "setForeground", bg)
		component.invoke(gpu, "setBackground", fg)
	end

	local function showCursor()
		if lightOn then return end
		lightOn = true
		swapColors()
		local c = component.invoke(gpu, "get", x, y)
		component.invoke(gpu, "set", x, y, c)
	end

	local function hideCursor()
		if not lightOn then return end
		lightOn = false
		swapColors()
		local c = component.invoke(gpu, "get", x, y)
		component.invoke(gpu, "set", x, y, c)
	end

	local function toggleCursor()
		if lightOn then
			hideCursor()
		else
			showCursor()
		end
	end

	local function disableBlink()
		if not blinkTimer then return end
		Kocos.event.cancel(blinkTimer)
		blinkTimer = nil
	end

	local function enableBlink()
		if blinkTimer then return end
		blinkTimer = Kocos.event.timer(0.5, function()
			if Kocos.disableScreen then disableBlink() end
			toggleCursor()
		end, math.huge)
	end

	local stdClrs = Kocos.args.termStdColors or {
		-- taken from https://en.wikipedia.org/wiki/ANSI_escape_code#Control_Sequence_Introducer_commands
		-- Mix of VS Code and VGA.
		-- BG is auto-computed.
		[30] = color(0, 0, 0), -- black
		[31] = color(205, 49, 49), -- red
		[32] = color(13, 188, 121), -- green
		[33] = color(229, 229, 16), -- yellow
		[34] = color(36, 114, 200), -- blue
		[35] = color(188, 63, 188), -- magenta
		[36] = color(17, 168, 205), -- cyan
		[37] = color(229, 229, 229), -- white
		[90] = color(85, 85, 85), -- bright black (gray)
		[91] = color(255, 85, 85), -- bright red
		[92] = color(85, 255, 85), -- bright green
		[93] = color(255, 255, 85), -- bright yellow
		[94] = color(59, 142, 234), -- bright blue
		[95] = color(255, 85, 255), -- bright magenta
		[96] = color(85, 255, 255), -- bright cyan
		[97] = color(255, 255, 255), -- bright white
	}

	local defaultFg = Kocos.args.termDefaultFg or stdClrs[37]
	local defaultBg = Kocos.args.termDefaultBg or stdClrs[30]

	component.invoke(gpu, "setForeground", defaultFg)
	component.invoke(gpu, "setBackground", defaultBg)

	component.invoke(gpu, "setResolution", w, h)
	component.invoke(gpu, "fill", 1, 1, w, h, " ")

	local color256 = {
		[0] = stdClrs[30],
		[1] = stdClrs[31],
		[2] = stdClrs[32],
		[3] = stdClrs[33],
		[4] = stdClrs[34],
		[5] = stdClrs[35],
		[6] = stdClrs[36],
		[7] = stdClrs[37],
		[8] = stdClrs[90],
		[9] = stdClrs[91],
		[10] = stdClrs[92],
		[11] = stdClrs[93],
		[12] = stdClrs[94],
		[13] = stdClrs[95],
		[14] = stdClrs[96],
		[15] = stdClrs[97],
	}

	local esc = nil

	for red=0,5 do
		for green=0,5 do
			for blue=0,5 do
				local code = 16 + (red * 36) + (green * 6) + blue
				local r, g, b = 0, 0, 0
				if red ~= 0 then r = red * 40 + 55 end
				if green ~= 0 then g = green * 40 + 55 end
				if blue ~= 0 then b = blue * 40 + 55 end
				color256[code] = color(r, g, b)
			end
		end
	end

	for gray=0, 23 do
		local level = gray * 10 + 8
		local code = 232 + gray
		color256[code] = color(level, level, level)
	end

	local isKeyUpEnabled = false

	local sx, sy = 1, 1

	local MAX_ESC = 1*1024

	---@param contents string
	---@param action string
	local function doCSI(contents, action)
		-- CSIs can have "intermediate bytes", for some fucking reason
		local params = ""

		while #contents > 0 and contents:byte() >= 0x30 and contents:byte() <= 0x3F do
			params = params .. contents:sub(1, 1)
			contents = contents:sub(2)
		end

		---@type (number?)[]
		local nums = string.split(params, ";")
		for i=1,#nums do nums[i] = tonumber(nums[i]) end

		if action == "A" then
			local n = nums[1] or 1
			y = math.clamp(y - n, 1, h)
			return
		end
		if action == "B" then
			local n = nums[1] or 1
			y = math.clamp(y + n, 1, h)
			return
		end
		if action == "C" then
			local n = nums[1] or 1
			x = math.clamp(x + n, 1, w)
			return
		end
		if action == "D" then
			local n = nums[1] or 1
			x = math.clamp(x - n, 1, w)
			return
		end
		if action == "E" then
			local n = nums[1] or 1
			x = 1
			y = math.clamp(y + n, 1, h)
			return
		end
		if action == "F" then
			local n = nums[1] or 1
			x = 1
			y = math.clamp(y - n, 1, h)
			return
		end
		if action == "G" then
			local n = nums[1] or 1
			x = math.clamp(n, 1, w)
			return
		end
		if action == "H" then
			local n = nums[1] or 1
			local m = nums[2] or 1
			x = math.clamp(n, 1, w)
			y = math.clamp(m, 1, h)
			return
		end
		if action == "J" then
			local n = nums[1] or 0
			if n == 0 then
				component.invoke(gpu, "fill", x, y, w - x + 1, 1, " ")
				component.invoke(gpu, "fill", 1, y+1, 1, h-y, " ")
			elseif n == 1 then
				component.invoke(gpu, "fill", 1, 1, 1, y-1, " ")
				component.invoke(gpu, "fill", 1, y, x, 1, " ")
			elseif n == 2 then
				component.invoke(gpu, "fill", 1, 1, w, h, " ")
			end
			return
		end
		if action == "K" then
			local n = nums[1] or 0
			if n == 0 then
				component.invoke(gpu, "fill", x, y, w - x + 1, 1, " ")
			elseif n == 1 then
				component.invoke(gpu, "fill", 1, y, x, 1, " ")
			elseif n == 2 then
				component.invoke(gpu, "fill", 1, y, w, 1, " ")
			end
			return
		end
		if action == "S" then
			local n = nums[1] or 1
			component.invoke(gpu, "copy", 1, 1, w, h, 0, n)
			component.invoke(gpu, "fill", 1, 1, w, n, " ")
			y = math.clamp(y - n, 1, h)
			return
		end
		if action == "T" then
			local n = nums[1] or 1
			component.invoke(gpu, "copy", 1, 1, w, h, 0, -n)
			component.invoke(gpu, "fill", 1, h-n+1, w, n, " ")
			y = math.clamp(y - n, 1, h)
			return
		end
		if action == "m" then
			---@cast nums (number?)[]
			local function pop()
				return table.remove(nums, 1) or 0
			end
			if #nums == 0 then nums = {0} end
			while #nums > 0 do
				local op = pop()
				if op == 0 then
					component.invoke(gpu, "setForeground", defaultFg)
					component.invoke(gpu, "setBackground", defaultBg)
				elseif op == 7 then
					swapColors()
				elseif op == 8 then
					-- TODO: conceal
				elseif op == 28 then
					-- TODO: conceal
				elseif op >= 30 and op <= 37 then
					component.invoke(gpu, "setForeground", stdClrs[op])
				elseif op >= 90 and op <= 97 then
					component.invoke(gpu, "setForeground", stdClrs[op])
				elseif op >= 40 and op <= 47 then
					component.invoke(gpu, "setBackground", stdClrs[op-10])
				elseif op >= 100 and op <= 107 then
					component.invoke(gpu, "setBackground", stdClrs[op-10])
				elseif op == 38 then
					local clr = defaultFg
					local n = pop()
					if n == 5 then
						clr = color256[pop()]
					elseif n == 2 then
						local r = pop()
						local g = pop()
						local b = pop()
						clr = color(r,g,b)
					end
					component.invoke(gpu, "setForeground", clr)
				elseif op == 48 then
					local clr = defaultBg
					local n = pop()
					if n == 5 then
						clr = color256[pop()]
					elseif n == 2 then
						local r = pop()
						local g = pop()
						local b = pop()
						clr = color(r,g,b)
					end
					component.invoke(gpu, "setBackground", clr)
				elseif op == 39 then
					component.invoke(gpu, "setForeground", defaultFg)
				elseif op == 49 then
					component.invoke(gpu, "setBackground", defaultBg)
				end
			end
			return
		end
		if action == "n" then
			if nums[1] == 6 then
				keybuf = keybuf .. string.format("\x1b[%d;%dR", x, y)
				return
			end
			if nums[1] == 7 then
				keybuf = keybuf .. string.format("\x1b[%d;%dR", w, h)
				return
			end
			if nums[1] == 8 then
				local mw, mh = component.invoke(gpu, "maxResolution")
				keybuf = keybuf .. string.format("\x1b[%d;%dR", mw, mh)
				return
			end
			return
		end
		if action == "i" then
			-- dont care about AUX port
			return
		end
		if action == "h" then
			if params == "?25" then
				enableBlink()
				showCursor()
				return
			end
			if params == "?1004" then
				-- Not applicable
				return
			end
			if params == "?2004" then
				isKeyUpEnabled = true
				return
			end
			return
		end
		if action == "l" then
			if params == "?25" then
				disableBlink()
				hideCursor()
				return
			end
			if params == "?1004" then
				-- Not applicable
				return
			end
			if params == "?2004" then
				isKeyUpEnabled = false
				return
			end
			return
		end
		if action == "U" then
			if nums[1] == 1 then
				component.invoke(gpu, "fill", nums[2] or 1, nums[3] or 1, nums[4] or w, nums[5] or h, unicode.char(nums[6] or 32))
				return
			end
			if nums[1] == 2 then
				component.invoke(gpu, "copy", nums[2] or 1, nums[3] or 1, nums[4] or w, nums[5] or h, nums[6] or 0, nums[7] or 0)
				return
			end
			if nums[1] == 3 then
				local _w = nums[2] or w
				local _h = nums[3] or h
				if component.invoke(gpu, "setResolution", _w, _h) then
					w = _w
					h = _h
				end
				return
			end
			if nums[1] == 4 then
				local x = nums[2] or x
				local y = nums[3] or y
				local c, f, g = component.invoke(gpu, "get", x, y)
				keybuf = keybuf .. string.format("\x1b[%d;%d;%dR", string.byte(c), f, g)
				return
			end
			return
		end
		if action == "v" then
			if nums[1] == 1 then
				local free = component.invoke(gpu, "freeMemory") or 0
				local total = component.invoke(gpu, "totalMemory") or 0
				keybuf = keybuf .. string.format("\x1b[%d;%dR", free, total)
				return
			end
			return
		end
	end

	---@param cmd string
	local function doOSC(cmd)
		if cmd:sub(1, 2) == "0;" then
			Kocos.printk(Kocos.L_WARN, cmd:sub(3))
		end
		if cmd:sub(1, 2) == "1;" then
			local ok, _, cx, cy, msg = string.find(cmd:sub(3), "([%d+]);([%d+]);(.*)")
			if ok then
				component.invoke(gpu, "set", tonumber(cx) or x, tonumber(cy) or y, msg)
			end
		end
	end

	local lastbeep = 0
	local beepinterval = 5

	local function putc(c)
		if esc then
			if #esc == MAX_ESC then
				esc = nil -- yeah no
				return
			end
			if c == "7" and #esc == 0 then
				sx, sy = x, y
				esc = nil
				return
			end
			if c == "8" and #esc == 0 then
				x, y = sx, sy
				esc = nil
				return
			end
			if c == ']' and #esc == 0 then
				esc = ']' -- OSC!!!
				return
			end
			if c == '[' and #esc == 0 then
				esc = '[' -- CSI!!!
				return
			end
			if esc:sub(1, 1) == '[' then
				-- CSI
				if c:byte() >= 0x40 and c:byte() <= 0x7E then
					local ok, err = pcall(doCSI, esc:sub(2), c)
					esc = nil
					if not ok then
						Kocos.printk(Kocos.L_ERROR, err)
					end
					return
				end
				esc = esc .. c
				return
			end
			if esc:sub(1, 1) == ']' then
				-- OSC
				esc = esc .. c
				local terms = {"\a", "\x1b\\"}
				for _, term in ipairs(terms) do
					if esc:sub(-#term) == term then
						local ok, err = pcall(doOSC, esc:sub(2, -#term - 1))
						esc = nil
						if not ok then
							Kocos.printk(Kocos.L_ERROR, err)
						end
						return
					end
				end
				return
			end
			esc = nil -- bad escape
			return
		end
		if c == "\n" then
			flush()
			y = y + 1
			x = 1
		elseif c == "\r" then
			flush()
			x = 1
		elseif c == "\t" then
			flush()
			x = x + 4
		elseif c == "\a" then
			flush()
			local now = computer.uptime()
			-- super slow so we cap it
			if now - lastbeep > beepinterval then
				--computer.beep(200, 0.01) -- just super slow
				lastbeep = now
			end
		elseif c == "\b" then
			flush()
			if x > 1 then
				x = x - 1
				component.invoke(gpu, "set", x, y, " ")
			end
		elseif c == "\x1b" then
			flush()
			esc = ""
		else
			buf = buf .. c
			x = x + 1
		end

		if x > w then
			flush()
			x = 1
			y = y + 1
		end

		if y > h then
			component.invoke(gpu, "copy", 1, 2, w, h-1, 0, -1)
			y = h
			component.invoke(gpu, "fill", 1, y, w, 1, " ")
		end
	end

	function Kocos.scr_write(text)
		if Kocos.disableScreen then return end
		hideCursor()
		for i=1,unicode.len(text) do
			putc(unicode.sub(text, i, i))
		end
		flush()
	end

	local keyboard = component.invoke(screen, "getKeyboards")[1]

	local function isTerminalPrintable(char)
		return (char >= 3 and char <= 20) or (char >= 32)
	end

	local keysHeld = {}

	function Kocos._scr_reader(ev, kbAddr, chr, cod)
		if Kocos.disableScreen then return end
		if kbAddr ~= keyboard then return end
		local mods = 0
		local ctrl = false
		if keysHeld[0x2A] or keysHeld[0x36] then -- shift
			mods = mods + 1
		end
		if keysHeld[0x38] or keysHeld[0xB8] then -- alt / menu
			mods = mods + 2
		end
		if keysHeld[0x1D] or keysHeld[0x9D] then -- control
			mods = mods + 4
			ctrl = true
		end
		if keysHeld[0] then -- meta
			mods = mods + 8
		end
		if ev == "key_down" then
			keysHeld[cod] = true
			local target = Kocos.process.allProcs[targetPid]
			if ctrl then
				-- to fix possible complications on other environments
				if cod == 0x20 then
					keybuf = keybuf .. string.char(4) -- Ctrl-D
					return
				end
				if cod == 0x2E then -- Ctrl-C
					if target then
						Kocos.process.raise(target, Kocos.process.SIGINT)
					else
						keybuf = keybuf .. string.char(3)
					end
					return
				end
			end
			if chr == 3 then -- also Ctrl-C
				if target then
					Kocos.process.raise(target, Kocos.process.SIGINT)
				else
					keybuf = keybuf .. string.char(3)
				end
				return
			end
			if isTerminalPrintable(chr) then
				keybuf = keybuf .. unicode.char(chr)
				return
			end
			if chr == 0x1b then
				keybuf = keybuf .. "\x1b\x1b"
				return
			end
			if mods == 0 then
				keybuf = keybuf .. string.format("\x1b[%d;%d~", chr, cod)
			else
				keybuf = keybuf .. string.format("\x1b[%d;%d;%d~", chr, cod, mods)
			end
			return
		end
		if ev == "key_up" then
			keysHeld[cod] = false
			if isKeyUpEnabled then
				if mods == 0 then
					keybuf = keybuf .. string.format("\x1b[%d;%d^", chr, cod)
				else
					keybuf = keybuf .. string.format("\x1b[%d;%d;%d^", chr, cod, mods)
				end
			end
			return
		end
		if ev == "clipboard" then
			keybuf = keybuf .. "\x1b[" .. tostring(#chr) .. "|" .. chr
			return
		end
	end

	---@param len integer
	---@return string?
	function Kocos.scr_read(len)
		if Kocos.disableScreen then return end
		len = math.min(len, #keybuf)
		local oldbuf = keybuf:sub(1, len)
		keybuf = keybuf:sub(len+1)
		return oldbuf
	end

	---@return string[]
	function Kocos.scr_addrs()
		return {gpu, screen, keyboard}
	end

	---@param action string
	---@param ... any
	---@return ...
	function Kocos.scr_ioctl(action, ...)
		if action == "setfgpid" then
			targetPid = ...
			return
		end
		if action == "terminfo" then
			local hw_features = {}
			local depth = component.invoke(gpu, "getDepth")
			local hasVRAM = component.invoke(gpu, "totalMemory")

			if depth > 1 then
				table.insert(hw_features, "color")
			end
			if depth > 4 then
				table.insert(hw_features, "truecolor")
			end
			if hasVRAM then
				table.insert(hw_features, "vrambuf")
			end

			return {
				termname = "kocos-vtty-gpu",
				hw = Kocos.scr_addrs(),
				hw_features = hw_features,
				term_features = {
					"ansicolor",
					"256color",
					"truecolor",
					"gpu",
					"vrambuf",
				},
				columns = w,
				lines = h,
			}
		end
		return nil, Kocos.errno.EINVAL
	end
end

Kocos.event.listen(Kocos._scr_reader)

---@param text string
function Kocos.writelog(text)
	-- No version when output available
	if oc and not Kocos.args.noOcelotLog then
		component.invoke(oc, "log", text)
	end
	-- typically done after boot to not fight the kernel logger
	if Kocos.disableScreenLogging then return end
	Kocos.scr_write(text)
end

function Kocos.printk(severity, msg)
	local uptime = computer.uptime()

	Kocos.event.notifyListeners("kocos_log", uptime, severity, msg)

	if Kocos.args.minLog then
		if severity < Kocos.args.minLog then return end
	end

	local names = {
		[Kocos.L_DEBUG] = "DEBUG",
		[Kocos.L_INFO] = "INFO",
		[Kocos.L_AUTOFIX] = "AUTOFIX",
		[Kocos.L_WARN] = "WARN",
		[Kocos.L_ERROR] = "ERROR",
		[Kocos.L_PANIC] = "PANIC",
	}

	local colors = {
		[Kocos.L_DEBUG] = 2,
		[Kocos.L_INFO] = 12,
		[Kocos.L_AUTOFIX] = 8,
		[Kocos.L_WARN] = 3,
		[Kocos.L_ERROR] = 1,
		[Kocos.L_PANIC] = 9,
	}

	local color, reset = "", ""

	color = "\x1b[38;5;" .. tostring(colors[severity] or 0) .. "m"

	reset = "\x1b[0m"

	local rawText = string.format("[%5.3f %s%s%s] %s\n", uptime, color, names[severity] or "UNKNOWN", reset, msg)
	Kocos.writelog(rawText)

	if severity == Kocos.L_PANIC then
		if Kocos.disableDefaultPanicHandler then
			Kocos.event.notifyListeners("kocos_panic", uptime, msg)
			return
		end
		pcall(Kocos.event.pull, 5)
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

Kocos.printk(Kocos.L_DEBUG, "printk loaded")
