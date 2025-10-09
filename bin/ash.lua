--!lua

local readline = require("readline")
local userdb = require("userdb")

local users = userdb.parsePasswd() or {}

local function getusername()
	for _, user in ipairs(users) do
		if user.uid == k.geteuid() then
			return user.name
		end
	end
	return "root"
end

print("\x1b[36mAsh\x1b[32m v0.0.1\x1b[0m")
while true do
	local cwd = assert(k.chdir("."))
	k.write(1, string.format("\x1b[36m%s\x1b[0m@\x1b[33m%s\x1b[0m ", getusername(), k.hostname()))
	k.write(1, "\x1b[32m")
	k.write(1, cwd)
	k.write(1, " > ")
	k.write(1, "\x1b[0m")
	local line = readline()
	if not line then return end
	local args = string.split(line:sub(1, -2), " ")
	if #args > 0 then
		local cmd = "/bin/" .. table.remove(args, 1) .. ".lua"
		if cmd == "/bin/exit.lua" then
			return tonumber(args[2]) or 0
		else
			args[0] = cmd
			local child = assert(k.fork(function()
				local ok, err = k.exec(cmd, args)
				if not ok then
					print("\x1b[31mError\x1b[0m:", err)
				end
			end))
			k.waitpid(child)
		end
	end
end
