--!lua

local daemons = assert(k.listDaemons())

for _, daemon in ipairs(daemons) do
	local pid = assert(k.getDaemonPid(daemon))
	print(daemon, pid)
end
