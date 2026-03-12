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

local kernelCode = ""
local kernelF = assert(component.invoke(fs, "open", "boot/vmkocos"))
local segment = 0

while true do
	local code, err = component.invoke(fs, "read", kernelF, math.huge)
	if err then
		error(err)
	end
	if not code then break end
	kernelCode = kernelCode .. code
	while true do
		local segTerm, segTermEnd = string.find(kernelCode, "--[[KOCOS_SEGMENT]]", nil, true)
		if segTerm then
			segment = segment + 1
			local rawCode = string.sub(kernelCode, 1, segTerm-1)
			local f = assert(load(rawCode, "=kocos_seg" .. segment))
			f()
			kernelCode = string.sub(kernelCode, segTermEnd+1)
		else
			break
		end
	end
end

component.invoke(fs, "close", kernelF)

if #kernelCode > 0 then
	local f = assert(load(kernelCode, "=kocos"))
	kernelCode = "" -- allow it to be GC'd
	f()
end

error("kernel halted")
