--!lua

local errnos = require("errnos")

---@param action string
k.registerDaemon("sudod", function(cpid, action, ...)
	local userdb = require("userdb")
	if action == "chuser" then
		---@type string, string
		local user, password = ...
		local uinfo = userdb.getinfo(user)
		if not uinfo then return false, "auth failed" end
		if userdb.checkpass(user, password) then
			local pinfo = assert(k.getprocinfo(cpid, "uid"))
			if pinfo.uid == uinfo.uid then
				local wheel = userdb.getgroup("wheel")
				if not wheel then return false, "missing wheel group" end
				if not table.contains(wheel.users, user) then return false, errnos.EACCESS end
				-- user logging in as themselves means root!!
				-- TODO: check if they are in the wheel group
				assert(k.setuid(0, cpid)) -- gid remains the same
			else
				assert(k.setuid(uinfo.uid, cpid))
				assert(k.setgid(uinfo.gid, cpid))
			end
			return true
		end
		return false, "auth failed"
	end
end)

k.invokeDaemon("initd", "markComplete")

k.kill(k.getpid(), "SIGSTOP")
coroutine.yield()
