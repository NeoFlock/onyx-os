--!lua

local pid, action = ...
action = action or "SIGKILL" -- brutally murder

local npid = tonumber(pid)
if not npid then
	k.write(2, "Bad pid\n")
	return 1
end

local ok, err = k.kill(npid, action, select(3, ...))
if not ok then
	k.write(2, err .. "\n")
	return 1
end
return 0
