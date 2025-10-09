--!lua

local bootAddr = ...

if not bootAddr then
	print(k.chboot())
	return
end

print(assert(k.chboot(assert(k.caddress(bootAddr)))))
