--!lua

local dirs = ...

for _, dir in ipairs(dirs) do
	assert(k.mknod(dir, "directory"))
end
