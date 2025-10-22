--!lua

--- Internet socket layer

---@class sockinternetd.tcp: Kocos.net.socket
---@field sock userdata
---@field dataReady boolean

---@type table<string, socktunneld.socket>
local tcp = {}

assert(k.mklistener(function(ev, id)
	if ev ~= "internet_ready" then return end
	if tcp[id] then
		tcp[id].dataReady = true
	end
end))

local errnos = k.errnos()

assert(k.mkdriver(function(ev, ...)
	if ev == "NET-socket" then
		---@type string, string, string?
		local domain, socktype, protocol = ...
		if domain ~= "AF_INET" then return end
		local inet = k.cprimary("internet")
		if not inet then return nil, errnos.ENETDOWN end
		protocol = protocol or "http"
		if protocol == "http" then
			---@type Kocos.net.socket
			return {
				state = "init",
				flags = 1,
				connect = function(s, addrinfo)
					local sock, err = inet.request(addrinfo.address, addrinfo.postData, addrinfo.headers)
					if not sock then return nil, err end
					s.sock = sock
					s.state = "connected"
					-- TODO: async stuff
					return addrinfo.address
				end,
				read = function(s, len)
					if s.flags & 1 == 0 then
						local ok, err = s.sock.finishConnect()
						if not ok then return nil, err end
					end
					return s.sock.read(len)
				end,
				close = function(s)
					if s.sock then s.sock.close() end
				end,
				ioctl = function(s, action)
					if not s.sock then return nil, errnos.EBADF end
					if action == "response" then
						return s.sock.response()
					end
				end,
			}
		elseif protocol == "tcp" then
		end
		return nil, errnos.EPROTONOSUPPORT
	end
end))

k.invokeDaemon("initd", "markComplete")

k.kill(k.getpid(), "SIGSTOP")
coroutine.yield()
