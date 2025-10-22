#!/usr/bin/env lua
---@diagnostic disable: lowercase-global
-- Build script

-- Stuff thrown in here so LSP will sybau
if 1<0 then
	---@param n integer
	---@param v any
	---@vararg type
	function checkArg(n, v, ...) end
end

if not os.exec then
	-- on actual Lua
	package.path = package.path .. ";usr/lib/?.lua"
end

require("usr.src.kocos.utils")

local toBuild = {
	"onyx",
}

local args={...}

if #args > 0 then
	toBuild = {}
	for i=1,#args do
		table.insert(toBuild, args[i])
	end
end

local built = {}

local buildInfo = {
	onyx = {
		type = "none",
		deps = {
			"kocos", -- need the kernel, obviously
		},
	},
	kocos = {
		type = "cat",
		luamin = true,
		files = {
			"usr/src/kocos/bootstrap.lua",
			"usr/src/kocos/utils.lua",
			"usr/src/kocos/event.lua",
			"usr/src/kocos/component.lua",
			"usr/src/kocos/printk.lua",
			"usr/src/kocos/errno.lua",
			"usr/src/kocos/drivers.lua",
			"usr/src/kocos/debugger.lua",
			"usr/src/kocos/ramfs.lua",
			"usr/src/kocos/fs.lua",
			"usr/src/kocos/devfs.lua",
			"usr/src/kocos/process.lua",
			"usr/src/kocos/require.lua",
			"usr/src/kocos/exec.lua",
			"usr/src/kocos/net.lua",
			"usr/src/kocos/syscalls.lua",
			"usr/src/kocos/boot.lua",
		},
		out = "boot/vmkocos",
		deps = {},
	},
}

---@param src string
---@return string
local function luamin(src)
	local l = require("luamin")
	return l(src)
end

local function runBuild(thing)
	if built[thing] then return end
	built[thing] = true
	local entry = buildInfo[thing]

	if entry.deps then
		for _, dep in ipairs(entry.deps) do runBuild(dep) end
	end

	print("Building", thing)

	if entry.type == "cat" then
		-- Directly merge files
		local outcode = ""
		for _, file in ipairs(entry.files) do
			print("Reading", file)
			local f = assert(io.open(file, "rb"))
			outcode = outcode .. assert(f:read("a"), "no code")
			f:close()
		end
		if entry.luamin then
			outcode = luamin(outcode)
		end
		local f = assert(io.open(entry.out, "wb"))
		f:write(outcode)
		f:flush()
		f:close()
	end
end

for i=1,#toBuild do
	runBuild(toBuild[i])
end
