--!lua

local readline = require("readline")
local shutils = require("shutils")
local userdb = require("userdb")

print("\x1b[36mAsh\x1b[32m v0.0.1\x1b[0m")
local history = {}
while true do
	k.write(1, shutils.promptFormatToAnsi(os.getenv("PS1")))
	k.write(1, "\x1b[0m ")
	local line = readline(nil, nil, nil, function(i) return history[i] end)
	if not line then return end
	local l = line:sub(1, -2)
	-- de-duplication
	if history[1] ~= l then
		table.insert(history, 1, l)
	end
	local args = string.split(l, " ")
	if #args > 0 then
		local cmd = table.remove(args, 1)
		if cmd == "exit" then
			return tonumber(args[1]) or 0
		elseif cmd == "cd" then
			assert(k.chdir(args[1] or userdb.getHome(shutils.getUser())))
		elseif cmd == "which" then
			print(shutils.search(args[1]) or "no such command")
		elseif cmd == "setprompt" then
			os.setenv("PS1", table.concat(args, " "))
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
