--!lua

local addr, filter = ...
local exact = false
if filter then
	exact = filter:sub(1,1) == "="
	if exact then filter = filter:sub(2) end
end
addr = assert(k.caddress(addr, filter, exact))
print(k.ctype(addr))
