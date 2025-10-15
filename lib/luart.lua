---@diagnostic disable: lowercase-global
-- TODO: use io once it is made

if not k then
	---@type Kocos.syscalls
	k = setmetatable({}, {
		__mode = "v",
		__index = function(t, sys)
			local f = function(...)
				return syscall(sys, ...)
			end
			rawset(t, sys, f)
			return f
		end,
	})
end

function print(...)
	local t = {...}
	for i=1,#t do t[i]=tostring(t[i]) end
	assert(k.write(1, table.concat(t, " ") .. "\n"))
end

-- very useful libs!!!!
require("os")
require("io")
return true
