--!lua

if select("#", ...) == 0 then
	print("args", "env", "uid", "gid", "parent", "tree", "state", "namespace", "signals")
	return
end

if select("#", ...) == 1 then
	print("Error: no info arguments")
	return 1
end

local function printInfoFor(pid, args)
	local info = assert(k.getprocinfo(pid, table.unpack(args)))

	if info.argv then
		print("Argv:", info.argv[0])
		print("Args:", table.concat(info.argv, " "))
	end

	if info.environ then
		print("Environment:")
		for k, v in pairs(info.environ) do
			print(k, "=", v)
		end
	end

	if info.uid then
		print("UID:", info.uid)
	end
	if info.euid then
		print("Effective UID:", info.euid)
	end

	if info.gid then
		print("GID:", info.gid)
	end
	if info.egid then
		print("Effective GID:", info.egid)
	end

	if info.parent then
		print("Parent PID:", info.parent)
	end
	if info.tracer then
		print("Tracer PID:", info.tracer)
	end

	if info.exitcode then
		print("Exitcode:", info.exitcode)
	end

	if info.cwd then
		print("CWD:", info.cwd)
	end
	if info.exe then
		print("EXE:", info.exe)
	end

	if info.namespace then
		print("Namespace: " .. tostring(info.namespace))
	end

	if info.children then
		print("Children:")
		for _, cpid in ipairs(info.children) do
			print("-", cpid)
		end
	end

	if info.signals then
		print("Signals:")
		for _, sig in ipairs(info.signals) do
			print("-", sig)
		end
	end
end

local pidStr = (...)
local args = {select(2, ...)}

if (...) == "*" then
	for _, pid in ipairs(assert(k.getprocs())) do
		print("PID:", pid)
		printInfoFor(pid, args)
	end
	return
end

local pid = assert(tonumber(pidStr), "bad pid")
printInfoFor(pid, args)
