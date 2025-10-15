--!lua

-- Log users in

local userdb = require("userdb")
local readline = require("readline")
local shutils = require("shutils")

local users = assert(userdb.parsePasswd())

---@param name string
---@return userdb.user?
local function getugids(name)
	for _, user in ipairs(users) do
		if user.name == name then
			return user
		end
	end
end

---@param name string
---@return boolean
local function tryLogin(name)
	if not userdb.checkpass(name, "", users) then
		k.write(1, "password: ")
		local pass = readline(nil, nil, "")
		if not pass then return false end
		if not userdb.checkpass(name, pass:sub(1, -2), users) then return false end
	end
	local uinfo = getugids(name)
	if not uinfo then return false end
	local pid = assert(k.fork(function()
		assert(k.setuid(uinfo.uid))
		assert(k.setgid(uinfo.gid))
		assert(k.seteuid(uinfo.uid))
		assert(k.setegid(uinfo.gid))
		assert(k.chdir(uinfo.home))
		local environ = table.copy(assert(k.environ()))
		environ.USER = uinfo.name
		environ.SHELL = uinfo.shell
		environ.PATH = shutils.defaultSearchPath(uinfo.name)
		environ.HOME = uinfo.home
		environ.USERINFO = uinfo.userInfo
		assert(k.exec(uinfo.shell, nil, environ))
	end))
	assert(k.waitpid(pid))
	return true
end

while true do
	k.write(1, "login: ")
	local name = readline()
	if not name then return end
	if not tryLogin(name:sub(1, -2)) then
		print("login failed")
		k.sleep(math.random() * 2.5 + 0.5)
	end
end
