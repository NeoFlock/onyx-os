--!lua

local t = "poweroff"
local instant = false

local args = {...}

while #args > 0 do
	local arg = table.remove(args, 1)
	if arg == "--force" or arg == "-f" then
		instant = true
	end
	if arg == "--poweroff" or arg == "-p" then
		t = "poweroff"
	end
	if arg == "--reboot" or arg == "-r" then
		t = "reboot"
	end
end

local ok, err = k.invokeDaemon("initd", "poweroff", t, instant)
if not ok then print("Error:", err) return 1 end
