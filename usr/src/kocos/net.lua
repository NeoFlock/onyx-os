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
---@return Kocos.Handle?, string?
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

Kocos.net = net
Kocos.printk(Kocos.L_DEBUG, "network subsystem loaded")
