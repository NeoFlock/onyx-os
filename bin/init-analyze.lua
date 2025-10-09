--!lua

local timings = k.invokeDaemon("initd", "timings")
print("BIOS:", string.boottimefmt(timings.bios))
print("Kernel:", string.boottimefmt(timings.kernel))
print("All Services:", string.boottimefmt(timings.allServices))
print("Boot Steps:", string.boottimefmt(timings.currentCommand))
