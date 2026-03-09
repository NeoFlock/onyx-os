--!lua

local path = ...

local ok, err = k.umount(path)
if not ok then
	io.ewrite("umount: ", err, "\n")
	return 1
end
