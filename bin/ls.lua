--!lua

local path = ...

path = path or "."

local terminal = require("terminal")
local errno = require("errnos")

local d = assert(k.list(path))

local dirColor = "\x1b[34m"
local linkColor = "\x1b[31m"
local devColor = "\x1b[33m"
local mntColor = "\x1b[32m"
local exeColor = "\x1b[92m"

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
		local p = k.join(path, f)
		local s = assert(k.stat(p))
		local big3 = s.perms | (s.perms >> 3) | (s.perms >> 6)
		local ff = fixedD[i] or f
		if k.isMount(p) then
			d[i] = mntColor .. ff .. "\x1b[0m"
		elseif s.type == "directory" then
			d[i] = dirColor .. ff .. "\x1b[0m"
		elseif s.type == "symlink" then
			d[i] = linkColor .. ff .. "\x1b[0m"
		elseif s.type ~= "regular" then
			d[i] = devColor .. ff .. "\x1b[0m"
		elseif big3 & 1 ~= 0 then
			d[i] = exeColor .. ff .. "\x1b[0m"
		else
			d[i] = ff
		end
	end
end

for i=1,#d, maxPerLine do
	local l = table.concat(d, " ", i, math.min(i+maxPerLine-1, #d))
	print(l)
end
