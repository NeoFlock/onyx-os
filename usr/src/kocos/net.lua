-- Networking layer
local net = {}
local errno = Kocos.errno

---@alias Kocos.net.socketstate "init"|"connecting"|"connected"|"listening"|"closed"

net.O_NONBLOCK = Kocos.fs.O_NONBLOCK

-- Events similar to FS

net.EV_CLOSED = Kocos.fs.EV_CLOSED
net.EV_DATAREADY = Kocos.fs.EV_DATAREADY
net.EV_WRITEDONE = Kocos.fs.EV_WRITEDONE
--- on success, it should contain 2 nilable strings: the connection ID and the error. If error is nil, the operation succeeded. The connection ID is meant to be returned by connect() and be *unique*
net.EV_CONNECTDONE = "connect-done"

---@class Kocos.net.addrinfo: table
--- An address of some kind depending on networking technology
---@field address any
---@field port integer

---@class Kocos.net.socket
---@field state Kocos.net.socketstate
---@field write? fun(self, data: string): boolean, string?
---@field read? fun(self, len: integer): string?, string?
---@field ioctl? fun(self, action: string, ...): ...
---@field close? fun(self)
---@field accept? fun(self): Kocos.net.socket?, string?
---@field listen? fun(self, addrinfo: Kocos.net.addrinfo): boolean, string?
---@field connect? fun(self, addrinfo: Kocos.net.addrinfo): string?, string?
---@field flags integer
---@field listener? function

---@param domain string
---@param protocol string
---@param host string
--- Either a name of an application-layer protocol or the port number
---@param service? string|integer
---@return Kocos.net.addrinfo?, string?
function net.getaddrinfo(domain, protocol, host, service)
	for _, driver in ipairs(Kocos.drivers) do
		local s, err = driver("NET-addrinfo", domain, protocol, host, service)
		if err then
			return nil, err
		end
		if s then
			return s
		end
	end
	return nil, errno.ENODRIVER
end

---@param domain string
---@param socktype string
---@param protocol? string
---@return Kocos.net.socket?, string?
function net.socket(domain, socktype, protocol)
	for _, driver in ipairs(Kocos.drivers) do
		local s, err = driver("NET-socket", domain, socktype, protocol)
		if err then
			return nil, err
		end
		if s then
			return s
		end
	end
	return nil, errno.ENODRIVER
end

---@param socket Kocos.net.socket
---@param data string
---@return boolean, string?
function net.write(socket, data)
	if socket.state ~= "connected" then
		return false, errno.EAGAIN
	end
	if socket.write then
		return socket:write(data)
	end
	return false, errno.EBADF
end

---@param socket Kocos.net.socket
---@param len integer
---@return string?, string?
function net.read(socket, len)
	if socket.state ~= "connected" then
		return nil, errno.EAGAIN
	end
	if socket.read then
		return socket:read(len)
	end
	return nil, errno.EBADF
end

---@param socket Kocos.net.socket
---@param ev string
function net.notify(socket, ev, ...)
	if socket.listener then
		socket:listener(ev, ...)
	end
end

---@param socket Kocos.net.socket
---@return string?, string?
function net.close(socket)
	net.notify(socket, net.EV_CLOSED)
	socket.state = "closed"
	if socket.close then
		return socket:close()
	end
end

---@param socket Kocos.net.socket
---@param action string
function net.ioctl(socket, action, ...)
	if socket.ioctl then
		return socket:ioctl(action, ...)
	end
	return nil, errno.EBADF
end

---@param socket Kocos.net.socket
---@return Kocos.net.socket?, string?
function net.accept(socket)
	if socket.state ~= "listening" then
		return nil, errno.EBADF
	end
	if socket.accept then
		return socket:accept()
	end
	return nil, errno.EBADF
end

---@param socket Kocos.net.socket
---@param addrinfo Kocos.net.addrinfo
---@return string?, string?
function net.connect(socket, addrinfo)
	if socket.state ~= "init" then
		return nil, errno.EISCONN
	end
	if socket.connect then
		return socket:connect(addrinfo)
	end
	return nil, errno.EBADF
end

---@param socket Kocos.net.socket
---@param addrinfo Kocos.net.addrinfo
---@return boolean, string?
function net.listen(socket, addrinfo)
	if socket.state == "init" then
		return false, errno.EISCONN
	end
	if socket.listen then
		return socket:listen(addrinfo)
	end
	return false, errno.EBADF
end

Kocos.net = net
Kocos.printk(Kocos.L_DEBUG, "network subsystem loaded")
