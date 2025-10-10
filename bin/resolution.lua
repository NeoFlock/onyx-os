--!lua

local terminal = require("terminal")

local term = terminal.stdterm()

local args = {...}

if args[1] == "max" then
	local w, h = term:maxResolution()
	print(w,"x",h)
	return
end

if #args >= 2 then
	local w = tonumber(args[1]) or 80
	local h = tonumber(args[2]) or 50
	term:setResolution(w, h)
end

local w, h = term:getResolution()
print(w,"x",h)
