--!lua

-- TODO: implement fully

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
local ramfs = {
	items = {
		textfile = {
			fileData = "sick file bro",
		},
	},
}

k.unmount"/tmp"
local fs = assert(k.cramfs(ramfs, "mktmproot", false))
assert(k.mountDev("/tmp", fs))

local toMake = {
	"/tmp",
	"/mnt",
	"/media",
	"/dev",
}

for _, dir in ipairs(toMake) do
	assert(k.mkdir("/tmp" .. dir, 2^16-1))
end

assert(k.mountDev("/tmp/dev", "devfs"))

if k.exists("/tmp/bin") then
	os.executeBin("/bin/chroot.lua", {"/tmp"})
end
