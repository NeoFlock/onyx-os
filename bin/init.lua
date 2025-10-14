--!lua

assert(Kocos, "not running in kernel address space")

local kBootTime = k.uptime()
local predTime = kBootTime
local cmdTime = kBootTime
local lastCmdTime = kBootTime
Kocos.printkf(Kocos.L_INFO, "Reached init in %s", string.boottimefmt(kBootTime))
print("Welcome to \x1b[38;5;2m" .. _OSVERSION .. "\x1b[0m")

---@type table<string, _G>
local addrs = {
	-- default address spaces
	kernel = _G,
	system = table.luaglobals(),
	user = table.luaglobals(),
	cmd = table.luaglobals(),
}

-- Setup daemon

---@class onyx.init.service
---@field name string
---@field deps string[]
---@field cwd string
---@field exec string
---@field args string[]
---@field env table<string, string>
---@field addr string

---@class onyx.init.command
---@field name string
---@field priority integer
---@field cwd string
---@field exec string
---@field args string[]
---@field env table<string, string>
---@field addr string

---@type table<string, onyx.init.service>
local serviceInfo = {}
---@type table<string, boolean>
local servicesLoaded = {}
---@type table<integer, string>
local serviceFromPids = {}

---@type onyx.init.command[]
local cmds = {}

---@param path string
---@return table
local function loadFileInfoStuff(path)
	local f = assert(k.open(path, "r"))
	local data = ""
	while true do
		local chunk, err = k.read(f, 1024)
		if err then
			k.close(f)
			error(err)
		end
		if not chunk then break end
		data = data .. chunk
		coroutine.yield()
	end
	k.close(f)

	return assert(load("return " .. data, "=" .. path, nil, {}))()
end

-- Prelude steps (likely in ramfs)
local preludeFiles = assert(k.list("/etc/preluded"))
local preludes = {}
for _, file in ipairs(preludeFiles) do
	Kocos.printkf(Kocos.L_INFO, "Found command file: %s", file)
	---@type onyx.init.command
	local info = loadFileInfoStuff("/etc/preluded/" .. file)
	info.priority = info.priority or 100
	info.args = info.args or {}
	info.env = info.env or {}
	info.cwd = info.cwd or "/home"
	info.addr = info.addr or "user"
	table.insert(preludes, info)
end

Kocos.printkf(Kocos.L_INFO, "Running %d prelude steps", #preludes)
for _, cmd in ipairs(preludes) do
	Kocos.printkf(Kocos.L_INFO, "Running %s", cmd.name)
	lastCmdTime = k.uptime()
	local child = assert(k.fork(function()
		assert(k.chdir(cmd.cwd))
		assert(k.exec(cmd.exec, cmd.args, cmd.env, addrs[cmd.addr]))
	end))
	assert(k.waitpid(child))
end
predTime = k.uptime()

-- Load services (likely out of ramfs)
local serviceFiles = assert(k.list("/etc/services"))
local commandFiles = assert(k.list("/etc/initd"))

for _, file in ipairs(serviceFiles) do
	Kocos.printkf(Kocos.L_INFO, "Found service file: %s", file)
	---@type onyx.init.service
	local info = loadFileInfoStuff("/etc/services/" .. file)
	info.deps = info.deps or {}
	info.args = info.args or {}
	info.env = info.env or {}
	info.cwd = info.cwd or "/"
	info.addr = info.addr or "system"
	serviceInfo[info.name] = info
end

for _, file in ipairs(commandFiles) do
	Kocos.printkf(Kocos.L_INFO, "Found command file: %s", file)
	---@type onyx.init.command
	local info = loadFileInfoStuff("/etc/initd/" .. file)
	info.priority = info.priority or 100
	info.args = info.args or {}
	info.env = info.env or {}
	info.cwd = info.cwd or "/home"
	info.addr = info.addr or "user"
	table.insert(cmds, info)
end

---@param action string
k.registerDaemon("initd", function(cpid, action, ...)
	if type(action) ~= "string" then return nil, "bad request" end

	if action == "timings" then
		return {
			bios = Kocos.biosBootTime,
			kernel = kBootTime,
			prelude = predTime,
			allServices = cmdTime,
			currentCommand = lastCmdTime,
		}
	end

	if action == "waitFor" then
		local services = {...}
		k.blockUntil(cpid, function()
			for _, serv in ipairs(services) do
				if not servicesLoaded[serv] then return false end
			end
			return true
		end)
		return true
	end

	if action == "markComplete" then
		local service = serviceFromPids[cpid]
		if not service then return nil, "not a service" end
		Kocos.printkf(Kocos.L_INFO, "%s completed", service)
		servicesLoaded[service] = true
		return true
	end
end)

-- Debug handlers
k.signal("SIGCHLD", function(cpid, exit)
	local serv = serviceFromPids[cpid]
	if not serv then return end -- command, don't care
	Kocos.printkf(Kocos.L_WARN, "Service %s exited with %s", serv, tostring(exit))
end)

-- Launch services
Kocos.printkf(Kocos.L_INFO, "Launching %d services", #serviceFiles)
local allServices = {}
for service, info in pairs(serviceInfo) do
	Kocos.printkf(Kocos.L_INFO, "Launching %s", service)
	table.insert(allServices, service)
	local pid = assert(k.fork(function()
		assert(k.chdir(info.cwd))
		assert(k.invokeDaemon("initd", "waitFor", table.unpack(info.deps)))
		assert(k.exec(info.exec, info.args, info.env, addrs[info.addr]))
	end))
	serviceFromPids[pid] = service
end

Kocos.printkf(Kocos.L_INFO, "Waiting for %d services", #serviceFiles)
k.invokeDaemon("initd", "waitFor", table.unpack(allServices))

cmdTime = k.uptime()
Kocos.printkf(Kocos.L_INFO, "Finished services in %s (%s total)", string.boottimefmt(cmdTime - kBootTime), string.boottimefmt(cmdTime))

table.sort(cmds, function(a, b) return a.priority > b.priority end)

-- Run commands
Kocos.printkf(Kocos.L_INFO, "Running %d commands", #cmds)
for _, cmd in ipairs(cmds) do
	Kocos.printkf(Kocos.L_INFO, "Running %s", cmd.name)
	lastCmdTime = k.uptime()
	local child = assert(k.fork(function()
		assert(k.chdir(cmd.cwd))
		assert(k.exec(cmd.exec, cmd.args, cmd.env, addrs[cmd.addr]))
	end))
	assert(k.waitpid(child))
end

Kocos.printkf(Kocos.L_INFO, "All commands have finished")
