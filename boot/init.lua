-- Orbit bootloader

local bootLocation = ...

local boot = computer.getBootAddress()

local function readBootFile(path)
	if component.type(boot) == "filesystem" then
		bootLocation = bootLocation or ""
		path = bootLocation .. "/" .. path

		local f = component.invoke(boot, "open", path, "r")
		if not f then return end
		local data = ""
		while true do
			local chunk = component.invoke(boot, "read", f, math.huge)
			if not chunk then break end
			data = data .. chunk
		end
		component.invoke(boot, "close", f)
		return data
	elseif component.type(boot) == "drive" then
	end
end

local conf = {}
do
	local confSrc = readBootFile("orbit.conf")
	if confSrc then
		conf = assert(load(confSrc))()
	end
end

local function bootSystem(system)
	local kernel = assert(readBootFile(system.kernel), "missing kernel")
	local ramfs = system.ramfs and readBootFile(system.ramfs) or nil

	if system.protocol == "generic" then
		assert(load(kernel, "=kernel"))()
	elseif system.protocol == "kocos" then
		assert(load(kernel, "=kernel"))("kocos", system.cmdline, ramfs)
	end
	error("system halted")
end

local gpuAddr, screen = component.list("gpu")(), component.list("screen")()

if gpuAddr and screen then
	local fg = conf.foreground or 0xFFFFFF
	local bg = conf.background or 0x000000
	local cur = 1
	local gpu = assert(component.proxy(gpuAddr))

	gpu.bind(screen)
	local w, h = gpu.maxResolution()
	gpu.setResolution(w, h)
	gpu.setForeground(fg)
	gpu.setBackground(bg)
	gpu.fill(1, 1, w, h, " ")

	local idleTime = conf.bootAfter or 5
	local lastAction = computer.uptime()

	while true do
		-- render
		local elapsed = computer.uptime() - lastAction
		gpu.setForeground(fg)
		gpu.setBackground(bg)
		gpu.fill(1, 1, w, h, " ")
		gpu.set(1, 1, "Orbit Bootloader")
		for i=1,#conf.systems do
			local pref = cur == i and "> " or ""
			gpu.set(1, i+1, pref .. conf.systems[i].name)
		end
		gpu.setForeground(bg)
		gpu.setBackground(fg)
		gpu.fill(1, h, math.floor(w * elapsed / idleTime), 1, " ")
		local e = {computer.pullSignal(0.5)}
		if e[1] == "key_down" then
			lastAction = computer.uptime()
			if e[4] == 0x1C then
				gpu.setForeground(fg)
				gpu.setBackground(bg)
				gpu.fill(1, 1, w, h, " ")
				bootSystem(conf.systems[cur])
			end
			if e[4] == 0xC8 then
				cur = cur - 1
			end
			if e[4] == 0xD0 then
				cur = cur + 1
			end
		end
		-- actions
		if cur < 1 then cur = 1 end
		if cur > #conf.systems then cur = #conf.systems end
		elapsed = computer.uptime() - lastAction
		if elapsed >= idleTime then
			bootSystem(conf.systems[cur])
		end
	end
else
	bootSystem(conf.systems[1])
end
