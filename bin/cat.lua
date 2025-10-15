--!lua

local paths = {...}

local blockSize = 4096

for _, path in ipairs(paths) do
	local f = assert(k.open(path, "r"))
	while true do
		local data, err = k.read(f, blockSize)
		if err then
			k.close(f)
			error(err)
		end
		if not data then break end
		k.write(1, data)
	end
	k.close(f)
end
