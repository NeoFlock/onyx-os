--!lua

local filter = ...

for _, type in k.clist(filter) do
	print(k.cprimaryaddr(type), type)
end
