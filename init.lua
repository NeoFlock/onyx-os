local fs = computer.getBootAddress()

---@type Kocos.config
local kargs = {}

kargs.debugger = component.list("ocelot")()

if kargs.debugger then
	component.invoke(kargs.debugger, "log", "Selected as KGDB")
end

local kernelCode = {}
local kernelF = assert(component.invoke(fs, "open", "boot/vmkocos"))

while true do
	local code, err = component.invoke(fs, "read", kernelF, math.huge)
	if err then
		error(err)
	end
	if not code then break end
	table.insert(kernelCode, code)
end

local f = assert(load(function()
	return table.remove(kernelCode, 1)
end, "=kocos"))
kernelCode = nil -- allow it to be GC'd
f("kocos", kargs)
