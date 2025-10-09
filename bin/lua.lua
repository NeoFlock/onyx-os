--!lua

-- lua.lua is a lua script that runs lua

local argv = {...}
local readline = require("readline")

local function showVersionInfo()
	print(_VERSION, _OSVERSION, _KVERSION)
end

local function interactive()
	while true do
		k.write(1, "\x1b[34mlua>\x1b[0m ")
		local code = readline()
		if not code then break end
		if code:sub(1, 1) == "=" then
			code = "return " .. code:sub(2)
		end

		local f, err1 = load(code, "=stdin")
		if f then
			local t = {xpcall(f, debug.traceback)}
			if t[1] then
				local bufs = {}
				for i=2,#t do
					bufs[i-1] = table.serialize(t[i])
				end
				print(table.concat(bufs, ", "))
			else
				print("\x1b[31mError\x1b[0m:", t[2])
			end
		else
			print("\x1b[31mError\x1b[0m:", err1)
		end
	end
end

local function executeStdin()
	error("Executing stdin is not implemented yet")
end

if #argv == 0 then
	showVersionInfo()
	interactive()
	return 0
end

-- best argument parser ever
local interactiveAfterScript = false
while true do
	local arg = argv[1]
	if not arg then break end
	if arg:sub(1,1) ~= "-" then break end
	table.remove(argv, 1)
	if arg == "--" then
		break -- stop handling options
	elseif arg == "-" then
		executeStdin()
		break
	elseif arg == "-v" then
		showVersionInfo()
	elseif arg == "-i" then
		interactiveAfterScript = true
	elseif arg == "-e" then
		local expr = assert(table.remove(argv, 1), "missing statement")
		assert(load(expr, "=cmdline"))()
	elseif arg == "-l" then
		local lib = assert(table.remove(argv, 1), "missing lib")
		local eql = string.find(lib, "=")
		if eql then
			local name = string.sub(lib, 1, eql-1)
			lib = string.sub(lib, eql+1)
			_G[name] = require(lib)
		else
			_G[lib] = require(lib)
		end
	else
		print("Unrecognized option:", arg)
		print("Usage: lua5.1 [options] [script [args]]", k.argv()[0])
		print("Available options are:")
		print("\t-e stat   Execute string 'stat'")
		print("\t-l mod    mod = require`mod`")
		print("\t-l g=mod  g = require`mod`")
		print("\t-i        Enter interactive mode")
		print("\t-v        Show version information")
		print("\t--        Stop handling options")
		print("\t-         Stop handling options and read stdin")
	end
end

if argv[1] then
	local c = assert(readfile(argv[1]))
	assert(load(c, "=" .. argv[1]))(table.unpack(argv, 2))
end

if interactiveAfterScript then
	interactive()
end
