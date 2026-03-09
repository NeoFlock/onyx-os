---@diagnostic disable: lowercase-global

if not k then
	---@type Kocos.syscalls
	k = {}
	local l = assert(syscall("syscalls"))

	for _, name in ipairs(l) do
		k[name] = function(...)
			return syscall(name, ...)
		end
	end
	setmetatable(k, {__index = function(t, k)
		if type(k) ~= "string" then return end
		local f = function(...)
			return syscall(k, ...)
		end
		rawset(t, k, f)
		return f
	end})
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
