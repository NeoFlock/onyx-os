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
		__pairs = function()
			return pairs(assert(syscall("syscalls")))
		end,
	})
end

function print(...)
	assert(k.write(1, table.concat({...}, " ") .. "\n"))
end
