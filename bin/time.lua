--!lua

local shutils = require("shutils")

local args = {...}
local cmd = table.remove(args, 1)
cmd = assert(shutils.search(cmd), "no such command")

local start = k.uptime()
local child = assert(k.fork(function()
	assert(k.exec(cmd, args))
end))
k.waitpid(child)
local now = k.uptime()

print(cmd, table.concat(args, " "), string.format("%03.03fs total", now - start))
