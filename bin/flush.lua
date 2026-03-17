--!lua

local dev = ...
if dev then dev = io.todevice(dev) end

assert(k.flush(dev))
