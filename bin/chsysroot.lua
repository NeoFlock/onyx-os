--!lua

local rootAddr = ...
assert(rootAddr, "no device specified")
rootAddr = assert(io.todevice(rootAddr))

assert(k.umount("/"))
assert(k.mount("/", rootAddr))
