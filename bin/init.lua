--!lua

assert(syscall("write", 1, "Welcome to \x1b[38;5;2m" .. _OSVERSION .. "\x1b[0m\n"))

-- TODO: boot services

assert(syscall("chdir", "/home"))

-- Go directly to shell for now
assert(syscall("exec", "/bin/sh", nil, nil, table.luaglobals()))
