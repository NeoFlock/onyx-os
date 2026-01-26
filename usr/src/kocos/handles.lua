---@alias Kocos.HandleAction "close"|"write"|"read"|"seek"|"ioctl"|"connect"|"listen"|"accept"

local errno = Kocos.errno

---@class Kocos.Handle
---@field type "file"|"socket"|"device"|"lock"
---@field state string
---@field rc number
---@field handle fun(req: Kocos.HandleAction, ...): ...
---@field flags integer
---@field listener? function

local handles = {}

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
	if h.listener then h.listener(ev, ...) end
end

---@param h Kocos.Handle
function handles.close(h)
	h.rc = h.rc - 1
	if h.rc <= 0 then
		h.state = "closed"
		h.handle("close")
	end
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

Kocos.handles = handles
Kocos.printk(Kocos.L_DEBUG, "handle subsystem loaded")
