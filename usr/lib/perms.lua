local perms = {}

perms.X = 1
perms.W = 2
perms.R = 4

perms.OTHER = 0
perms.GROUP = 3
perms.OWNER = 6

perms.OTHER_MASK = 7
perms.GROUP_MASK = 7 << perms.GROUP
perms.OWNER_MASK = 7 << perms.OWNER

---@param p integer
function perms.to3BitString(p)
	---@type string[]
	local t = {}
	t[1] = (p & perms.R) and "r" or "-"
	t[2] = (p & perms.W) and "w" or "-"
	t[3] = (p & perms.X) and "x" or "-"
	return table.concat(t)
end

---@param s string
---@return integer
function perms.from3BitString(s)
	local p = 0
	if s:sub(1,1) == "r" then p = p | perms.R end
	if s:sub(2,2) == "w" then p = p | perms.W end
	if s:sub(3,3) == "x" then p = p | perms.X end
	return p
end

---@param p integer
---@return string
function perms.toString(p)
	---@type string[]
	local t = {}
	t[1] = perms.to3BitString(p >> perms.OWNER)
	t[2] = perms.to3BitString(p >> perms.GROUP)
	t[3] = perms.to3BitString(p >> perms.OTHER)
	return table.concat(t)
end

---@param s string
---@return integer
function perms.fromString(s)
	local p = 0
	p = p | (perms.from3BitString(s:sub(1, 3)) << perms.OWNER)
	p = p | (perms.from3BitString(s:sub(4, 6)) << perms.GROUP)
	p = p | (perms.from3BitString(s:sub(7, 9)) << perms.OTHER)
	return p
end

perms.everything = 511

return perms
