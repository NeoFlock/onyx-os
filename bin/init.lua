--!lua

assert(syscall("write", 1, "Welcome to " .. _OSVERSION .. "\n"))

print("Hello, world!")

Kocos.printk(Kocos.L_AUTOFIX, "Disabling kernel logger...")

Kocos.disableScreenLogging = true
Kocos.disableDefaultPanicHandler = true
