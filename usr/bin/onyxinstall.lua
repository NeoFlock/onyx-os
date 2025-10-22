--!lua

---@type string
local device = ...

local perms = require("perms")
local readline = require("readline")

if not device then
	print("Usage: onyxinstall [device file]")
	return 1
end

print("Mounting device...")
local devAddr = k.ctype(k.caddress(device)) and k.caddress(device) or (k.stat(device).deviceAddress)
assert(k.mountDev("/mnt", devAddr))

local tmpAddr = k.sysinfo().tmpAddress
local devfsAddr = k.cprimary("devfs").address

print("Setting up basic filesystem...")
os.mkdir("/mnt/tmp", perms.everything)
os.mkdir("/mnt/dev", perms.everything)
os.mkdir("/mnt/boot", perms.everything)

assert(k.mountDev("/mnt/tmp", tmpAddr))
assert(k.mountDev("/mnt/dev", devfsAddr))

print("Setting up opk...")
os.executeSearchedBin("opk", {"--root", "/mnt", "strap"})

print("Installing kocos")
os.executeSearchedBin("opk", {"--root", "/mnt", "add", "vmkocos"})

print("Installing bootloader")
os.executeSearchedBin("opk", {"--root", "/mnt", "add", "onyx-boot"})

print("Installing core packages")
os.executeSearchedBin("opk", {"--root", "/mnt", "add", "luart", "opk", "coreutils", "onit", "ash"})

print("Setting up init system...")
os.touch("/mnt/sbin/init", perms.fromString("rwxr--r--"))
os.executeSearchedBin("chroot", {"/mnt", "chinit", "/sbin/onit.lua"})

print("Installing needed services...")
os.executeSearchedBin("opk", {"--root", "/mnt", "add", "initfs", "sudo", "internetd", "tunneld"})

print("Installing nice-to-have packages")
os.executeSearchedBin("opk", {"--root", "/mnt", "add", "minify", "fetch", "highlight", "unload", "wget", "strace", "forkbomb"})

---@param prompt string
---@param packages string[]
local function promptForPackages(prompt, packages)
	io.write(prompt, " [y/N] ")
	io.flush()
	local l = readline()
	if not l then return end
	if l:lower():sub(1, 1) ~= "y" then
		print("Skipping...")
		return
	end
	os.executeSearchedBin("opk", {"--root", "/mnt", "add", table.unpack(packages)})
end

promptForPackages("Install nicefs support?", {"mkfs-nicefs", "nicefsd"})

-- TODO: create users and stuff

print("Installation is done, you can chroot or chsysroot into the install medium, or just reboot.")
