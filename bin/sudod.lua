--!lua

local userdb = require("userdb")

---@param action string
k.registerDaemon("sudod", function(cpid, action, ...)
	if action == "chuser" then
		---@type string, string
		local user, password = ...
		local uinfo = userdb.getinfo(user)
		if not uinfo then return false, "auth failed" end
		if userdb.checkpass(user, password) then
			k.seteuid(uinfo.uid)
			k.setegid(uinfo.gid)
			return true
		end
		return false, "auth failed"
	end
end)

k.invokeDaemon("initd", "markComplete")

k.blockUntil(k.getpid(), function() return false end)
