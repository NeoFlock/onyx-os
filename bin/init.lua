--!lua

assert(Kocos, "not running in kernel address space")

print("Welcome to \x1b[38;5;2m" .. _OSVERSION .. "\x1b[0m")

-- TODO: boot services

k.chdir("/home")

-- Go directly to shell for now
k.exec("/bin/sh", nil, nil, table.luaglobals())
