--!lua

local argv = {...}
local bin = table.remove(argv, 1)

if not k.exists(bin) then
	print("error: no such file")
	return 1
end

for i=1,#argv do argv[i] = string.format("%q", argv[i]) end

local s = string.format("--!lua\nassert(k.exec(%q, {%s}))\n", bin, table.concat(argv, ", "))
assert(writefile("/sbin/init", s))
