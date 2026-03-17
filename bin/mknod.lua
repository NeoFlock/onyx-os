--!lua

-- Wraps the mknod syscall,
-- quite different from POSIX mknod

local perms = require("perms")
local mode = perms.default
local uid, gid

local path, ty = ...

assert(k.mknod(path, ty, mode, uid, gid))
