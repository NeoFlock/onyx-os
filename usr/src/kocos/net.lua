-- Networking syscalls

---@class Kocos.addrinfo
---@field address? string
---@field port? integer
---@field opts? table

---@param domain string
---@param type "SOCK_DGRAM"|"SOCK_STREAM"|"SOCK_SEQPACKET"|"SOCK_RAW"|string
---@param protocol? string nil for default one
---@return integer?, string
function syscalls.socket(domain, type, protocol)
	---@type Kocos.descriptor?, string?, string?
	local socket, err, modname

	for name, mod in pairs(Kocos.mods) do
		socket, err = mod("NET-socket", domain, type, protocol)
		if err then return nil, err end
		if socket then
			modname = name
			break
		end
	end

	if not socket then return nil, Kocos.ENODRIVER end

	local proc = Kocos.currentProcess()
	local avail = Kocos.availableDescriptorFor(proc)
	proc.fds[avail] = socket
	return avail, tostring(modname)
end

---@param fd integer
---@param addrinfo Kocos.addrinfo
---@return boolean, string?
function syscalls.bind(fd, addrinfo)
	if type(addrinfo) ~= "table" then return false, Kocos.EINVAL end
	addrinfo = table.copy(addrinfo)

	local h = Kocos.currentProcess().fds[fd]
	if not h then return false, Kocos.EBADF end
	if h.type ~= "socket" then return false, Kocos.EBADF end
	local ok, err = Kocos.handleDescriptorRequest(h, "addrinfo_valid", addrinfo)
	if not ok then return false, err end
	h.addrinfo = addrinfo
	return true
end

---@param fd integer
---@return boolean, string?
function syscalls.connect(fd)
	local h = Kocos.currentProcess().fds[fd]
	if not h then return false, Kocos.EBADF end
	if h.type ~= "socket" then return false, Kocos.EBADF end
	return Kocos.handleDescriptorRequest(h, "connect")
end

---@param fd integer
---@param backlog? integer
---@return boolean, string?
function syscalls.listen(fd, backlog)
	backlog = backlog or 128
	if type(backlog) ~= "number" then return false, Kocos.EINVAL end
	backlog = math.floor(backlog)
	local h = Kocos.currentProcess().fds[fd]
	if not h then return false, Kocos.EBADF end
	if h.type ~= "socket" then return false, Kocos.EBADF end
	return Kocos.handleDescriptorRequest(h, "listen", backlog)
end

---@param fd integer
---@return integer?, string?
function syscalls.accept(fd)
	local h = Kocos.currentProcess().fds[fd]
	if not h then return nil, Kocos.EBADF end
	if h.type ~= "socket" then return nil, Kocos.EBADF end
	return Kocos.handleDescriptorRequest(h, "accept")
end

---@param fd integer
---@param data string
---@param id any
---@return boolean, string?
--- Attempts an async write.
--- If successful, it will eventually send a data_written event to the socket.
--- The event has 2 parameters, the id initially sent, and an error if it failed.
function syscalls.aio_write(fd, data, id)
	if type(fd) ~= "number" then return false, Kocos.EINVAL end
	if type(data) ~= "string" then return false, Kocos.EINVAL end

	local proc = Kocos.currentProcess()
	local f = proc.fds[fd]
	if not f then return false, Kocos.EBADF end
	return Kocos.handleDescriptorRequest(f, "aio_write", data, id)
end

---@param fd integer
---@param len integer
---@return boolean, string?
--- Requests an async read.
--- This would eventually send a data_recv signal when data is received.
--- The signal has 2 parameters, a length that can be passed to read() to
--- get the data, or nil, and an error if applicable.
--- Sockets will send the signal regardless, and thus for sockets,
--- this is completely useless.
function syscalls.aio_read(fd, len)
	if type(fd) ~= "number" then return false, Kocos.EINVAL end
	if type(len) ~= "number" then return false, Kocos.EINVAL end
	local proc = Kocos.currentProcess()
	local f = proc.fds[fd]
	if not f then return false, Kocos.EBADF end
	return Kocos.handleDescriptorRequest(f, "aio_read", len)
end
