--!lua

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
				-- user logging in as themselves means root!!
				-- TODO: check if they are in the wheel group
				assert(k.seteuid(0, cpid)) -- gid remains the same
			else
				assert(k.seteuid(uinfo.uid, cpid))
				assert(k.setegid(uinfo.gid, cpid))
			end
			return true
		end
		return false, "auth failed"
	end
end)

k.invokeDaemon("initd", "markComplete")

k.blockUntil(k.getpid(), function() return false end)
