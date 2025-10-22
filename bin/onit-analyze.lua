--!lua

local action = ...

if action == "blame" then
	return
end

local timings = k.invokeDaemon("initd", "timings")
print("BIOS:", string.boottimefmt(timings.bios))
print("Kernel:", string.boottimefmt(timings.kernel))
print("Boot Steps:", string.boottimefmt(timings.currentCommand))
