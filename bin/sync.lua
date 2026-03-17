--!lua

local dev = ...
if dev then dev = io.todevice(dev) end

assert(k.sync(dev))
