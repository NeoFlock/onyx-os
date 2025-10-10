-- Utilies for things that do shell-like operations

local userdb = require("userdb")

local shutils = {}

function shutils.getWorkingDirectory()
	return assert(k.chdir("."))
end

function shutils.getUser()
	local uid = k.geteuid()
	local users = assert(userdb.parsePasswd())
	for _, user in ipairs(users) do
		if user.uid == uid then return user.name end
	end
end

function shutils.getHostname()
	return k.hostname()
end

---@param path string
function shutils.printablePath(path)
	local home = userdb.getHome(shutils.getUser())

	if path == home then return "~" end
	if string.startswith(path, home .. "/") then
		return "~" .. path:sub(#home+1)
	end
	return path
end

---@param user? string
function shutils.defaultSearchPath(user)
	local sys = "/usr/local/bin:/usr/bin:/bin:/tmp/bin:/mnt/bin"
	if user then
		sys = "/home/" .. user .. "/bin:" .. sys
	end
	return sys
end

---@param cmd string
---@param exts? string[]
---@param path? string
---@return string?
function shutils.search(cmd, exts, path)
	path = path or k.environ().PATH or shutils.defaultSearchPath(shutils.getUser())
	exts = exts or {'', '.lua', '.kelf', '.sh', '.cmd', '.bat'}

	local dirs = string.split(path, ":")

	for _, ext in ipairs(exts) do
		local p = cmd .. ext
		if k.exists(p) then return p end
	end

	for _, dir in ipairs(dirs) do
		for _, ext in ipairs(exts) do
			local p = dir .. "/" .. cmd .. ext
			if k.exists(p) then return p end
		end
	end
end

return shutils
