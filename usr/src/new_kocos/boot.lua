Kocos.printk(Kocos.L_INFO, "Base kernel loaded")
Kocos.printkf(Kocos.L_INFO, "Loading modules from %s...", Kocos.modulePath)

do
	local modules = assert(syscalls.list(Kocos.modulePath))

	for _, mod in ipairs(modules) do
		if string.endswith(mod, ".lua") then
			local m = mod:sub(1, -5)
			Kocos.printkf(Kocos.L_INFO, "Loading module %q", m)
			assert(Kocos.loadModule(m))
		end
	end
end

Kocos.printk(Kocos.L_INFO, "Booting...")

Kocos.printk(Kocos.L_INFO, "Spawning init...")
assert(syscalls.fork(function()
	Kocos.printk(Kocos.L_INFO, "Searching for init...")
	local files = {
		-- standard init path
		"/sbin/init",
		-- a more conventional init
		"/bin/init",
		-- old UNIX init?
		"/etc/init",
		-- If all else fails, shell
		"/sbin/sh",
		"/bin/sh",
		"/etc/sh",
	}

	local exts = {"", ".lua", ".sh", ".bin", ".exe"}

	for _, path in ipairs(files) do
		for _, ext in ipairs(exts) do
			local toCheck = path .. ext
			if syscalls.exists(toCheck) then
				Kocos.printkf(Kocos.L_INFO, "Found %s", toCheck)
				local ok, err = syscalls.exec(toCheck)
				if not ok then
					Kocos.panickf("Could not exec %s: %s", toCheck, err)
				end
			end
		end
	end

	Kocos.panick("No init found!")
end))

Kocos.printk(Kocos.L_INFO, "Running event loop...")
while true do
	if Kocos.shutdown == "halt" then
		break
	end
	if Kocos.shutdown == "reboot" then
		computer.shutdown(true)
	end
	if Kocos.shutdown == "poweroff" then
		computer.shutdown(false)
	end

	Kocos.tickProcesses()
	Kocos.pull(0.05)
end
