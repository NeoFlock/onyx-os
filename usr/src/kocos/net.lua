-- Networking syscalls

---@class Kocos.addrinfo
---@field address? string
---@field port? integer
---@field opts? table

---@param domain string
---@param type string
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

	if not socket then return nil, Kocos.ENOTBOUND end

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
---@param data string
---@return integer?, string?
--- Returns the current write offset that will be passed
--- to the data_written signal once completed.
--- Intended mostly for sockets but files can also use it.
function syscalls.aio_write(fd, data)
	if type(fd) ~= "number" then return nil, Kocos.EINVAL end
	if type(data) ~= "string" then return nil, Kocos.EINVAL end

	local proc = Kocos.currentProcess()
	local f = proc.fds[fd]
	if not f then return nil, Kocos.EBADF end
	return Kocos.handleDescriptorRequest(f, "aio_write", data)
end

---@param fd integer
---@param len integer
---@return integer?, string?
--- Returns the current read offset that will be passed
--- to the data_recv signal once completed.
--- Intended mostly for sockets but files can also use it.
--- Sockets will typically queue the signal regardless of aio_read.
--- This function is mostly just for files, but not all filesystems support it.
function syscalls.aio_read(fd, len)
	if type(fd) ~= "number" then return nil, Kocos.EINVAL end
	if type(len) ~= "number" then return nil, Kocos.EINVAL end
	local proc = Kocos.currentProcess()
	local f = proc.fds[fd]
	if not f then return nil, Kocos.EBADF end
	return Kocos.handleDescriptorRequest(f, "aio_read", len)
end
