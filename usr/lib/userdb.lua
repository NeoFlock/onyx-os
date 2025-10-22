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

---@param file? string
---@return userdb.group[]?, string?
function userdb.parseGroup(file)
	local data, err1 = readfile(file or "/etc/group")
	if not data then return nil, err1 end

	---@type userdb.group[]
	local groups = {}
	local lines = string.split(data, "\n")
	for _, line in ipairs(lines) do
		if #line > 0 then
			local cols = string.split(line, ":")
			if #cols ~= 4 then return nil, "format error" end
			local gid = tonumber(cols[3])
			if not gid then
				return nil, "bad GID"
			end
			---@type userdb.group
			local group = {
				name = cols[1],
				passphrase = cols[2],
				gid = gid,
				users = string.split(cols[4], ","),

			}
			table.insert(groups, group)
		end
	end
	return groups
end

---@param users userdb.user[]
---@param file? string
function userdb.writePasswd(users, file)
	local lines = {}
	for _, user in ipairs(users) do
		table.insert(lines, string.format("%s:%s:%d:%d:%s:%s:%s", user.name, user.password, user.uid, user.gid, user.userInfo, user.home, user.shell))
	end
	return writefile(file or "/etc/passwd", table.concat(lines, "\n") .. "\n")
end

---@param groups userdb.group[]
---@param file? string
function userdb.writeGroup(groups, file)
	local lines = {}
	for _, group in ipairs(groups) do
		table.insert(lines, string.format("%s:%s:%d:%s", group.name, group.passphrase, group.gid, table.concat(group.users, ",")))
	end
	return writefile(file or "/etc/group", table.concat(lines, "\n") .. "\n")
end

---@param hash string
---@param pass string
---@return boolean
function userdb.checkpasshash(hash, pass)
	if hash == "" then return true end
	if hash:sub(1,1) == "=" then
		return hash:sub(2) == pass
	end
	return true
end

---@param user string
---@param users? userdb.user[]
function userdb.getinfo(user, users)
	users = users or (userdb.parsePasswd() or {})
	for _, u in ipairs(users) do
		if u.name == user then return u end
	end
end

---@param user string
---@param users? userdb.user[]
function userdb.getShell(user, users)
	local info = userdb.getinfo(user, users)
	if not info then return "/bin/sh" end
	return info.shell
end

---@param user string
---@param users? userdb.user[]
function userdb.getHome(user, users)
	local info = userdb.getinfo(user, users)
	if not info then return "/home" end
	return info.home
end

-- Compute a checkpasshash-compatible hash for the password
---@param pass string
---@return string
function userdb.hashpassword(pass)
	if pass == "" then return "" end
	-- TODO: hash, cuz this is for exact passwords
	return "=" .. pass
end

---@param user string
---@param pass string
---@param users? userdb.user[]
---@param shadows? userdb.shadow[]
function userdb.checkpass(user, pass, users, shadows)
	users = users or assert(userdb.parsePasswd())
	shadows = shadows or {} -- TODO: read /etc/shadow

	for _, uinfo in ipairs(users) do
		if uinfo.name == user then
			if uinfo.password == "x" then
				for _, shadow in ipairs(shadows) do
					if shadow.name == user then
						return userdb.checkpasshash(shadow.password, pass)
					end
				end
				return false
			end
			return userdb.checkpasshash(uinfo.password, pass)
		end
	end

	return false
end

return userdb
