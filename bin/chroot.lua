--!lua

local userdb = require("userdb")
local shutils = require("shutils")

-- TODO: let user select another user

local uinfo = assert(userdb.getinfo(shutils.getUser()), "unknown user")

local args = {...}
local root = table.remove(args, 1)
assert(root, "missing root")
local cmd = table.remove(args, 1)

if not cmd then
	cmd = uinfo.shell
end

cmd = assert(shutils.search(cmd), "no such command")

assert(k.chroot(root))
assert(k.exec(cmd, args))
