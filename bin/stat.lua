--!lua

local paths = {...}

for _, path in ipairs(paths) do
	local s = assert(k.stat(path))
	print(path)
	print("Dev:", s.deviceAddress)
	print("DevType:", s.deviceType)
	print("Size:", string.memformat(s.size))
	print("Created at:", os.date("%x %X", math.floor(s.createdAt / 1000)))
	print("Last Modified:", os.date("%x %X", math.floor(s.lastModified / 1000)))
	print("Size On Disk:", string.memformat(s.diskSize))
	print("Disk Used:", string.memformat(s.diskUsed))
	print("Disk Total:", string.memformat(s.diskTotal))
	print("Ino:", s.inode)
	print("Perms:", s.perms) -- TODO: show them stringified
end
