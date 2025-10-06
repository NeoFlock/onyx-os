--!lua

local info = k.sysinfo()

print("total", info.memtotal)
print("used", info.memtotal - info.memfree)
print("free", info.memfree)
