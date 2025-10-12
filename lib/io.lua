---@diagnostic disable: duplicate-set-field

local buffer = require("buffer")

io={}

io.ALL_PERMS = 511

---@param filename string
---@param mode? "r"|"w"|"a"|"rb"|"wb"|"ab"
---@return buffer?, string?
function io.open(filename, mode)
	mode = mode or "rb"
	local textmode = #mode == 1
	mode = mode:sub(1, 1)
	if mode ~= "r" and not k.exists(filename) then
		local ok, err = k.touch(filename, io.ALL_PERMS)
		if not ok then return nil, err end
	end
	local fd, err = k.open(filename, mode)
	if not fd then return nil, err end

	return buffer.create({
		fd = fd,
		write = function(_, data)
			local ok, werr = k.write(fd, data)
			return ok or false, werr
		end,
		read = function(_, len)
			return k.read(fd, len)
		end,
		seek = function(_, whence, off)
			return k.seek(fd, whence, off)
		end,
		close = function()
			return k.close(fd)
		end,
	}, mode == "r", textmode), nil
end

---@param fd integer
---@param readonly boolean
---@param textmode boolean
---@return buffer
function io.wrap(fd, readonly, textmode)
	return buffer.create({
		fd = fd,
		write = function(_, data)
			local ok, werr = k.write(fd, data)
			return ok or false, werr
		end,
		read = function(_, len)
			return k.read(fd, len)
		end,
		seek = function(_, whence, off)
			return k.seek(fd, whence, off)
		end,
		close = function()
			return k.close(fd)
		end,
	}, readonly, textmode)
end

---@param file? buffer
---@return buffer
function io.output(file)
	local ploc = k.proclocal()
	if not file then
		ploc._IO_OUT = ploc._IO_OUT or io.wrap(1, false, true)
		return ploc._IO_OUT
	end
	ploc._IO_OUT = file
	return file
end

---@param file? buffer
---@return buffer
function io.input(file)
	local ploc = k.proclocal()
	if not file then
		ploc._IO_IN = ploc._IO_IN or io.wrap(1, false, true)
		return ploc._IO_IN
	end
	ploc._IO_IN = file
	return file
end

---@param file? buffer
---@return buffer
function io.input(file)
	local ploc = k.proclocal()
	if not file then
		ploc._IO_IN = ploc._IO_IN or io.wrap(1, false, true)
		return ploc._IO_IN
	end
	ploc._IO_IN = file
	return file
end

---@param file? buffer
---@return buffer
function io.error(file)
	local ploc = k.proclocal()
	if not file then
		ploc._IO_ERR = ploc._IO_ERR or io.wrap(2, false, true)
		return ploc._IO_ERR
	end
	ploc._IO_ERR = file
	return file
end

---@type buffer
io.stdin = nil

---@type buffer
io.stdout = nil

---@type buffer
io.stderr = nil

setmetatable(io, {
	__index = function(t, key)
		if key == "stdin" then
			return io.input()
		end
		if key == "stdout" then
			return io.output()
		end
		if key == "stderr" then
			return io.error()
		end
	end,
	__newindex = function(t, key, val)
		if key == "stdin" then
			io.input(val)
			return
		end
		if key == "stdout" then
			io.output(val)
			return
		end
		if key == "stderr" then
			io.error(val)
			return
		end
		rawset(t, key, val)
	end,
})

function io.write(...)
	return io.stdout:write(...)
end

function io.ewrite(...)
	return io.stderr:write(...)
end

function io.flush()
	io.stdout:flush()
	io.stderr:flush()
end

function io.read(...)
	io.flush()
	return io.stdin:read(...)
end

---@param file buffer
function io.close(file)
	return file:close()
end

io.ftype = k.ftype
io.list = k.list

return io
