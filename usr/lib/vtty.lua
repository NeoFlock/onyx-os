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
---@field blinktimer? integer
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
		blinktimer = nil,
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
	local c = self.controller.get(self.x, self.y)
	self:swapColors()
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
	if not self.blinktimer then return end
	k.close(self.blinktimer)
	self.blinktimer = nil
end

function vtty:enableBlink()
	-- blinking is not yet implemented
	if self.blinktimer then return end
	self.blinktimer = assert(k.mktimer(0.5, function()
		self:toggleCursor()
	end, math.huge))
end

---@param n? integer
function vtty:scrollUp(n)
	n = n or 1
	local w, h = self.controller.getResolution()
	self.controller.copy(1, 1, w, h, 0, -n)
	self.controller.fill(1, h-n+1, w, n, " ")
	self.y = math.clamp(self.y - n, 1, h)
end

---@param n? integer
function vtty:scrollDown(n)
	n = n or 1
	local w, h = self.controller.getResolution()
	self.controller.copy(1, 1, w, h, 0, n)
	self.controller.fill(1, 1, w, n, " ")
	self.y = math.clamp(self.y + n, 1, h)
end

---@param contents string
---@param action string
function vtty:doCSI(contents, action)
	-- CSIs can have "intermediate bytes", for some fucking reason
	local params = ""

	while #contents > 0 and contents:byte() >= 0x30 and contents:byte() <= 0x3F do
		params = params .. contents:sub(1, 1)
		contents = contents:sub(2)
	end

	---@type (number?)[]
	local nums = string.split(params, ";")
	for i=1,#nums do nums[i] = tonumber(nums[i]) end

	local w, h = self.controller.getResolution()

	if action == "A" then
		local n = nums[1] or 1
		self.y = math.clamp(self.y - n, 1, h)
		return
	end
	if action == "B" then
		local n = nums[1] or 1
		self.y = math.clamp(self.y + n, 1, h)
		return
	end
	if action == "C" then
		local n = nums[1] or 1
		self.x = math.clamp(self.x + n, 1, w)
		return
	end
	if action == "D" then
		local n = nums[1] or 1
		self.x = math.clamp(self.x - n, 1, w)
		return
	end
	if action == "E" then
		local n = nums[1] or 1
		self.x = 1
		self.y = math.clamp(self.y + n, 1, h)
		return
	end
	if action == "F" then
		local n = nums[1] or 1
		self.x = 1
		self.y = math.clamp(self.y - n, 1, h)
		return
	end
	if action == "G" then
		local n = nums[1] or 1
		self.x = math.clamp(n, 1, w)
		return
	end
	if action == "H" then
		local n = nums[1] or 1
		local m = nums[2] or 1
		self.x = math.clamp(n, 1, w)
		self.y = math.clamp(m, 1, h)
		return
	end
	if action == "J" then
		local n = nums[1] or 0
		if n == 0 then
			self.controller.fill(self.x, self.y, w - self.x + 1, 1, " ")
			self.controller.fill(1, self.y + 1, 1, h - self.y, " ")
		elseif n == 1 then
			self.controller.fill(1, 1, 1, self.y-1, " ")
			self.controller.fill(1, self.y, self.x, 1, " ")
		elseif n == 2 then
			self.controller.fill(1, 1, w, h, " ")
		end
		return
	end
	if action == "K" then
		local n = nums[1] or 0
		if n == 0 then
			self.controller.fill(self.x, self.y, w - self.x + 1, 1, " ")
		elseif n == 1 then
			self.controller.fill(1, self.y, self.x, 1, " ")
		elseif n == 2 then
			self.controller.fill(1, self.y, w, 1, " ")
		end
		return
	end
	if action == "S" then
		self:scrollUp(nums[1])
		return
	end
	if action == "T" then
		self:scrollDown(nums[1])
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
				self.controller.setForeground(self.defaultFg)
				self.controller.setBackground(self.defaultBg)
			elseif op == 7 then
				self:swapColors()
			elseif op == 8 then
				-- TODO: conceal
			elseif op == 28 then
				-- TODO: un-conceal
			elseif op >= 30 and op <= 37 then
				self.controller.setForeground(self.stdColors[op])
			elseif op >= 90 and op <= 97 then
				self.controller.setForeground(self.stdColors[op])
			elseif op >= 40 and op <= 47 then
				self.controller.setBackground(self.stdColors[op-10])
			elseif op >= 100 and op <= 107 then
				self.controller.setBackground(self.stdColors[op-10])
			elseif op == 38 then
				local clr = self.defaultFg
				local n = pop()
				if n == 5 then
					clr = self.color256[pop()]
				elseif n == 2 then
					local r = pop()
					local g = pop()
					local b = pop()
					clr = vtty.color(r, g, b)
				end
				self.controller.setForeground(clr)
			elseif op == 48 then
				local clr = self.defaultBg
				local n = pop()
				if n == 5 then
					clr = self.color256[pop()]
				elseif n == 2 then
					local r = pop()
					local g = pop()
					local b = pop()
					clr = vtty.color(r, g, b)
				end
				self.controller.setBackground(clr)
			elseif op == 39 then
				self.controller.setForeground(self.defaultFg)
			elseif op == 49 then
				self.controller.setBackground(self.defaultBg)
			end
		end
	end

	if action == "n" then
		if params == "6" then
			self.keybuf = self.keybuf .. string.format("\x1b[%d;%dR", self.x, self.y)
			return
		end
		if params == "7" then
			self.keybuf = self.keybuf .. string.format("\x1b[%d;%dR", w, h)
			return
		end
		if params == "8" then
			local mw, mh = self.controller.maxResolution()
			self.keybuf = self.keybuf .. string.format("\x1b[%d;%dR", mw, mh)
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
			self:enableBlink()
			self:showCursor()
		end
		if params == "?1004" then
			-- TODO: enable focus reporting
			return
		end
		if params == "?2004" then
			-- bracketed paste mode is remapped to key up enabled
			self.keyUpEnabled = true
			return
		end
		return
	end
	if action == "l" then
		if params == "?25" then
			self:disableBlink()
			self:hideCursor()
		end
		if params == "?1004" then
			-- TODO: enable focus reporting
			return
		end
		if params == "?2004" then
			-- bracketed paste mode is remapped to key up enabled
			self.keyUpEnabled = true
			return
		end
		return
	end
	if action == "U" then
		-- from UlOS, with minor changes
		if nums[1] == 1 then
			self.controller.fill(nums[2] or 1, nums[3] or 1, nums[4] or w, nums[5] or h, unicode.char(nums[6] or 32))
			return
		end
		if nums[1] == 2 then
			self.controller.copy(nums[2] or 1, nums[3] or 1, nums[4] or w, nums[5] or h, nums[6] or 0, nums[7] or 0)
			return
		end
		if nums[1] == 3 then
			self.controller.setResolution(nums[2] or w, nums[3] or h)
			return
		end
		if nums[1] == 4 then
			local x = nums[2] or self.x
			local y = nums[3] or self.y
			local c, f, g = self.controller.get(x, y)
			-- TODO: decode out the UTF-8 instead of using string.char
			self.keybuf = self.keybuf .. string.format("\x1b[%d;%d;%dR", string.byte(c), f, g)
			return
		end
		return
	end
	if action == "v" then
		if nums[1] == 1 then
			local free = self.controller.freeMemory()
			local total = self.controller.totalMemory()
			self.keybuf = self.keybuf .. string.format("\x1b[%d;%dR", free, total)
			return
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
		if self.esc:sub(1,1) == "]" then
			-- CSIs!!
			self.esc = self.esc .. c
			local terms = {"\a", "\x1b\\"}
			for _, term in ipairs(terms) do
				if self.esc:sub(-#term) == term then
					self:doOSC(self.esc:sub(2, -#term - 1))
					self.esc = nil
					return
				end
			end
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
		self.x = math.align(self.x + 1, 8)
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
		self:scrollUp(1)
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
