--!lua

local errnos = require("errnos")

--- Tunnel socket layer

---@class socktunneld.socket: Kocos.Handle
---@field id string
---@field device string
---@field buffer string[]

---@type table<string, socktunneld.socket>
local sockets = {}

assert(k.mklistener(function(ev, receiver, sender, port, distance, msg)
	if ev ~= "modem_message" then return end
	if k.ctype(receiver) ~= "tunnel" then return end
	if type(msg) ~= "string" then return end

	for _, s in pairs(sockets) do
		if s.device == receiver then
			table.insert(s.buffer, msg)
			if s.listener then
				s.listener("data-ready", #msg)
			end
		end
	end
end))

assert(k.mkdriver(function(ev, ...)
	if ev == "NET-socket" then
		---@type string, string, string?
		local domain, socktype, protocol = ...
		if domain ~= "AF_TUNNEL" then return end
		---@type socktunneld.socket
		local s
		s = {
			type = "socket",
			state = "init",
			id = string.randomGUID(),
			buffer = {},
			device = "",
			flags = 0,
			rc = 1,
			handle = function(act, v)
				if act == "connect" then
					---@type Kocos.net.addrinfo
					local addrinfo = v
					if k.ctype(addrinfo.address) ~= "tunnel" then return nil, "host is unreachable" end
					s.device = addrinfo.address
					-- TODO: inform in non-blocking case once timers exist
					s.state = "connected"
					return s.id
				end
				if act == "read" then
					---@type integer
					local len = v
					while #s.buffer == 0 do
						if s.flags & 1 then return "" end
						coroutine.yield()
					end
					if len >= #s.buffer[1] then
						return table.remove(s.buffer, 1)
					end
					local c = s.buffer[1]:sub(1, len)
					s.buffer[1] = s.buffer[1]:sub(len+1)
					return c
				end
				if act == "write" then
					if #data == 0 then return true end -- trust me, this is a good thing
					return k.cinvoke(s.device, "send", data)
				end
				if act == "close" then
					sockets[s.id] = nil
					return
				end
				return nil, errnos.EBADF
			end,
		}
		sockets[s.id] = s
		return s
	end
end))

k.invokeDaemon("initd", "markComplete")

-- beautiful hack
k.kill(k.getpid(), "SIGSTOP")
coroutine.yield()
