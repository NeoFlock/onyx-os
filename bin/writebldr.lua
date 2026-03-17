--!lua

-- Write the bootloader

local luamin = require("luamin")

local f, forDev = ...
f = f or "/boot/init.lua"

local data = assert(readfile(f))
data = luamin(data) .. "\0"

---@type Kocos.partdev?
local bootPart
local bootAddr = io.todevice(forDev) or k.sysinfo().bootAddress

for addr in k.clist("partition", true) do
	---@type Kocos.partdev
	local dev = assert(k.cproxy(addr))
	if dev.getStorageDevice() == bootAddr and dev.getPartitionType() == "boot" then
		bootPart = dev
		break
	end
end

assert(bootPart, "unable to find partition")
assert(#data <= bootPart.getCapacity(), "insufficient storage")

local trueSize = math.align(#data, bootPart.getSectorSize())
data = string.rightpad(data, trueSize, '\0')
local ss = bootPart.getSectorSize()
local numSec = #data / ss

for i=0,numSec-1 do
	local chunk = data:sub(1 + i * ss, ss + i * ss)
	bootPart.writeSector(1 + i, chunk)
end
