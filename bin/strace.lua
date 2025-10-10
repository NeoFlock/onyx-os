--!lua

local shutils = require("shutils")

local args = {...}

local cmd = table.remove(args, 1)
assert(cmd, "missing command")

local bin = shutils.search(cmd)
assert(bin, "no such command")

local tracer = k.getpid()

local spawnedBy = {}

local function lineage(pid)
	if not spawnedBy[pid] then return tostring(pid) end
	return tostring(pid) .. " <- " .. lineage(spawnedBy[pid])
end

k.signal("SIGSYSR", function(cpid, sysname, argv, retc)
	if sysname == "fork" then
		if retc[1] then
			-- track process hierarchies
			spawnedBy[retc[1]] = cpid
		end
	end
	for i=1,#argv do
		argv[i] = table.serialize(argv[i], nil, table.colorTypeInfo)
	end
	for i=1,#retc do
		retc[i] = table.serialize(retc[i], nil, table.colorTypeInfo)
	end
	while #retc < 2 do
		table.insert(retc, table.serialize(nil, nil, table.colorTypeInfo))
	end
	local argstr = table.concat(argv, ", ")
	local retstr = table.concat(retc, ", ")
	local s = string.format("[%s] %s(%s) = %s", lineage(cpid), sysname, argstr, retstr)
	print(s)
end)

local child = assert(k.fork(function()
	assert(k.strace(tracer))
	assert(k.exec(bin, args))
end))
spawnedBy[child] = tracer
return assert(k.waitpid(child))
