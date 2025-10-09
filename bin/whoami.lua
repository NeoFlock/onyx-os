--!lua

local userdb = require("userdb")

local uid = assert(k.geteuid())
local users = assert(userdb.parsePasswd())

for _, user in ipairs(users) do
	if user.uid == uid then
		print(user.name)
		return
	end
end

print("Unknown EUID. This is a horrible state to be in.")
