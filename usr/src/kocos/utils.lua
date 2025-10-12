function table.copy(t)
	if type(t) == "table" then
		local nt = {}
		for k, v in pairs(t) do
			nt[k] = v
		end
		return nt
	else
		return t
	end
end

local luaglobals = {
	"_VERSION",
	"_OSVERSION",
	"_KVERSION",
	"assert",
	"error",
	"getmetatable",
	"ipairs",
	"next",
	"pairs",
	"pcall",
	"rawequal",
	"rawget",
	"rawset",
	"rawlen",
	"select",
	"setmetatable",
	"tonumber",
	"tostring",
	"type",
	"xpcall",
	"bit32",
	"table",
	"string",
	"math",
	"debug",
	"os",
	"checkArg",
	"unicode",
	"utf8",
	"coroutine",
	"load",
	"syscall",
	"require",
	"package",
	"writefile",
	"readfile",
	"loadfile",
	"dofile",
}

---@param src? _G
---@return _G
function table.luaglobals(src)
	src = src or _G
	local namespace = {}

	namespace._G = namespace

	for _, k in ipairs(luaglobals) do
		namespace[k] = table.copy(src[k])
	end
	namespace.package.loaded = {} -- fixed SO MUCH BS

	return namespace
end

local function isGoodKey(s)
	return type(s) == "string" and string.format("%q", s) == ('"' .. s .. '"')
end

---@param s string
---@param c? string
local function color(s, c)
	if not c then return s end
	return c .. s .. "\x1b[0m"
end

---@type table<type, string>
table.colorTypeInfo = {
	["nil"] = "\x1b[34m",
	boolean = "\x1b[34m",
	number = "\x1b[92m",
	string = "\x1b[32m",
	table = "\x1b[90m",
	thread = "\x1b[35m",
	["function"] = "\x1b[35m",
	["userdata"] = "\x1b[35m",
	--- definitely a lua type trust me
	docs = "\x1b[33m",
}

---@param colorinfo? table<type, string>
function table.serialize(val, refs, colorinfo)
	refs = refs or {}
	colorinfo = colorinfo or {}
	if type(val) == "table" then
		if refs[val] then return color("...", colorinfo.table) end
		refs[val] = true
		if getmetatable(val) and getmetatable(val).__tostring then
			return color(tostring(val), colorinfo.docs)
		end
		local s = color("{", colorinfo.table)
		local list = {}
		local done = {}
		for i, item in ipairs(val) do
			done[i] = true
			table.insert(list, table.serialize(item, refs, colorinfo))
		end
		for k, v in pairs(val) do
			if not done[k] then
				done[k] = true
				local pair = ""
				if isGoodKey(k) then
					pair = k
				else
					pair = "[" .. table.serialize(k, refs, colorinfo) .. "]"
				end
				k = pair .. " = " .. table.serialize(v, refs, colorinfo)
				table.insert(list, k)
			end
		end
		s = s .. table.concat(list, ", ")
		s = s .. color("}", colorinfo.table)
		return s
	elseif type(val) == "string" then
		return color(string.format("%q", val), colorinfo.string)
	else
		return color(tostring(val), colorinfo[type(val)])
	end
end

---@generic T
---@param t T[]
---@param v T
---@return boolean, integer?
function table.contains(t, v)
	for i, x in ipairs(t) do
		if v == x then
			return true, i
		end
	end
	return false
end

---@param memory integer
---@param spacing? string
function string.memformat(memory, spacing)
	spacing = spacing or ""

	local units = {"B", "KiB", "MiB", "GiB", "TiB", "PiB"}
	local scale = 1024

	while #units > 1 and memory >= scale do
		memory = memory / scale
		table.remove(units, 1)
	end

	return string.format("%.2f%s%s", memory, spacing, units[1])
end

---@param inputstr string
---@param sep string
---@return string[]
function string.split(inputstr, sep)
	if sep == nil then
		sep = "%s"
	end
	if sep == "" then
		sep = "."
	else
		sep = "[^" .. sep .. "]*"
	end
	local t = {}
	for str in string.gmatch(inputstr, "("..sep..")") do
		table.insert(t, str)
	end
	return t
end

---@param s string
---@param prefix string
function string.startswith(s, prefix)
    return s:sub(1, #prefix) == prefix
end

---@param s string
---@param suffix string
function string.endswith(s, suffix)
    return s:sub(-#suffix) == suffix
end

---@param s string
---@param l integer
---@param c? string
--- We assure you this will not break npm
function string.leftpad(s, l, c)
    if #s > l then return s end
    c = c or " "
    return string.rep(c, l - #s) .. s
end

---@param s string
---@param l integer
---@param c? string
function string.rightpad(s, l, c)
    if #s > l then return s end
    c = c or "\0"
    return s .. string.rep(c, l - #s)
end

---@param x number
---@param min number
---@param max number
function math.clamp(x, min, max)
    return math.min(max, math.max(x, min))
end

---@param x number
---@param min1 number
---@param max1 number
---@param min2 number
---@param max2 number
function math.map(x, min1, max1, min2, max2)
    return min2 + ((x - min1) / (max1 - min1)) * (max2 - min2)
end

-- Take in a binary and turn it into a GUID
-- Bin can be above 16 bytes.
-- If bin is less than 16 bytes, it is padded with 0s
---@param bin string
function string.binToGUID(bin)
    local digits4 = "0123456789abcdef"

    local base16d = ""
    for i=1,16 do
        local byte = string.byte(bin, i, i)
        if not byte then byte = 0 end
        local upper = math.floor(byte / 16) + 1
        local lower = byte % 16 + 1
        base16d = base16d .. digits4:sub(upper, upper) .. digits4:sub(lower, lower)
    end

    local guid = base16d:sub(1, 8) .. "-"
        .. base16d:sub(9, 12) .. "-"
        .. base16d:sub(13, 16) .. "-"
        .. base16d:sub(17, 20) .. "-"
        .. base16d:sub(21)

    return guid
end

function string.randomGUID()
	local buf = ""
	for _=1,16 do buf = buf .. string.char(math.random(0, 255)) end
	return string.binToGUID(buf)
end

---@param t number
function string.uptimefmt(t)
	local hours = math.floor(t / 3600)
	local mins = math.floor(t / 60) % 60
	local secs = t % 60

	return string.format("%02d:%02d:%02.3f", hours, mins, secs)
end

---@param t number
function string.boottimefmt(t)
	local hours = math.floor(t / 3600)
	local mins = math.floor(t / 60) % 60
	local secs = t % 60

	return string.format("%02dh%02dm%02.3fs", hours, mins, secs)
end

---@param name string
---@param path string
---@param sep? string
---@param rep? string
---@return string? filename, string? errmsg
function package.searchpath(name, path, sep, rep)
	sep = sep or "."
	rep = rep or "/"

	name = name:gsub("%" .. sep, rep)

	local paths = string.split(path, ';')

	for _, p in ipairs(paths) do
		local toCheck = p:gsub("%?", name)
		local fd = syscall("open", toCheck, "r")
		if fd then
			assert(syscall("close", fd))
			return toCheck
		end
	end
end

function dofile(filename, ...)
	return assert(loadfile(filename))(...)
end

function loadfile(filename, mode, env)
	local code, err = readfile(filename)
	if not code then return nil, err end
	if code:sub(1,2) == "#!" then
		-- shebang!
		local ln = string.find(code, "\n") or #code
		code = code:sub(ln+1)
	end
	return load(code, "=" .. filename, mode, env)
end

---@param bufsize? integer
---@return string?, string?
function readfile(filename, bufsize)
	local fd, err = syscall("open", filename, "r")
	if err then return nil, err end

	local code = ""
	while true do
		local data, err2 = syscall("read", fd, bufsize or math.huge)
		if err2 then
			syscall("close", fd)
			return nil, err2
		end
		if not data then break end
		code = code .. data
		coroutine.yield()
	end

	syscall("close", fd)
	return code
end

---@param data string
---@return boolean?, string?
function writefile(filename, data)
	local fd, err = syscall("open", filename, "r")
	if err then return nil, err end

	local ok, err2 = syscall("write", fd, data)
	if not ok then
		syscall("close", fd)
		return nil, err2
	end

	syscall("close", fd)
	return true
end
