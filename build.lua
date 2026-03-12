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
	require("usr.src.kocos.utils")
end

local kar = require("kar")

local function perms3(str)
	local n = 0
	if str:sub(1,1) == "r" then n = n + 4 end
	if str:sub(2,2) == "w" then n = n + 2 end
	if str:sub(3,3) == "x" then n = n + 1 end
	return n
end

local function perms(str)
	return perms3(str) * 64 + perms3(str:sub(4)) * 8 + perms3(str:sub(7))
end

local readWholeFile = readfile or function(path)
	local f = assert(io.open(path, "rb"))
	local data = tostring(f:read("a"))
	f:close()
	return data
end

---@param path string
---@return string
local function permsOf(path)
	if path == "sbin" then return "rwxr-xr-x" end
	if string.startswith(path, "sbin/") then return "rwxr-xr-x" end
	if path == "bin" then return "rwxr-xr-x" end
	if string.startswith(path, "bin/") then return "rwxr-xr-x" end
	if path == "lib" then return "rwxr-xr-x" end
	if string.startswith(path, "lib/") then return "rwxr-xr-x" end
	if path == "root" then return "rwxr-xr-x" end
	if path == "etc/onit.conf" then return "rwxr-xr-x" end
	if path == "etc/passwd" then return "rw-r--r--" end
	if path == "etc/group" then return "rw-r--r--" end
	if path == "etc/shadow" then return "rw-------" end
	if path == "etc/fstab" then return "rw-r--r--" end
	if path == "home/helloWorld.lua" then return "rwxrwxrwx" end
	if path == "etc/onit.d" then return "rw-r--r--" end
	if string.startswith(path, "etc/onit.d/") then return "rw-r--r--" end
	if path == "usr/bin" then return "rwxr-xr-x" end
	if string.startswith(path, "usr/bin/") then return "rwxr-xr-x" end
	if path == "usr/lib" then return "rwxr-xr-x" end
	if string.startswith(path, "usr/lib/") then return "rwxr-xr-x" end
	if path == "boot" then return "rwxr-xr-x" end
	if path == "init.lua" then return "rwxr-xr-x" end
	if string.startswith(path, "boot/") then return "rwxr-xr-x" end
	return "rw-rw-rw-"
end

local function list(path)
	if io.list then
		local l = assert(io.list(path))
		for i=1,#l do
			l[i] = l[i]:gsub("/", "")
		end
		return l
	end
	local lfs = require("lfs")
	local t = {}
	for e in lfs.dir(path) do
		table.insert(t, e)
	end
	return t
end

local ftype = io.ftype or function(path)
	local lfs = require("lfs")
	return lfs.attributes(path, 'mode') == 'directory' and 'directory' or 'regular'
end

local forbidden = {
	".kocos",
	".git",
	".gitkeep",
	".",
	"..",
	".kocos",
	".gitignore",
	"run_ocelot.sh",
	"build.lua",
	"README.md",
	"TODO.md",
	"docs",
	-- prevent recursion
	"ramfs.tar",
	"ramfs.kar",
	"installer.lua",
}

local badpaths = {"dev", "proc", "sys", "tmp", "usr/src"}

---@return string[]
local function recursiveFiles()
	local files = {}

	local function scanDir(path)
		if path:sub(-1, -1) == "/" then path = path:sub(1, -2) end
		if table.contains(badpaths, path) then return {} end
		local entries = assert(list(path))
		for _, entry in ipairs(entries) do
			if not table.contains(forbidden, entry) then
				local fullpath = path .. "/" .. entry
				table.insert(files, fullpath)
				if ftype(fullpath) == "directory" then
					scanDir(fullpath)
				end
			end
		end
	end

	local root = assert(list("."))
	for _, entry in ipairs(root) do
		if not table.contains(forbidden, entry) then
			table.insert(files, entry)
			if ftype(entry) == "directory" then
				scanDir(entry)
			end
		end
	end
	return files
end

local function karRecs()
	---@type kar.record[]
	local recs = {}

	---@param path string
	---@param name string
	local function makeRecord(path, name)
		---@type kar.record
		local rec = {
			name = name,
			type = assert(ftype(path)),
			perms = perms(permsOf(path)),
			uid = 0,
			gid = 0,
			mtime = 0,
		}
		if rec.type == "regular" then
			rec.data = readWholeFile(path)
		elseif rec.type == "directory" then
			if path:sub(-1, -1) == "/" then path = path:sub(1, -2) end
			rec.entries = {}
			if not table.contains(badpaths, path) then
				for _, ent in ipairs(assert(list(path))) do
					if not table.contains(forbidden, ent) then
						table.insert(rec.entries, makeRecord(path .. "/" .. ent, ent))
					end
				end
			end
		end
		return rec
	end

	local root = assert(list("."))
	for _, entry in ipairs(root) do
		if not table.contains(forbidden, entry) then
			table.insert(recs, makeRecord(entry, entry))
		end
	end
	return recs
end

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

local kernel = os.getenv("ONYX_KERNEL") or "kocos"

local buildInfo = {
	onyx = {
		type = "none",
		deps = {
			"kocos_metadata",
			kernel, -- need the kernel, obviously
		},
	},
	kocos_metadata = {
		type = "buildmeta",
	},
	kocos = {
		type = "cat",
		luamin = os.getenv("ONYX_MIN") ~= nil,
		segment = os.getenv("ONYX_SEGMENT") ~= nil,
		files = {
			"usr/src/kocos/utils.lua",
			"usr/src/kocos/init.lua",
			"usr/src/kocos/event.lua",
			"usr/src/kocos/component.lua",
			"usr/src/kocos/errno.lua",
			"usr/src/kocos/modules.lua",
			"usr/src/kocos/process.lua",
			"usr/src/kocos/ramfs.lua",
			"usr/src/kocos/fs.lua",
			"usr/src/kocos/net.lua",
			"usr/src/kocos/boot.lua",
		},
		out = "boot/vmkocos",
		deps = {},
	},
	installer = {
		type = "ramfs-inst",
		deps = {"onyx"},
	},
}

---@return string, string
local function makeRamFS()
	local kernelCode = assert(readWholeFile("boot/vmkocos"))
	local records = karRecs()
	return kar.encode(records), kernelCode
end

---@param src string
---@return string
local function luamin(src)
	if os.getenv("ONYX_NOMIN") then return src end
	local l = require("luamin")
	return l(src)
end

local function runBuild(thing)
	if built[thing] then return end
	built[thing] = true
	local entry = buildInfo[thing]
	assert(entry, "unknown build step: " .. thing)

	if entry.deps then
		for _, dep in ipairs(entry.deps) do runBuild(dep) end
	end

	print("Building", thing)

	if entry.type == "cat" then
		-- Directly merge files
		local outcode = ""
		for _, file in ipairs(entry.files) do
			if file ~= "" then
				print("Reading", file)
				local fcode = readWholeFile(file)
				if entry.luamin then
					fcode = luamin(fcode)
				end
				if entry.segment then
					fcode = fcode .. "--[[KOCOS_SEGMENT]]"
				end
				if fcode:sub(-1, -1) ~= " " then fcode = fcode .. " " end
				outcode = outcode .. fcode
			end
		end
		local f = assert(io.open(entry.out, "wb"))
		f:write(outcode)
		f:flush()
		f:close()
	elseif entry.type == "buildmeta" then
		local everything = recursiveFiles()
		-- Kocos Metadata 1
		local lines = {
			"KMETA 1",
			"PATH FTYPE OWNER GROUP PERMS",
		}

		for _, path in ipairs(everything) do
			local p = perms(permsOf(path))
			print("writing metadata for " .. path .. "...")
			table.insert(lines, string.format("%s %s 0 0 %d", path, ftype(path), p))
		end


		local f = assert(io.open(".kocos", "wb"))
		f:write(table.concat(lines, "\n"))
		f:flush()
		f:close()
	elseif entry.type == "ramfs-inst" then

		local ramimg, kernelCode = makeRamFS()

		local f = assert(io.open("ramfs.kar", "wb"))
		f:write(ramimg)
		f:flush()
		f:close()

		local koff = assert(string.find(ramimg, kernelCode, nil, true), "missing kernel")

		local inst = string.format("local ramfs=%q local kernel=string.sub(ramfs, %d, %d) return assert(load(kernel,'=kocos'))('kocos','',ramfs)", ramimg, koff, koff+#kernelCode-1)

		f = assert(io.open("installer.lua", "wb"))
		f:write(inst)
		f:flush()
		f:close()
	end
end

for i=1,#toBuild do
	runBuild(toBuild[i])
end
