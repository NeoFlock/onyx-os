-- For managed filesystems
local fs = computer.getBootAddress()

if component.invoke(fs, "exists", "installer.lua") then
	local inst = assert(component.invoke(fs, "open", "installer.lua"))
	local data = ""
	while true do
		local code, err = component.invoke(fs, "read", inst, math.huge)
		if err then error(err) end
		if not code then break end
		data = data .. code
	end
	component.invoke(fs, "close", inst)

	assert(load(data, "=installer.lua"))()
	error("installer halted")
end

local orbitCode = ""
local orbitF = assert(component.invoke(fs, "open", "boot/init.lua"))

while true do
	local code, err = component.invoke(fs, "read", orbitF, math.huge)
	if err then
		error(err)
	end
	if not code then break end
	orbitCode = orbitCode .. code
end

component.invoke(fs, "close", orbitF)

if #orbitCode > 0 then
	local f = assert(load(orbitCode, "=bootloader"))
	orbitCode = "" -- allow it to be GC'd
	f("boot")
end

error("orbit halted")
