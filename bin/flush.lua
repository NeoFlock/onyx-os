--!lua

local dev = ...
if dev then dev = k.caddress(dev) end

assert(k.flush(dev))
