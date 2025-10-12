--!lua

local userdb = require("userdb")
local shutils = require("shutils")
local readline = require("readline")

-- TODO: let user select another user
local user = shutils.getUser()

local uinfo = assert(userdb.getinfo(user), "unknown user")

local args = {...}
local cmd = table.remove(args, 1)

if not cmd then
	cmd = uinfo.shell
end

cmd = assert(shutils.search(cmd), "no such command")

while true do
	-- authenticate
	k.write(1, "[sudo] password for " .. user .. ": ")
	local l = readline(nil, nil, "")
	if not l then break end
	local ok, err = k.invokeDaemon("sudod", "chuser", user, l:sub(1, -2))
	if ok then
		break
	else
		k.write(2, err .. "\n")
	end
end

assert(k.exec(cmd, args))
