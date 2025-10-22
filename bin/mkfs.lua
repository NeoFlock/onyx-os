--!lua
-- Call the correct mkfs utility

local args = {...}
local shutils = require("shutils")

-- This is basically the "default" filesystem
local fsType = os.getenv("MKFS_DEFAULT_FS") or "nicefs"

if args[1] == "-h" or args[1] == "--help" or not args[1] then
	print("mkfs [-t <type>] [options] <device>")
	print("Make a filesystem. Current default FS (set by MKFS_DEFAULT_FS) is", fsType)
	return 0
end

if args[1] == "-t" then
	table.remove(args, 1)
	fsType = table.remove(args, 1)
end

local bin = shutils.search("mkfs." .. fsType)
if not bin then
	print("Unsupported filesystem:", fsType)
	return 1
end

assert(os.exec(bin, args))
