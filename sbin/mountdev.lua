--!lua

local addr, path = ...

addr = assert(k.caddress(addr))

assert(k.mountDev(path, addr))
