--!lua

local perms = require("perms")
local userdb = require("userdb")

local users = assert(userdb.parsePasswd())
local groups = assert(userdb.parseGroup())

local paths = {...}

for _, path in ipairs(paths) do
	local s = assert(k.stat(path))
	print(path)
	print("Type:", s.type)
	print("Dev:", s.deviceAddress)
	print("DevType:", k.ctype(s.deviceAddress))
	print("Size:", string.memformat(s.size))
	print("Last Modified:", os.date("%x %X", math.floor(s.lastModified / 1000)))
	print("Size On Disk:", string.memformat(s.diskSize))
	print("Disk Used:", string.memformat(s.diskUsed))
	print("Disk Total:", string.memformat(s.diskTotal))
	print("Ino:", s.inode)
	print("Perms:", perms.toString(s.perms))
	print("Owner:", userdb.fromuid(s.uid, users).name)
	print("Group:", userdb.fromgid(s.gid, groups).name)
end
