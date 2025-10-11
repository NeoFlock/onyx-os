--!lua

local srcPath, destPath = ...

local blockSize = 4096

local src = assert(k.open(srcPath, "r"))
local dest = assert(k.open(destPath, "r"))

while true do
	local data, err = k.read(src, blockSize)
	if err then error(err) end
	if not data then break end
	assert(k.write(dest, data))
	coroutine.yield()
end

-- exiting closes fds
