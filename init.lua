local fs = computer.getBootAddress()

---@type Kocos.config
local kargs = {}

kargs.debugger = component.list("ocelot")()

if kargs.debugger then
	component.invoke(kargs.debugger, "clearLog")
	component.invoke(kargs.debugger, "log", "Selected as KGDB")
end

local kernelCode = ""
local kernelF = assert(component.invoke(fs, "open", "kernel"))

while true do
	local code, err = component.invoke(fs, "read", kernelF, math.huge)
	if err then
		error(err)
	end
	if not code then break end
	kernelCode = kernelCode .. code
end

_OSVERSION = "ONYX v0.0.1"

local f = assert(load(kernelCode, "=kocos"))
kernelCode = nil -- allow it to be GC'd
f("kocos", kargs)
