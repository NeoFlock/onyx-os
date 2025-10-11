--!lua

--- Tunnel socket layer

---@class socktunneld.socket: Kocos.net.socket
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
			state = "init",
			id = string.randomGUID(),
			buffer = {},
			device = "",
			flags = 0,
			connect = function(_, addrinfo)
				if k.ctype(addrinfo.address) ~= "tunnel" then return nil, "host is unreachable" end
				s.device = addrinfo.address
				-- TODO: inform in non-blocking case once timers exist
				s.state = "connected"
				return s.id
			end,
			read = function(_, len)
				while #s.buffer == 0 do
					if s.flags & 1 then return "" end
					coroutine.yield()
				end
				if len >= #s.buffer[1] then
					return table.remove(s.buffer, 1)
				else
					local c = s.buffer[1]:sub(1, len)
					s.buffer[1] = s.buffer[1]:sub(len+1)
					return c
				end
			end,
			write = function(_, data)
				return k.cinvoke(s.device, "send", data)
			end,
			close = function()
				sockets[s.id] = nil
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
