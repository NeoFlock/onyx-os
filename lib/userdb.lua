-- Module for loading and storing data in /etc/passwd, /etc/shadow and /etc/group

---@class userdb.user
---@field name string
--- Empty means unsecured, x means stored in /etc/shadow. Programs are free to process other variants as they wish.
---@field password string
---@field uid integer
---@field gid integer
---@field userInfo string
---@field home string
---@field shell string

---@class userdb.group
---@field name string
---@field passphrase string
---@field gid integer
---@field users string[]

---@class userdb.shadow
---@field name string
---@field password string
--- In *days* since UNIX epoch
---@field lastPassChange integer
--- In days
---@field minimumBetweenChanges integer
--- In days, how long until user must change passwords
---@field passwordLifespan integer
--- In days, how long until the user should be warned that their password may expire
---@field warn integer
--- In days, how long until the account is disabled due to password being too old
---@field inactive integer
--- In *days* since UNIX epoch, how long until the account is permanently disabled.
---@field expire integer

local userdb = {}

---@param file? string
---@return userdb.user[]?, string?
function userdb.parsePasswd(file)
	local data, err1 = readfile(file or "/etc/passwd")
	if not data then return nil, err1 end

	---@type userdb.user[]
	local users = {}
	local lines = string.split(data, "\n")
	for _, line in ipairs(lines) do
		if #line > 0 then
			local cols = string.split(line, ":")
			if #cols ~= 7 then return nil, "format error" end
			local uid, gid = tonumber(cols[3]), tonumber(cols[4])
			if not uid then
				return nil, "bad UID"
			end
			if not gid then
				return nil, "bad GID"
			end
			---@type userdb.user
			local user = {
				name = cols[1],
				password = cols[2],
				uid = uid,
				gid = gid,
				userInfo = cols[5],
				home = cols[6],
				shell = cols[7],
			}
			table.insert(users, user)
		end
	end
	return users
end

---@param users userdb.user[]
---@param file? string
function userdb.writePasswd(users, file)
	local lines = {}
	for _, user in ipairs(users) do
		table.insert(lines, string.format("%s:%s:%d:%d:%s:%s:%s", user.name, user.password, user.uid, user.gid, user.home, user.shell))
	end
	return writefile(file or "/etc/passwd", table.concat(lines, "\n") .. "\n")
end

return userdb
