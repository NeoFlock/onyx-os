--!lua

local bootAddr = ...

assert(k.chboot(assert(k.caddress(bootAddr))))
