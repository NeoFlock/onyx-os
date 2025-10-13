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

local toMake = {
	"/tmp",
	"/mnt",
	"/dev",
}

-- TODO: unmount tmpfs and mount a ramfs

for _, dir in ipairs(toMake) do
	assert(k.mkdir("/tmp" .. dir, 2^16-1))
end

assert(k.mountDev("/tmp/dev", "devfs"))

if k.exists("/tmp/bin") then
	os.executeBin("/bin/chroot.lua", {"/tmp"})
end
