--!lua

local path = ...

path = path or "."

local terminal = require("terminal")

local d = assert(k.list(path))

local dirColor = "\x1b[34m"
local mountColor = "\x1b[33m"
local exeColor = "\x1b[92m"
local dataColor = "\x1b[35m"
local devColor = "\x1b[36m"
local kernelColor = "\x1b[31m"

local colorsForExts = {
	[".lua"] = exeColor,
	[".md"] = dataColor,
	[".json"] = dataColor,
	[".gitignore"] = dataColor,
	[".lon"] = dataColor,
}

local fixedD = {}

-- get resolution
local maxPerLine = 1
if terminal.isatty(terminal.STDTERM) then
	local width = terminal.stdterm():getResolution()
	local biggest = 0
	for _, f in ipairs(d) do
		biggest = math.max(biggest, #f)
	end
	for i, f in ipairs(d) do
		fixedD[i] = string.rightpad(f, biggest)
	end
	if biggest > 0 then
		maxPerLine = math.max(math.floor(width / (biggest+1)), 1)
	end
end

-- apply colorization if TTY
if terminal.isatty(terminal.STDOUT) then
	for i, f in ipairs(d) do
		local t = k.ftype(k.join(path, f))
		local ff = fixedD[i] or f
		if t == "directory" then
			d[i] = dirColor .. ff .. "\x1b[0m"
		elseif t == "mount" then
			d[i] = mountColor .. ff .. "\x1b[0m"
		elseif t == "blockdev" then
			d[i] = devColor .. ff .. "\x1b[0m"
		elseif t == "chardev" then
			d[i] = devColor .. ff .. "\x1b[0m"
		elseif f == "kernel" then
			d[i] = kernelColor .. ff .. "\x1b[0m"
		elseif f == "LICENSE" then
			d[i] = dataColor .. ff .. "\x1b[0m"
		elseif f == "Makefile" then
			d[i] = dataColor .. ff .. "\x1b[0m"
		else
			for e, c in pairs(colorsForExts) do
				if string.endswith(f, e) then
					d[i] = c .. ff .. "\x1b[0m"
				end
			end
		end
	end
end

for i=1,#d, maxPerLine do
	local l = table.concat(d, " ", i, math.min(i+maxPerLine-1, #d))
	print(l)
end
