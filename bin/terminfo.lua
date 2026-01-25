--!lua

local terminal = require("terminal")

local fd = tonumber((...)) or terminal.STDTERM
local f = terminal.fterminfo(fd)

print(table.serialize(f, nil, table.colorTypeInfo))
return f and 0 or 1
