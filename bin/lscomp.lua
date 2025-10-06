--!lua

local filter = ...

for addr, type in k.clist(filter) do
	print(addr, type)
end
