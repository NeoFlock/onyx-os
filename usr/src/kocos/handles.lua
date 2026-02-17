---@alias Kocos.HandleAction "close"|"write"|"read"|"seek"|"ioctl"|"connect"|"listen"|"accept"

local errno = Kocos.errno

---@class Kocos.Handle
---@field type "file"|"socket"|"device"|"lock"|"pipe"|"timer"
---@field state string
---@field rc number
---@field handle fun(req: Kocos.HandleAction, ...): ...
---@field flags integer
---@field listener? function
---@field evbuf? table[]

local handles = {}

handles.MAX_EVBUF = 8

---@param h Kocos.Handle
---@param data string
---@return boolean, string?
function handles.write(h, data)
	if h.type == "socket" and h.state ~= "connected" then
		return false, errno.EAGAIN
	end
	return h.handle("write", data)
end

---@param h Kocos.Handle
---@param len? integer
---@return string?, string?
function handles.read(h, len)
	if h.type == "socket" and h.state ~= "connected" then
		return nil, errno.EAGAIN
	end
	return h.handle("read", len or math.huge)
end

---@param h Kocos.Handle
---@param whence? "set"|"cur"|"end"
---@param off? integer
---@return integer?, string?
function handles.seek(h, whence, off)
	return h.handle("seek", whence or "cur", off or 0)
end

---@param h Kocos.Handle
---@param action string
---@return ...
function handles.ioctl(h, action, ...)
	return h.handle("ioctl", action, ...)
end

---@param h Kocos.Handle
---@param ev string
function handles.notify(h, ev, ...)
	if h.listener then
		h.listener(ev, ...)
	else
		h.evbuf = h.evbuf or {}
		table.insert(h.evbuf, {...})
		while #h.evbuf > handles.MAX_EVBUF do
			table.remove(h.evbuf, 1)
		end
	end
end

---@parma h Kocos.Handle
---@param f function?
function handles.setlistener(h, f)
	if h.evbuf and f then
		for _, ev in ipairs(h.evbuf) do
			f(table.unpack(ev))
		end
		-- save the memory!!
		h.evbuf = nil
	end
	h.listener = f
end

---@param h Kocos.Handle
function handles.close(h)
	h.rc = h.rc - 1
	if h.rc <= 0 then
		h.state = "closed"
		h.handle("close")
	end
end

function handles.unusable(...)
	return nil, errno.EBADF
end

---@param h Kocos.Handle
---@param addrinfo Kocos.net.addrinfo
---@return string?, string?
function handles.connect(h, addrinfo)
	if h.state ~= "init" then
		return nil, errno.EISCONN
	end
	return h.handle("connect", addrinfo)
end

---@param h Kocos.Handle
---@param addrinfo Kocos.net.addrinfo
---@return boolean, string?
function handles.listen(h, addrinfo)
	if h.state ~= "init" then
		return false, errno.EISCONN
	end
	return h.handle("listen", addrinfo)
end

---@param h Kocos.Handle
---@return Kocos.Handle?, string?
function handles.accept(h)
	if h.state ~= "listening" then
		return nil, errno.EBADF
	end
	return h.handle("accept")
end

---@return Kocos.Handle reader, Kocos.Handle writer
function handles.mkpipe()
	---@type string?
	local sharedBuf = ""

	---@type Kocos.Handle, Kocos.Handle
	local r, w
	r = {
		type = "pipe",
		state = "reader",
		rc = 1,
		flags = 0,
		handle = function(act, len)
			if act == "read" then
				if not sharedBuf then
					return nil, errno.EPIPE
				end
				if len > #sharedBuf then len = #sharedBuf end
				len = math.floor(len)
				local chunk = sharedBuf:sub(1, len)
				sharedBuf = sharedBuf:sub(len+1)
				return chunk
			end
			if act == "close" then
				sharedBuf = nil
				return true
			end
			return nil, errno.EBADF
		end,
	}
	w = {
		type = "pipe",
		state = "writer",
		rc = 1,
		flags = 0,
		handle = function(act, data)
			if act == "write" then
				if not sharedBuf then
					return nil, errno.EPIPE
				end
				sharedBuf = sharedBuf .. data
				-- for async I/O
				handles.notify(w, Kocos.fs.EV_DATAREADY, #data)
				return true
			end
			if act == "close" then
				sharedBuf = nil
				return true
			end
			return nil, errno.EBADF
		end,
	}
	return r, w
end

---@param interval number
---@param func function
---@param times? integer
---@return Kocos.Handle
function handles.mktimer(interval, func, times)
	local t = Kocos.event.timer(interval, func, times)

	---@type Kocos.Handle
	return {
		type = "timer",
		handle = function(a)
			if a == "close" then
				Kocos.event.cancel(t)
			end
			return nil, errno.EBADF
		end,
		rc = 1,
		state = "",
		flags = 0,
	}
end

Kocos.handles = handles
Kocos.printk(Kocos.L_DEBUG, "handle subsystem loaded")
