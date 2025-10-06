Kocos.printkf(Kocos.L_INFO, "Booting %s...", _KVERSION)

Kocos.printkf(Kocos.L_DEBUG, "Detecting hardware...")
for addr, type in component.list() do
	Kocos.printkf(Kocos.L_DEBUG, "%s %s", addr, type)
end

local freeMem = computer.freeMemory()
local totalMem = computer.totalMemory()

Kocos.printkf(Kocos.L_INFO, "Free Memory: %s / %s", string.memformat(freeMem), string.memformat(totalMem))

if freeMem < 64*1024 then
	Kocos.printkf(Kocos.L_WARN, "FREE MEMORY IS BELOW 64KiB!!!")
end

local function tick()
	Kocos.event.pull()
	Kocos.process.run()
end

local initPaths = {
	-- init process
	"/sbin/init",
	"/sbin/init.lua",
	"/sbin/init.sh",
	"/bin/init",
	"/bin/init.lua",
	"/bin/init.sh",
	-- login???
	"/sbin/login",
	"/sbin/login.lua",
	"/sbin/login.sh",
	"/bin/login",
	"/bin/login.lua",
	"/bin/login.sh",
	-- shell???
	"/sbin/sh",
	"/sbin/sh.lua",
	"/bin/sh",
	"/bin/sh.lua",
}

-- classic fork() exec()
local initProc = Kocos.process.fork(Kocos.process.root, function()
	for _, path in ipairs(initPaths) do
		if syscall("exists", path) then
			Kocos.printkf(Kocos.L_INFO, "Running %s...", path)
			assert(syscall("exec", path))
		end
	end
	Kocos.panickf("COULD NOT FIND INIT PROGRAM!\nSearched: %s\n", table.concat(initPaths, "\n"))
end)
Kocos.process.init = initProc

initProc.fds[1] = {
	refc = 3,
	opts = 0,
	file = Kocos.fs.fd_from_rwf(function(_, len)
		return Kocos.scr_read(len)
	end, function(_, data)
		Kocos.scr_write(data)
		return true
	end, nil, function(_, ...) return Kocos.scr_ioctl(...) end),
}

initProc.fds[0] = initProc.fds[1]
initProc.fds[2] = initProc.fds[1]

local function justDie()
	pcall(computer.pullSignal, 2)
	computer.shutdown(true)
end

while true do
	local ok, err = xpcall(tick, debug.traceback)
	if not ok then
		local panic_ok = pcall(Kocos.panickf, "Tick error: %s\n", err)
		if Kocos.args.permissiveCrashes then
			if panic_ok then
				-- eventually determine how bad the system is based
				-- off the rate of panics
			else
				-- if panic handler also dies we might as well give up
				justDie()
			end
		else
			-- just die instantly
			-- the state is so horrible its not worth preserving
			justDie()
		end
	end
end
