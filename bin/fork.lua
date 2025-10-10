--!lua

local shutils = require("shutils")

local args = {...}
local cmd = table.remove(args, 1)
assert(cmd, "missing command")

local bin = shutils.search(cmd)
assert(bin, "command not found")

local child = assert(k.fork(function()
	assert(k.exec(bin, args))
end))

return assert(k.waitpid(child))
