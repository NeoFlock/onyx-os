-- Terminal escape reader
-- It is used to turn escapes into an event stream.

local keyboard = require("keyboard")

---@class terminal
---@field fd integer
---@field buf? string
---@field clipboardBuf? string
---@field clipboardSize integer
---@field events any[][]
local terminal = {}
terminal.__index = terminal

---@param fd integer
function terminal.wrap(fd)
	return setmetatable({fd=fd, events={}, clipboardSize = 0}, terminal)
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
		local parts = string.split(data, ";")
		self:push("term_response", tonumber(parts[1]), tonumber(parts[2]))
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
---@return string, ...
function terminal:pull()
	local t = table.remove(self.events, 1)
	if t then
		return table.unpack(t)
	end
end

return terminal
