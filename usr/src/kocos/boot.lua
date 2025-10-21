Kocos.printkf(Kocos.L_INFO, "Booting %s...", _KVERSION)

Kocos.printkf(Kocos.L_DEBUG, "Detecting hardware...")
for addr, type in component.list() do
	Kocos.printkf(Kocos.L_DEBUG, "%s %s", addr, type)
end

-- At this point we're supposed to mount the bootfs, either ramfs image or actual root
Kocos.printk(Kocos.L_INFO, "mounting boot filesystem at /")

local rootDev

if Kocos.args.ramfs then
	rootDev = Kocos.addRamfsComponent(Kocos.args.ramfs, "ramfs")
	Kocos.printk(Kocos.L_DEBUG, "mounting as ramfs tmp root")
else
	rootDev = Kocos.args.root or computer.getBootAddress()
	Kocos.printk(Kocos.L_DEBUG, "mounting as managedfs true root")
end

do
	assert(rootDev, "missing root device")
	assert(Kocos.syscalls.chsysroot(rootDev))
end

local freeMem = computer.freeMemory()
local totalMem = computer.totalMemory()

Kocos.printkf(Kocos.L_INFO, "Free Memory: %s / %s", string.memformat(freeMem), string.memformat(totalMem))

---@alias Kocos.shutdownType "halt"|"poweroff"|"reboot"
---@type Kocos.shutdownType?
Kocos.shutdown = nil

if freeMem < 64*1024 then
	Kocos.printkf(Kocos.L_WARN, "FREE MEMORY IS BELOW 64KiB!!!")
end

local function tick()
	if Kocos.shutdown then
		Kocos.printkf(Kocos.L_INFO, "Attempting %s", Kocos.shutdown)
		Kocos.poweroff(Kocos.shutdown == "reboot")
		return
	end
	Kocos.process.run()
	local interval = Kocos.args.pollInterval or 0
	local percent = computer.energy() / computer.maxEnergy()
	if percent < 0.5 then
		interval = Kocos.args.midBatteryPollInterval or 0.1 -- idle longer to save battery
	end
	if percent < 0.1 then
		interval = Kocos.args.midBatteryPollInterval or 0.2 -- idle way longer to save battery
	end
	Kocos.event.pull(interval)
end

local initPaths = {
	-- init process
	"/sbin/init",
	"/bin/init",
	-- login???
	"/sbin/login",
	"/bin/login",
	-- shell???
	"/sbin/sh",
	"/bin/sh",
}

-- classic fork() exec()
local initProc = Kocos.process.fork(Kocos.process.root, function()
	Kocos.process.init.executionDeadline = math.huge
	for _, path in ipairs(initPaths) do
		if Kocos.syscalls.exists(path) then
			Kocos.printkf(Kocos.L_INFO, "Running %s...", path)
			assert(Kocos.syscalls.exec(path))
		end
	end
	Kocos.panickf("COULD NOT FIND INIT PROGRAM!\nSearched: %s\n", table.concat(initPaths, "\n"))
end)
Kocos.process.init = initProc

initProc.fds[1] = {
	refc = 4,
	opts = 0,
	file = Kocos.fs.fd_from_rwf(function(_, len)
		return Kocos.scr_read(len)
	end, function(_, data)
		local bufSize = 1024
		if #data <= bufSize then
			Kocos.scr_write(data)
			return true
		end
		-- makes it so you can't write 1MB and freeze the system
		for i=1,#data,bufSize do
			local buf = data:sub(i, i+bufSize - 1)
			Kocos.scr_write(buf)
			coroutine.yield()
		end
		return true
	end, nil, function(_, ...) return Kocos.scr_ioctl(...) end),
}

initProc.fds[0] = initProc.fds[1]
initProc.fds[2] = initProc.fds[1]
initProc.fds[3] = initProc.fds[1]

Kocos.process.resume(initProc)

local function justDie()
	pcall(computer.pullSignal, 2)
	computer.shutdown(true)
end

while true do
	local ok, err = xpcall(tick, debug.traceback)
	if not ok then
		pcall(Kocos.panickf, "Tick error: %s\n", err)
		justDie()
	end
end
