--!lua

local readline = require("readline")
local shutils = require("shutils")
local userdb = require("userdb")

print("\x1b[36mAsh\x1b[32m v0.0.1\x1b[0m")
while true do
	local cwd = shutils.printablePath(shutils.getWorkingDirectory())
	k.write(1, string.format("\x1b[36m%s\x1b[0m@\x1b[33m%s\x1b[0m ", shutils.getUser(), shutils.getHostname()))
	k.write(1, "\x1b[32m")
	k.write(1, cwd)
	k.write(1, " > ")
	k.write(1, "\x1b[0m")
	local line = readline()
	if not line then return end
	local args = string.split(line:sub(1, -2), " ")
	if #args > 0 then
		local cmd = table.remove(args, 1)
		if cmd == "exit" then
			return tonumber(args[1]) or 0
		elseif cmd == "cd" then
			assert(k.chdir(args[1] or userdb.getHome(shutils.getUser())))
		elseif cmd == "which" then
			print(shutils.search(args[1]) or "no such command")
		else
			local p = shutils.search(cmd)
			if p then
				args[0] = p
				local child = assert(k.fork(function()
					local ok, err = k.exec(p, args)
					if not ok then
						print("\x1b[31mError\x1b[0m:", err)
					end
				end))
				k.ioctl(3, "setfgpid", child)
				k.waitpid(child)
			else
				print("\x1b[31mError\x1b[0m: unknown command:", cmd)
			end
		end
	end
end
