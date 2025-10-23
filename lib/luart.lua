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
	local s = table.concat(t, " ") .. "\n"
	if io then
		io.write(s)
	else
		assert(k.write(1, s))
	end
end

-- very useful libs!!!!
require("os")
require("io")
return true
