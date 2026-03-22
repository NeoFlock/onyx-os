-- Internet networking

---@class Kocos.internetsock: Kocos.descriptor
---@field _netTy "tcp"|"http"
---@field _netSock any

---@type table<string, Kocos.internetsock>
local socks = {}

---@type Kocos.descriptorHandler
local function internetHandler(handle, act, ...)
	---@cast handle Kocos.internetsock
	if act == "read" then
		if not handle._netSock then return nil, Kocos.EBADF end
		return handle._netSock.read(...)
	end
	if act == "aio_read" then
		return true
	end
	if act == "write" or act == "aio_write" then
		if not handle._netSock then return nil, Kocos.EBADF end
		if handle._netTy == "http" then return nil, Kocos.EBADF end
		local data, id = ...
		local ok, err = handle._netSock.write(data)
		if act == "aio_write" then
			Kocos.notifyDescriptor(handle, "data_written", id, err)
		end
		return ok, err
	end
	if act == "close" then
		if handle._netSock then handle._netSock.close() end
		return true
	end
	if act == "addrinfo_valid" then
		---@type Kocos.addrinfo
		local info = ...
		return type(info.address) == "string"
	end
	if act == "connect" then
		if not handle.addrinfo then return false, Kocos.EBADF end
		if not component.internet then return false, Kocos.ENETDOWN end
		local err
		if handle._netTy == "tcp" then
			handle._netSock, err = component.internet.connect(handle.addrinfo.address, handle.addrinfo.port)
		else
			local opts = handle.addrinfo.opts or {}
			handle._netSock, err = component.internet.request(handle.addrinfo.address, opts.postData, opts.headers)
		end
		return handle._netSock ~= nil, err
	end
	return nil, Kocos.EBADF
end

return function(req, ...)
	if req == "NET-socket" then
		local domain, type, proto = ...
		if domain ~= "AF_INET" then return end
		if type ~= "SOCK_STREAM" then return end
		proto = proto or "http"
		if proto ~= "http" and proto ~= "tcp" then return end
		if not component.internet then return nil, Kocos.ENETDOWN end
		if proto == "http" and not component.internet.isHttpEnabled() then
			return nil, Kocos.EPERM
		end
		if proto == "tcp" and not component.internet.isTcpEnabled() then
			return nil, Kocos.EPERM
		end
		---@type Kocos.internetsock
		return {
			type = "socket",
			state = "init",
			pid = 0,
			handler = internetHandler,
			flags = 0,
			rc = 1,
			_netTy = proto,
			device = component.internet.address,
		}
	end
	if req == "EVENT" then
		local ty, id = ...
		if ty ~= "internet_ready" then return end
		local s = socks[id]
		if not s then return end
		Kocos.notifyDescriptor(s, "data_recv", math.huge)
		return
	end
end
