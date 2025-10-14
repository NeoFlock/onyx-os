--!lua

-- TODO: implement fully

local arg = ...

local ramfs = require("ramfs")

local importantFiles = {
	"/bin",
	"/boot",
	"/etc",
	"/home",
	"/lib",
	"/root",
	"/usr",
	-- bootloader may not always be available at this path!!!!!!
	"/init.lua",
}

---@type Kocos.ramfs.node
local img = {
	items = {},
}

for _, file in ipairs(importantFiles) do
	print("Loading " .. file .. " into RAM...")
	img.items[file:sub(2)] = ramfs.readTree(file)
end

print("Generating ramfs component...")
local fs = assert(k.cramfs(img, "mktmproot", false))
print("Unmounting tmp...")
k.unmount"/tmp"
print("Mounting ramfs...")
assert(k.mountDev("/tmp", fs))

local toMake = {
	"/tmp",
	"/mnt",
	"/media",
	"/dev",
}

print("Fixing ramfs...")
for _, dir in ipairs(toMake) do
	assert(k.mkdir("/tmp" .. dir, 2^16-1))
end

assert(k.mountDev("/tmp/dev", "devfs"))

if arg == "-g" then
	assert(k.chsysroot(fs))
else
	if k.exists("/tmp/bin") then
		os.executeBin("/bin/chroot.lua", {"/tmp"})
	end
end
