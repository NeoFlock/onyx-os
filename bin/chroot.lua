--!lua

local userdb = require("userdb")
local shutils = require("shutils")

-- TODO: let user select another user

local uinfo = assert(userdb.getinfo(shutils.getUser()), "unknown user")

local args = {...}
local root = table.remove(args, 1)
assert(root, "missing root")

assert(k.chroot(root))
local cmd = table.remove(args, 1)

if cmd then
	cmd = assert(shutils.search(cmd), "no such command")
else
	cmd = uinfo.shell
end

assert(k.exec(cmd, args))
