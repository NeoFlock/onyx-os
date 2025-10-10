--!lua

local path = ...

path = path or "."

local d = assert(k.list(path))

local dirColor = "\x1b[34m"
local mountColor = "\x1b[33m"
local exeColor = "\x1b[92m"
local dataColor = "\x1b[36m"
local kernelColor = "\x1b[31m"

local colorsForExts = {
	[".lua"] = exeColor,
	[".md"] = dataColor,
	[".json"] = dataColor,
	[".gitignore"] = dataColor,
	[".lon"] = dataColor,
}

for i, f in ipairs(d) do
	local t = k.ftype(k.join(path, f))
	if t == "directory" then
		d[i] = dirColor .. f .. "\x1b[0m"
	elseif t == "mount" then
		d[i] = mountColor .. f .. "\x1b[0m"
	elseif f == "kernel" then
		d[i] = kernelColor .. f .. "\x1b[0m"
	elseif f == "LICENSE" then
		d[i] = dataColor .. f .. "\x1b[0m"
	elseif f == "Makefile" then
		d[i] = dataColor .. f .. "\x1b[0m"
	else
		for e, c in pairs(colorsForExts) do
			if string.endswith(f, e) then
				d[i] = c .. f .. "\x1b[0m"
			end
		end
	end
end

print(table.concat(d, " "))
