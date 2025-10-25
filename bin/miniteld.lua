--!lua

-- Incomplete Minitel driver

local errnos = require("errnos")

local minitelport = 4096

local PACK_UNRELIABLE = 0
local PACK_RELIABLE = 1
local PACK_ACK = 2

local m = k.cprimary("modem")
if m then
	-- hopefully online...
	m.open(minitelport)
end

---@type string[]
local dedupeCache = {}
local MAX_DEDUPE = 256

--- Host to layer-2 address
---@type {host: string, device: string, timeout: number}[]
local dynamicRouteInfo = {}

local dynRouteTimeout = 30

--- Static route information
---@type table<string, string>
local staticRouteInfo = {}

local function genPacketID()
	return string.random(8)
end

assert(k.mklistener(function(ev, receiver, sender, port, distance, packetID, packetType, dest, src, vport, data)
	if ev == "primary_removed" and receiver == "modem" then
		m = nil -- uh oh, we're offline!
		return
	end
	if ev == "primary_added" and receiver == "modem" then
		-- back online
		m = assert(k.cprimary("modem"))
		m.open(minitelport)
		return
	end
	if not m then return end
	if ev ~= "modem_message" then return end
	if port ~= minitelport then return end

	if table.contains(dedupeCache, packetID) then
		-- TODO: check if its a packet for us that is reliable and re-send ack
		return
	end
	table.insert(dedupeCache, packetID)
	while #dedupeCache > MAX_DEDUPE do
		table.remove(dedupeCache, 1)
	end
	if dest == "~" or dest == k.hostname() then
		if packetType == PACK_RELIABLE then
			m.send(sender, port, genPacketID(), PACK_ACK, src, dest, vport, packetID)
		end
		return
	end
	m.broadcast(port, packetID, packetType, dest ,src, vport, data)
end))

assert(k.mkdriver(function(ev, ...)
	if ev == "NET-socket" then
		---@type string, string, string?
		local domain, socktype, protocol = ...
		if domain ~= "AF_MINITEL" then return end
		if not m then return nil, errnos.ENETDOWN end
		protocol = protocol or "raw"
		-- TODO: actually create the socket and such
	end
end))

k.invokeDaemon("initd", "markComplete")

k.kill(k.getpid(), "SIGSTOP")
coroutine.yield()
