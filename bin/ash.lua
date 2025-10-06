--!lua

local readline = require("readline")

print("\x1b[36mAsh\x1b[32m v0.0.1\x1b[0m")
while true do
	local cwd = assert(k.chdir("."))
	k.write(1, string.format("\x1b[36mroot\x1b[0m@\x1b[33m%s\x1b[0m ", k.hostname()))
	k.write(1, "\x1b[32m")
	k.write(1, cwd)
	k.write(1, " > ")
	k.write(1, "\x1b[0m")
	local line = readline()
	if line then
		local args = string.split(line:sub(1, -2), " ")
		if #args > 0 then
			local cmd = "/bin/" .. table.remove(args, 1) .. ".lua"
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
