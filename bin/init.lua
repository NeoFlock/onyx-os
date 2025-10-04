--!lua

assert(syscall("write", 1, "Welcome to " .. _OSVERSION .. "\n"))

print("Hello, world!")

-- don't care
assert(syscall("close", 0))
assert(syscall("close", 1))
assert(syscall("close", 2))

Kocos.printk(Kocos.L_AUTOFIX, "Disabling kernel logger...")

Kocos.disableScreenLogging = true
Kocos.disableDefaultPanicHandler = true
