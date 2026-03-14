--!lua

local perms = require("perms")
local userdb = require("userdb")

local users = assert(userdb.parsePasswd())
local groups = assert(userdb.parseGroup())

local paths = {...}

for _, path in ipairs(paths) do
	local s = assert(k.stat(path))
	print(path)
	local addr = s.deviceAddress
	if k.ctype(addr) then addr = addr .. " (" .. k.ctype(addr) .. ")" end
	print("Type:", s.type)
	print("Dev:", addr)
	print("Size:", string.memformat(s.size))
	print("Last Modified:", os.date("%x %X", math.floor(s.lastModified / 1000)))
	print("Size On Disk:", string.memformat(s.diskSize))
	print("Disk Used:", string.memformat(s.diskUsed))
	print("Disk Total:", string.memformat(s.diskTotal))
	print("Ino:", s.inode)
	print("Link count:", s.linkCount)
	print("Perms:", perms.toString(s.perms))
	print("Owner:", userdb.fromuid(s.uid, users).name)
	print("Group:", userdb.fromgid(s.gid, groups).name)
end
