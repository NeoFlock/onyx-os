--!lua

---@type string
local device = ...

local perms = require("perms")
local readline = require("readline")
local userdb = require("userdb")

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
os.mkdir("/mnt/home", perms.everything)

assert(k.mountDev("/mnt/tmp", tmpAddr))
assert(k.mountDev("/mnt/dev", devfsAddr))

print("Setting up opk...")
os.executeSearchedBin("opk", {"--root", "/mnt", "strap"})

print("Installing kocos")
os.executeSearchedBin("opk", {"--root", "/mnt", "add", "vmkocos"})

print("Installing bootloader")
os.executeSearchedBin("opk", {"--root", "/mnt", "add", "onyx-boot"})

print("Installing core packages")
os.executeSearchedBin("opk", {"--root", "/mnt", "add", "luart", "opk", "coreutils", "onit", "ash", "login"})

print("Setting up init system...")
os.touch("/mnt/sbin/init", perms.fromString("rwxr--r--"))
os.executeSearchedBin("chroot", {"/mnt", "chinit", "/sbin/onit.lua"})

print("Installing needed services...")
os.executeSearchedBin("opk", {"--root", "/mnt", "add", "initfs", "sudo", "internetd", "tunneld"})

print("Installing nice-to-have packages")
os.executeSearchedBin("opk", {"--root", "/mnt", "add", "minify", "fetch", "highlight", "unload", "wget", "strace", "forkbomb", "onyx-install"})

local function yesOrNo()
	local l = readline()
	if not l then return end
	if l:lower():sub(1, 1) ~= "y" then
		return false
	end
	return true
end

---@param prompt string
---@param packages string[]
local function promptForPackages(prompt, packages)
	io.write(prompt, " [y/N] ")
	io.flush()
	if not yesOrNo() then
		print("Skipping...")
		return
	end
	os.executeSearchedBin("opk", {"--root", "/mnt", "add", table.unpack(packages)})
end

promptForPackages("Install nicefs support?", {"mkfs-nicefs", "nicefsd"})

-- TODO: create users and stuff

print("Beginning user setup")

---@type string
local rootPassword

repeat
	io.write("Root password: ")
	io.flush()
	local firstAttempt = readline()
	io.write("Retype password: ")
	io.flush()
	local secondAttempt = readline()
	if firstAttempt == secondAttempt then
		rootPassword = (firstAttempt or ""):sub(1, -2)
	end
until rootPassword

---@type userdb.user[]
local users = {
	{
		name = "root",
		uid = 0,
		gid = 0,
		home = "/root",
		password = "=" .. rootPassword,
		shell = "/bin/ash.lua",
		userInfo = "Root user",
	},
}

---@type userdb.group[]
local groups = {
	{
		name = "root",
		gid = 0,
		users = {"root"},
		passphrase = "",
	},
	{
		name = "default",
		gid = 1,
		users = {},
		passphrase = "",
	},
	{
		name = "wheel",
		gid = 3,
		users = {"root"},
		passphrase = "",
	},
}

local wheelGroup = groups[3]

io.write("Add guest user? [y/N] ")
io.flush()
if yesOrNo() then
	users[2] = {
		name = "guest",
		uid = 1,
		gid = 2,
		home = "/home",
		password = "",
		shell = "/bin/ash.lua",
		userInfo = "Guest user",
	}
	groups[4] = {
		name = "guest",
		gid = 2,
		users = {"guest"},
		passphrase = "",
	}
end

print("Adding more users")
local uid = 100

while true do
	print("Ctrl-D to stop adding users. You currently have", #users, "users.")
	io.write("Name: ")
	io.flush()
	local name = readline()
	if not name then break end
	name = name:sub(1, -2)
	io.write("Display Name: ")
	io.flush()
	local display = readline()
	if not display then break end
	display = display:sub(1, -2)
	---@type string
	local password
	repeat
		io.write("Password: ")
		io.flush()
		local attempt1 = readline()
		io.write("Retype: ")
		io.flush()
		local attempt2 = readline()
		if attempt1 == attempt2 then
			password = (attempt1 or ""):sub(1, -2)
			break
		end
	until password
	io.write("Can use sudo? [y/N] ")
	io.flush()
	users[#users+1] = {
		name = name,
		uid = uid,
		gid = 1,
		password = "=" .. password,
		userInfo = display,
		shell = "/bin/ash.lua",
		home = "/home/" .. name,
	}
	os.touch("/mnt/home/" .. name, perms.everything)
	if yesOrNo() then
		table.insert(wheelGroup.users, name)
	end
end

os.touch("/mnt/etc/passwd", perms.fromString("rwxr--r--"))
os.touch("/mnt/etc/group", perms.fromString("rwxr--r--"))
os.touch("/mnt/etc/shadow", perms.fromString("rwxr--r--"))
userdb.writePasswd(users, "/mnt/etc/passwd")
userdb.writeGroup(groups, "/mnt/etc/group")

print("Setting up repositories")
---@type string[]
local repos = {
	"onyx https://raw.githubusercontent.com/NeoFlock/onyx-os/refs/heads/main",
	"media /media ?",
}

assert(writefile("/mnt/etc/opk/repositories", table.concat(repos, "\n") .. "\n"))

print("Installation is done, you can chroot or chsysroot into the install medium, or just reboot.")
