--!lua

local readline = require("readline")

print("\x1b[36mAsh\x1b[32m v0.0.1\x1b[0m")
while true do
	local cwd = assert(syscall("chdir", "."))
	syscall("write", 1, "\x1b[36mroot\x1b[0m@\x1b[33mhostname\x1b[0m ")
	syscall("write", 1, cwd)
	syscall("write", 1, " > ")
	local line = readline()
	if line then
		local args = string.split(line:sub(1, -2), " ")
		if #args > 0 then
			local cmd = "/bin/" .. table.remove(args, 1) .. ".lua"
			args[0] = cmd
			local child = assert(syscall("fork", function()
				local ok, err = syscall("exec", cmd, args)
				if not ok then
					print("\x1b[31mError\x1b[0m:", err)
				end
			end))
			syscall("waitpid", child)
		end
	end
end
