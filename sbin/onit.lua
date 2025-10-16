--!lua

local conf = require("conf")

assert(Kocos, "not running in kernel address space")

local biosTime = Kocos.biosBootTime
local kBootTime = k.uptime()
local lastCmdTime = kBootTime
print("Welcome to \x1b[38;5;2m" .. _OSVERSION .. "\x1b[0m!")

local onitServiceDir = "/etc/onit.d"

---@type _G? Whether to share all globals
local shared = nil

---@type table<string, _G>
local addrs = {
	-- default address spaces
	kernel = _G,
}

---@param addr string
---@return _G
local function getAddress(addr)
	if not addrs[addr] then
		addrs[addr] = shared or table.luaglobals()
	end
	return addrs[addr]
end

---@type onit.service?
local toComplete = nil

---@class onit.service
---@field name string
---@field type "run"|"spawn"
---@field groups string[]
---@field needs string[]
---@field exec string
---@field argv string[]
---@field addr string
---@field loadTime? number
---@field completionTime? number
---@field pid? integer

---@type table<string, onit.service>
local services = {}
---@type string[]
local order = {}

---@type table<string, string[]>
local groups = {}

---@param service string
local function orderService(service)
	if service:sub(1,1) == "@" then
		local group = service:sub(2)
		local g = groups[group]
		if not g then return end
		for _, s in ipairs(g) do
			orderService(s)
		end
	end
	local info = services[service]
	if not info then return end
	if info.completionTime then return end
	info.completionTime = k.uptime()

	for _, dep in ipairs(info.needs) do
		orderService(dep)
	end

	table.insert(order, service)
end

local serviceFiles = assert(k.list(onitServiceDir))

for _, file in ipairs(serviceFiles) do
	local p = onitServiceDir .. "/" .. file
	local str = assert(readfile(p))
	local info = conf.decode(str)

	local name = info.name or file
	services[name] = {
		name = name,
		type = info.type or "run",
		groups = string.split(info.groups or "setup", ","),
		needs = info.needs and string.split(info.needs, ",") or {},
		exec = info.exec,
		argv = info.argv and string.split(info.argv, ",") or {},
		addr = info.addr or "system",
	}
	for _, g in ipairs(services[name].groups) do
		groups[g] = groups[g] or {}
		table.insert(groups[g], name)
	end
end

for s in pairs(services) do
	orderService(s)
end

assert(k.registerDaemon("initd", function(cpid, action, ...)
	if type(action) ~= "string" then return end
	if action == "markComplete" then
		if not toComplete then return end
		if toComplete.pid ~= cpid then return end
		toComplete.completionTime = k.uptime()
		toComplete = nil
		coroutine.yield()
	end
	if action == "timings" then
		return {
			bios = biosTime,
			kernel = kBootTime,
			currentCommand = lastCmdTime,
		}
	end
end))

for _, s in ipairs(order) do
	local info = services[s]
	lastCmdTime = k.uptime()
	info.loadTime = lastCmdTime
	if info.type == "spawn" then
		toComplete = info
		Kocos.printkf(Kocos.L_INFO, "Spawing %s...", info.name)
		assert(k.fork(function()
			info.pid = k.getpid()
			assert(k.exec(info.exec, info.argv, nil, getAddress(info.addr)))
		end))
		while toComplete do coroutine.yield() end
	elseif info.type == "run" then
		Kocos.printkf(Kocos.L_INFO, "Running %s...", info.name)
		assert(os.executeBin(info.exec, info.argv, nil, getAddress(info.addr)), "command failed")
	end
end

-- Shutdown!!!!
