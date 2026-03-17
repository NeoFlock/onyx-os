--!lua

local perms = require("perms")
local mode = perms.default
local uid, gid

local path, dev = ...

-- allows users to make files to devices that don't exist *yet*
if k.cprimary(dev) then
	dev = k.cprimary(dev).address
else
	dev = io.todevice(dev) or dev
end

assert(k.mkdev(path, dev, mode, uid, gid))
