--!lua

local info = k.sysinfo()
print("Kernel:", info.kernel)
print("OS:", info.os)
print("Host:", info.hostname)
print("Boot:", info.bootAddress)
print("Root:", info.rootAddress)
print("Tmp:", info.tmpAddress)
print("Total Memory:", string.memformat(info.memtotal))
print("Free Memory:", string.memformat(info.memfree))
print("Energy:", info.energy, "/", info.maxEnergy, "FE")
print("Kernel PID:", info.kernelPID)
print("Init PID:", info.initPID)
