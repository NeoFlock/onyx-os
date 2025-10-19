---@class buffer.stream
---@field write fun(self, data: string): boolean, string?
---@field read fun(self, len: integer): string?, string?
---@field seek fun(self, whence: seekwhence, off: integer): integer?, string?
---@field close fun(self)

---@alias buffer.mode "line"|"full"|"no"
---@alias buffer.readoption integer|"a"|"l"|"L"

---@class buffer
---@field stream buffer.stream
---@field readonly boolean
---@field textmode boolean
---@field closed boolean
---@field bufmode buffer.mode
---@field bufsize integer
---@field buffer? string
local buffer = {}
buffer.__index = buffer
buffer.defaultBufferSize = 2*1024
---@type buffer.mode
buffer.defaultBufferMode = "line"

---@param stream buffer.stream
---@param readonly boolean
---@param textmode boolean
---@param bufmode? buffer.mode
---@param bufsize? integer
function buffer.create(stream, readonly, textmode, bufmode, bufsize)
	return setmetatable({
		stream = stream,
		readonly = readonly,
		textmode = textmode,
		bufmode = bufmode or buffer.defaultBufferMode,
		bufsize = bufsize or buffer.defaultBufferSize,
		buffer = "",
		closed = false,
	}, buffer)
end

---@return string?, string?
function buffer:getBuffer()
	if self.buffer and #self.buffer > 0 then
		local buf = self.buffer
		self.buffer = nil
		if buf and self.textmode then
			local eof = string.find(buf, "\4") or (#buf+1)
			if eof then
				buf = buf:sub(1, eof-1)
				self.closed = true
			end
		end
		return buf
	end
	if self.closed then return end
	return self.stream:read(self.bufsize)
end

---@return boolean, string?
function buffer:flush()
	-- flushing does nothing
	if self.readonly then return false, "read-only buffer" end
	if not self.buffer then return true end
	if #self.buffer == 0 then return true end
	local ok, err = self.stream:write(self.buffer)
	if ok then self.buffer = "" end
	return ok, err
end

---@return boolean, string?
function buffer:write(...)
	local data = table.concat({...})
	if self.readonly then return false, "read-only buffer" end
	if self.bufmode == "no" then
		return self.stream:write(data)
	end
	self.buffer = self.buffer .. data
	if self.bufmode == "full" and #self.buffer >= self.bufsize then
		return self:flush()
	end
	if self.bufmode == "line" and (#self.buffer >= self.bufsize or string.find(self.buffer, "\n")) then
		return self:flush()
	end
	return true
end

---@param bufmode buffer.mode
---@param bufsize? integer
function buffer:setvbuf(bufmode, bufsize)
	if self.readonly then return end
	self:flush()
	self.bufmode = bufmode
	self.bufsize = bufsize or self.bufsize
	return true
end

---@param option buffer.readoption
---@return integer|string|nil
function buffer:readSingle(option)
	if not self.readonly then return end
	if type(option) == "number" then
		---@type string?
		local buf
		while true do
			if buf and #buf >= option then break end
			local chunk = self:getBuffer()
			if not chunk then break end
			buf = (buf or "") .. chunk
		end
		if not buf then return end
		local requested = buf:sub(1, option)
		self.buffer = buf:sub(option+1)
		if #self.buffer == 0 then self.buffer = nil end
		return requested
	end
	if option:sub(1, 1) == "*" then option = option:sub(2) end
	local c = option:sub(1,1)
	if c == "a" then
		---@type string?
		local buf
		while true do
			local chunk = self:getBuffer()
			if not chunk then break end
			buf = (buf or "") .. chunk
		end
		return buf
	end
	if c == "L" then
		---@type string?
		local buf
		local l
		repeat
			local chunk = self:getBuffer()
			if not chunk then break end
			buf = (buf or "") .. chunk
			l = string.find(buf, "\n")
		until l
		if not buf then return end
		l = l or (#buf+1)
		local line = buf:sub(1, l)
		self.buffer = buf:sub(l+1)
		return line
	end
	if c == "l" then
		-- this looks familiar...
		---@type string?
		local buf
		local l = nil
		repeat
			local chunk = self:getBuffer()
			if not chunk then break end
			buf = (buf or "") .. chunk
			l = string.find(buf, "\n")
		until l
		if not buf then return end
		l = l or (#buf+1)
		local line = buf:sub(1, l-1)
		self.buffer = buf:sub(l+1)
		return line
	end
end

---@vararg buffer.readoption
function buffer:read(...)
	if not self.readonly then return end
	local t = {}
	local n = select("#", ...)
	for i=1,n do
		local v = select(i, ...)
		t[i] = self:readSingle(v)
	end
	return table.unpack(t, 1, n)
end

---@param whence? seekwhence
---@param off? integer
---@return integer?, string?
function buffer:seek(whence, off)
	whence = whence or "cur"
	off = off or 0
	self:flush()
	if self.readonly then self.buffer = nil end
	return self.stream:seek(whence, off)
end

---@param str string
---@param bufsize? integer
function buffer.createString(str, bufsize)
	return buffer.create({
		write = function() return false, "read-only buffer" end,
		read = function(_, len)
			len = math.min(len, #str)
			local c = str:sub(1, len)
			str = str:sub(len+1)
			if c == "" then return end
			return c
		end,
		seek = function()
			return nil, "read-only string"
		end,
		close = function() end,
	}, true, false, nil, bufsize)
end

---@vararg buffer.readoption
---@return fun(): string?
function buffer:lines(...)
	local t = {...}
	if #t == 0 then t={"l"} end
	return function()
		return self:read(table.unpack(t))
	end
end

function buffer:close()
	self:flush()
	self.buffer=nil
	self.stream:close()
end

return buffer
