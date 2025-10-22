--!lua

local label = ...

local addr = assert(k.cramfs({items = {}}, label, false))
print(addr)
