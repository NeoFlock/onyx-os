--!lua

local path = ...

path = path or "."

local d = assert(k.list(path))

print(table.concat(d, " "))
