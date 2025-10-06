--!lua

local a = {...}

for _, short in ipairs(a) do
	print(assert(k.caddress(short)))
end
