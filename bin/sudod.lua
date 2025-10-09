--!lua

local userdb = require("userdb")

---@param action string
k.registerDaemon("sudod", function(cpid, action, ...)
	if action == "checkUser" then

	end
end)

k.invokeDaemon("initd", "markComplete")
