-- Terminal escape reader
-- It is used to turn escapes into an event stream.

local keyboard = require("keyboard")

---@class terminal
---@field fd integer
---@field ofd integer
---@field buf? string
---@field clipboardBuf? string
---@field clipboardSize integer
---@field events any[][]
local terminal = {}
terminal.__index = terminal

terminal.STDIN = 0
terminal.STDOUT = 1
terminal.STDERR = 2
terminal.STDTERM = 3

function terminal.stdio()
	return terminal.wrap(terminal.STDIN, terminal.STDOUT)
end

function terminal.stdterm()
	return terminal.wrap(terminal.STDTERM)
end

---@param fd integer
---@param ofd? integer
function terminal.wrap(fd, ofd)
	return setmetatable({fd=fd, ofd=ofd or fd, events={}, clipboardSize = 0}, terminal)
end

--- Internal function. Push an event
---@param event string
function terminal:push(event, ...)
	table.insert(self.events, {event, ...})
end

local _term, _user = ":terminal:", ":user:"

--- Internal function. Process a terminal CSI escape
---@param data string
---@param action string
function terminal:runCSI(data, action)
	if action == "~" then
		-- key_down
		local parts = string.split(data, ";")
		self:push("key_down", _term, tonumber(parts[1]), tonumber(parts[2]), tonumber(parts[3]) or 0)
		return
	end
	if action == "^" then
		-- key_up
		local parts = string.split(data, ";")
		self:push("key_up", _term, tonumber(parts[1]), tonumber(parts[2]), tonumber(parts[3]) or 0)
		return
	end
	if action == "|" then
		-- clipboard, very tricky here...
		self.clipboardSize = tonumber(data) or 0
		if self.clipboardSize == 0 then
			self:push("clipboard", _term, "", _user)
			return
		end
		self.clipboardBuf = ""
		return
	end
	if action == "R" then
		self:push("term_response", data)
		return
	end
	if action == "M" then
		-- stinky screen events...
		return
	end
end

--- Internal function. Process a single char from the terminal.
---@param c string
function terminal:processC(c)
	if self.clipboardBuf then
		self.clipboardBuf = self.clipboardBuf .. c
		if #self.clipboardBuf >= self.clipboardSize then
			self:push("clipboard", _term, self.clipboardBuf, 0)
			self.clipboardBuf = nil
			return
		end
	end
	if self.buf then
		if #self.buf == 0 and c == '\x1b' then
			self:push("key_down", _term, 0x1B, keyboard.keys.escape, 0)
			return
		end
		if #self.buf == 0 and c == '[' then
			-- CSI
			self.buf = '['
			return
		end
		if self.buf:sub(1, 1) == '[' then
			-- end of CSI
			if c:byte() >= 0x40 and c:byte() <= 0x7E then
				self:runCSI(self.buf:sub(2), c)
				self.buf = nil
				return
			end
			self.buf = self.buf .. c
			return
		end
		-- unrecognized escape
		self.buf = nil
		return
	end
	if c == '\x1b' then
		self.buf = ""
		return
	elseif c == "\x03" then
		self:push("interrupted")
		return
	else
		self:push("key_down", _term, c:byte(), keyboard.charToCode(c:byte()), 0)
		return
	end
end

---@param len? integer
---@return boolean, string?
function terminal:process(len)
	len = len or math.huge
	local buf, err = k.read(self.fd, len)
	if err then return false, err end
	if not buf then buf = "\x04" end -- EoF
	for i=1,#buf do
		self:processC(buf:sub(i, i))
	end
	return true
end

--- Get an event.
--- The screen and keyboard events have almost identical mappings, with the
--- addresses being set to :terminal:, and player name to :user: for screen events, and the modifier integer for keyboard events,
--- Responses raise a term_response event instead.
---@return string?, ...
function terminal:pull()
	local t = table.remove(self.events, 1)
	if t then
		return table.unpack(t)
	end
end

function terminal:write(...)
	local s = table.concat({...}, "")
	assert(k.write(self.ofd, s))
end

terminal.ESC = "\x1b"
terminal.CSI = "\x1b["
terminal.OSC = "\x1b]"
terminal.ST = "\x1b\\"
terminal.BELL = "\a"

function terminal:writeCSI(action, ...)
	self:write(terminal.CSI, table.concat({...}, ";"), action)
end

function terminal:writeOSC(cmd)
	self:write(terminal.OSC, cmd, terminal.BELL)
end

---@param passInterrupt? boolean
---@return string?, ...
function terminal:pullUntilEvent(passInterrupt)
	while true do
		local t = {self:pull()}
		if t[1] then
			if t[1] == "interrupted" and not passInterrupt then
				error("interrupted", 2)
			end
			return table.unpack(t)
		else
			coroutine.yield()
			self:process()
		end
	end
end

function terminal:dropEvents()
	self.events = {}
end

function terminal:showCursor()
	self:write(terminal.CSI, "?25h")
end

function terminal:hideCursor()
	self:write(terminal.CSI, "?25l")
end

---@return string
function terminal:blockUntilResponse()
	while true do
		local ev, resp = self:pullUntilEvent()
		if ev == "term_response" then
			return resp
		end
	end
end

---@return integer, integer
function terminal:blockUntilDSR()
	local resp = self:blockUntilResponse()
	local nums = string.split(resp, ";")
	return tonumber(nums[1]) or 0, tonumber(nums[2]) or 0
end

function terminal:getCursor()
	self:write(terminal.CSI, "6n")
	return self:blockUntilDSR()
end

---@param x integer
---@param y integer
function terminal:setCursor(x, y)
	self:write(terminal.CSI, x, ";", y, "H")
end

function terminal:clearScreenAfterCursor()
	self:write(terminal.CSI, "0J")
end

function terminal:clearScreenBeforeCursor()
	self:write(terminal.CSI, "1J")
end

function terminal:clearScreen()
	self:write(terminal.CSI, "2J")
end

function terminal:clearLineAfterCursor()
	self:write(terminal.CSI, "0K")
end

function terminal:clearLineBeforeCursor()
	self:write(terminal.CSI, "1K")
end

function terminal:clearLine()
	self:write(terminal.CSI, "2K")
end

function terminal:clearAndReset()
	self:clearScreen()
	self:setCursor(1, 1)
	self:disableFocusReporting()
	self:disableKeyUp()
	self:disableAuxPort()
	self:write(terminal.CSI, "0m")
end

function terminal:enableFocusReporting()
	self:write(terminal.CSI, "?1004h")
end

function terminal:disableFocusReporting()
	self:write(terminal.CSI, "?1004l")
end

function terminal:enableKeyUp()
	self:write(terminal.CSI, "?2004h")
end

function terminal:disableKeyUp()
	self:write(terminal.CSI, "?2004l")
end

function terminal:enableAuxPort()
	self:write(terminal.CSI, "5i")
end

function terminal:disableAuxPort()
	self:write(terminal.CSI, "4i")
end

---@param amountUp integer
function terminal:scroll(amountUp)
	if amountUp == 0 then return end
	self:write(terminal.CSI, math.abs(amountUp), amountUp > 0 and "S" or "T")
end

function terminal:getResolution()
	self:write(terminal.CSI, "7n")
	return self:blockUntilDSR()
end

function terminal:maxResolution()
	self:write(terminal.CSI, "8n")
	return self:blockUntilDSR()
end

---@param w integer
---@param h integer
function terminal:setResolution(w, h)
	self:write(terminal.CSI, "3;", w, ";", h, "U")
end

function terminal:beep()
	self:write(terminal.BELL)
end

---@return integer, integer
function terminal:requestVRAM()
	self:write(terminal.CSI, "1v")
	return self:blockUntilDSR()
end

function terminal:freeMemory()
	local free = self:requestVRAM()
	return free
end

function terminal:totalMemory()
	local _, total = self:requestVRAM()
	return total
end

function terminal:hasVRAM()
	return self:totalMemory() > 0
end

function terminal:saveCursor()
	self:write(terminal.ESC, "7")
end

function terminal:restoreCursor()
	self:write(terminal.ESC, "8")
end

return terminal
