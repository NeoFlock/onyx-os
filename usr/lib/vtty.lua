local errnos = require("errnos")
local keyboard = require("keyboard")
local keys = keyboard.keys

---@class vtty.controller
---@field maxResolution fun(): integer, integer
---@field getResolution fun(): integer, integer
---@field setResolution fun(w: integer, h: integer)
---@field set fun(x: integer, y: integer, s: string)
---@field get fun(x: integer, y: integer): string, integer, integer
---@field getForeground fun(): integer
---@field setForeground fun(c: integer)
---@field getBackground fun(): integer
---@field setBackground fun(c: integer)
---@field fill fun(x: integer, y: integer, w: integer, h: integer, c: string)
---@field copy fun(x: integer, y: integer, w: integer, h: integer, tx: integer, ty: integer)
---@field allocateBuffer fun(w: integer, h: integer): integer?, string?
---@field setActiveBuffer fun(buffer: integer)
---@field getActiveBuffer fun(): integer
---@field freeBuffer fun(buffer: integer?)
---@field freeAllBuffers fun()
---@field bitblt fun(dst?: integer, col?: integer, row?: integer, w?: integer, h?: integer, src?: integer, fromCol?: integer, fromRow?: integer)
---@field freeMemory fun(): integer
---@field totalMemory fun(): integer
---@field oscFallback fun(tty: vtty, s: string)
---@field csiFallback fun(tty: vtty, argStr: string, action: string)

---@class vtty
---@field controller vtty.controller
---@field x integer
---@field y integer
---@field sx integer
---@field sy integer
---@field keyUpEnabled boolean
---@field w integer
---@field h integer
---@field buf string
---@field keybuf string
---@field lightOn boolean
---@field stdColors table<integer, integer>
---@field color256 table<integer, integer>
---@field esc? string
---@field termname string
---@field hw string[]
---@field hwFeatures string[]
---@field defaultFg integer
---@field defaultBg integer
---@field keysHeld table<integer, boolean>
---@field target? integer
local vtty = {}
vtty.__index = vtty

-- past these, we assume OOM attack and flush in a panic
vtty.MAX_ESC = 1*1024
vtty.MAX_KEYBUF = 512

---@param r integer
---@param g integer
---@param b integer
function vtty.color(r, g, b)
	return r * 0x10000 + g * 0x100 + b
end

vtty.defaultTermName = "vtty-generic v0.0.1"

vtty.defaultStdColors = {
	-- taken from https://en.wikipedia.org/wiki/ANSI_escape_code#Control_Sequence_Introducer_commands
	-- Mix of VS Code and VGA.
	-- BG is auto-computed.
	[30] = vtty.color(0, 0, 0), -- black
	[31] = vtty.color(205, 49, 49), -- red
	[32] = vtty.color(13, 188, 121), -- green
	[33] = vtty.color(229, 229, 16), -- yellow
	[34] = vtty.color(36, 114, 200), -- blue
	[35] = vtty.color(188, 63, 188), -- magenta
	[36] = vtty.color(17, 168, 205), -- cyan
	[37] = vtty.color(229, 229, 229), -- white
	[90] = vtty.color(85, 85, 85), -- bright black (gray)
	[91] = vtty.color(255, 85, 85), -- bright red
	[92] = vtty.color(85, 255, 85), -- bright green
	[93] = vtty.color(255, 255, 85), -- bright yellow
	[94] = vtty.color(59, 142, 234), -- bright blue
	[95] = vtty.color(255, 85, 255), -- bright magenta
	[96] = vtty.color(85, 255, 255), -- bright cyan
	[97] = vtty.color(255, 255, 255), -- bright white
}

---@param stdClrs table<integer, integer>
---@return table<integer, integer>
function vtty.computeColor256(stdClrs)
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

	for red=0,5 do
		for green=0,5 do
			for blue=0,5 do
				local code = 16 + (red * 36) + (green * 6) + blue
				local r, g, b = 0, 0, 0
				if red ~= 0 then r = red * 40 + 55 end
				if green ~= 0 then g = green * 40 + 55 end
				if blue ~= 0 then b = blue * 40 + 55 end
				color256[code] = vtty.color(r, g, b)
			end
		end
	end

	for gray=0, 23 do
		local level = gray * 10 + 8
		local code = 232 + gray
		color256[code] = vtty.color(level, level, level)
	end
	return color256
end

---@param controller vtty.controller
---@param w integer
---@param h integer
---@param termname? string
---@param stdColors? table<integer, integer>
function vtty.create(controller, w, h, termname, stdColors)
	stdColors = stdColors or vtty.defaultStdColors
	termname = termname or vtty.defaultTermName
	return setmetatable({
		controller = controller,
		x = 1,
		y = 1,
		sx = 1,
		sy = 1,
		keyUpEnabled = false,
		w = w,
		h = h,
		buf = "",
		keybuf = "",
		lightOn = false,
		stdColors = stdColors,
		color256 = vtty.computeColor256(stdColors),
		termname = termname,
		hw = {},
		hwFeatures = {},
		defaultFg = stdColors[37],
		defaultBg = stdColors[30],
		keysHeld = {},
	}, vtty)
end

function vtty:initController()
	self.controller.setForeground(self.defaultFg)
	self.controller.setBackground(self.defaultBg)
	self.controller.setResolution(self.w, self.h)
	self.controller.fill(1, 1, self.w, self.h, " ")
end

function vtty:flush()
	self.controller.set(self.x - #self.buf, self.y, self.buf)
	self.buf = ""
end

function vtty:swapColors()
	local fg, bg = self.controller.getForeground(), self.controller.getBackground()
	self.controller.setForeground(bg)
	self.controller.setBackground(fg)
end

function vtty:toggleCursor()
	self.lightOn = not self.lightOn
	self:swapColors()
	local c = self.controller.get(self.x, self.y)
	self.controller.set(self.x, self.y, c)
end

function vtty:showCursor()
	if self.lightOn then return end
	self:toggleCursor()
end

function vtty:hideCursor()
	if not self.lightOn then return end
	self:toggleCursor()
end

function vtty:disableBlink()
	-- blinking is not yet implemented
	self:hideCursor()
end

function vtty:enableBlink()
	-- blinking is not yet implemented
	self:showCursor()
end

---@param contents string
---@param action string
function vtty:doCSI(contents, action)
	if action == "n" then
		if contents == "6" then
			self.keybuf = self.keybuf .. string.format("\x1b[%d;%dR", self.x, self.y)
			return
		end
		return
	end
	if action == "h" then
		if contents == "?25" then
			self:showCursor()
		end
		return
	end
	if action == "l" then
		if contents == "?25" then
			self:hideCursor()
		end
		return
	end
end

---@param cmd string
function vtty:doOSC(cmd)
	if cmd:sub(1,2) == "1;" then
		local ok, _, cx, cy, msg = string.find(cmd:sub(3), "([%d+]);([%d+]);(.*)")
		if ok then
			self.controller.set(tonumber(cx) or self.x, tonumber(cy) or self.y, msg)
		end
		return
	end
	self.controller.oscFallback(self, cmd)
end

---@param c string
function vtty:putc(c)
	if self.esc then
		if #self.esc >= vtty.MAX_ESC then
			self.esc = nil
			return
		end
		if c == "7" and #self.esc == 0 then
			self.sx = self.x
			self.sy = self.y
			self.esc = nil
			return
		end
		if c == "8" and #self.esc == 0 then
			self.x = self.sx
			self.y = self.sy
			self.esc = nil
			return
		end
		if c == "[" and #self.esc == 0 then
			-- CSI!!!
			self.esc = "["
			return
		end
		if c == "]" and #self.esc == 0 then
			-- OSC!!!
			self.esc = "]"
			return
		end
		if self.esc:sub(1,1) == "[" then
			-- CSIs!!
			if c:byte() >= 0x40 and c:byte() <= 0x7E then
				self:doCSI(self.esc:sub(2), c)
				self.esc = nil
				return
			end
			self.esc = self.esc .. c
			return
		end
		return
	end

	if c == "\n" then
		self:flush()
		self.y = self.y + 1
		self.x = 1
	elseif c == "\r" then
		self:flush()
		self.x = 1
	elseif c == "\t" then
		self:flush()
		self.x = self.x + 4
	elseif c == "\a" then
		self:flush()
		-- TODO: beep
	elseif c == "\b" then
		self:flush()
		if self.x > 1 then
			self.x = self.x - 1
			self.controller.set(self.x, self.y, " ")
		end
	elseif c == "\x1b" then
		self:flush()
		self.esc = ""
	else
		self.buf = self.buf .. c
		self.x = self.x + 1
	end

	if self.x > self.w then
		self:flush()
		self.x = 1
		self.y = self.y + 1
	end

	if self.y > self.h then
		self.controller.copy(1, 2, self.w, self.h-1, 0, -1)
		self.y = self.h
		self.controller.fill(1, self.y, self.w, 1, " ")
	end
end

---@param buf string
function vtty:write(buf)
	self:hideCursor()
	for i=1,unicode.len(buf) do
		self:putc(unicode.sub(buf, i, i))
	end
	self:flush()
end

---@vararg integer
---@return boolean
function vtty:isKeyHeld(...)
	local n = select("#", ...)
	for i=1,n do
		local k = select(i, ...)
		if self.keysHeld[k] then return true end
	end
	return false
end

---@return integer mods, boolean controlHeld
function vtty:getCurrentMods()
	local mods = 0
	local ctrl = false
	if self:isKeyHeld(keys.lshift, keys.rshift) then
		mods = mods + 1
	end
	if self:isKeyHeld(keys.lmenu, keys.rmenu) then
		mods = mods + 2
	end
	if self:isKeyHeld(keys.lcontrol, keys.rcontrol) then
		mods = mods + 4
		ctrl = true
	end
	if self:isKeyHeld(0) then -- meta
		mods = mods + 8
	end
	return mods, ctrl
end

--- Give an OC event to the terminal.
--- This can be key_down, key_up, clipboard
--- or mouse events.
---@param ev string
function vtty:putEvent(ev, ...)
	if #self.keybuf >= vtty.MAX_KEYBUF then
		self.keybuf = ""
	end
	if ev == "key_down" then
		local _, chr, cod = ...
		local mods, ctrl = self:getCurrentMods()
		self.keysHeld[cod] = true
		if ctrl then
			-- fix BS
			if cod == 0x20 then -- Ctrl-D
				self.keybuf = self.keybuf .. string.char(4)
				return
			end
			if cod == 0x2E then -- Ctrl-C
				chr = 3
			end
		end
		if chr == 3 then -- Ctrl-C
			if self.target then
				k.kill(self.target, "SIGINT")
			else
				self.keybuf = self.keybuf .. string.char(3)
			end
			return
		end
		if keyboard.isTerminalPrintable(chr) then
			self.keybuf = self.keybuf .. unicode.char(chr)
			return
		end
		if chr == 0x1b then
			self.keybuf = self.keybuf .. "\x1b\x1b"
			return
		end
		if mods == 0 then
			self.keybuf = self.keybuf .. string.format("\x1b[%d;%d~", chr, cod)
			return
		else
			self.keybuf = self.keybuf .. string.format("\x1b[%d;%d;%d~", chr, cod, mods)
			return
		end
		return
	end
	if ev == "key_up" then
		local _, chr, cod = ...
		local mods = self:getCurrentMods()
		self.keysHeld[cod] = false
		if self.keyUpEnabled then
			if mods == 0 then
				self.keybuf = self.keybuf .. string.format("\x1b[%d;%d^", chr, cod)
			else
				self.keybuf = self.keybuf .. string.format("\x1b[%d;%d;%d^", chr, cod, mods)
			end
		end
		return
	end
	if ev == "clipboard" then
		local _, data = ...
		self.keybuf = self.keybuf .. "\x1b[" .. tostring(#data) .. "|" .. data
		return
	end
end

function vtty:terminfo()
	return {
		termname = self.termname,
		hw = table.copy(self.hw),
		hw_features = table.copy(self.hwFeatures),
		term_features = {
			"ansicolor",
			"256color",
			"truecolor",
			"gpu",
			"vrambuf",
		},
		columns = self.w,
		lines = self.h,
	}
end

---@param action string
function vtty:ioctl(action, ...)
	if action == "setfgpid" then
		self.target = tonumber((...))
		return
	end
	if action == "terminfo" then
		return self:terminfo()
	end
	return nil, errnos.EINVAL
end

---@param len? integer
function vtty:read(len)
	len = math.min(len or math.huge, #self.keybuf)
	local oldbuf = self.keybuf:sub(1, len)
	self.keybuf = self.keybuf:sub(len+1)
	return oldbuf
end

return vtty
