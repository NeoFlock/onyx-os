local fs = computer.getBootAddress()

-- Taken from the Konsole theme of the same name
local scratchy = {
	[30] = 0x24273A,
	[31] = 0xED8796,
	[32] = 0xA6DA95,
	[33] = 0xEED49F,
	[34] = 0x8AADF4,
	[35] = 0xF5BDE6,
	[36] = 0x8BD5CA,
	[37] = 0xCAD3F5,
	[90] = 0x1F2232,
	[91] = 0xE48290,
	[92] = 0x9FD18F,
	[93] = 0xE1C896,
	[94] = 0x84A8EA,
	[95] = 0xE9B4DC,
	[96] = 0x83C9BE,
	[97] = 0xC2CBEB,
}

---@type Kocos.config
local kargs = {
	termStdColors = scratchy,
}

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
