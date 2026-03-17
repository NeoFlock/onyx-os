--!lua

local devutils = require("devutils")
local perms = require("perms")

local mnts = k.getMounts()

local typemap = {
	partition = "part",
	tape_drive = "tape",
	drive = "disk",
	filesystem = "disk",
}

for addr, type in pairs(assert(k.clist())) do
	local path = devutils.pathToDev(addr)
	local ty = typemap[type]
	if ty and path then
		local stat = assert(k.stat(path))
		local sizeStr = string.memformat(stat.size)
		local ro = string.find(perms.toString(stat.perms), "w") == nil

		print(path, ty, sizeStr, ro and "ro" or "rw", mnts[addr] or "")
	end
end
