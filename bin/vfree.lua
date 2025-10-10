--!lua

local terminal = require("terminal")

local free, total = terminal.stdio():requestVRAM()

print("total", total)
print("used", total - free)
print("free", free)
