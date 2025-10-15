-- Utilies for things that do shell-like operations

local userdb = require("userdb")

local shutils = {}

function shutils.getWorkingDirectory()
	return assert(k.chdir("."))
end

function shutils.getUser()
	local uid = k.geteuid()
	local users = userdb.parsePasswd() or {}
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
	local sys = "/sbin:/usr/local/bin:/usr/bin:/bin:/tmp/bin:/mnt/bin"
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
	exts = exts or {'', '.lua'}

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

---@param prompt string
---@param vars table<string, string|fun(s?: string): string>
function shutils.decodePromptWithVars(prompt, vars)
	local s = ""
	local chars = string.split(prompt, "")
	while #chars > 0 do
		local c = table.remove(chars, 1)
		if c == '%' then
			local v = table.remove(chars, 1) or ""
			if type(vars[v]) == "function" then
				if chars[1] == "{" then
					table.remove(chars, 1)
					-- has arg
					local arg = ""
					while #chars > 0 do
						local g = table.remove(chars, 1)
						if g == "}" then break end
						arg = arg .. g
					end
					s = s .. vars[v](arg)
				else
					s = s .. vars[v]()
				end
			else
				s = s .. (vars[v] or "")
			end
		else
			s = s .. c
		end
	end
	return s
end

shutils.DEFAULT_PROMPT = "%F{cyan}%n%F@%F{yellow}%M %F{green}%~ %#"

shutils.FGCOLORS = {
	reset = "\x1b[0m",
	default = "\x1b[39m",
	black = "\x1b[30m",
	red = "\x1b[31m",
	green = "\x1b[32m",
	yellow = "\x1b[33m",
	blue = "\x1b[34m",
	magenta = "\x1b[35m",
	cyan = "\x1b[36m",
	white = "\x1b[37m",
	gray = "\x1b[90m",
	brightRed = "\x1b[91m",
	brightGreen = "\x1b[92m",
	brightYellow = "\x1b[93m",
	brightBlue = "\x1b[94m",
	brightMagenta = "\x1b[95m",
	brightCyan = "\x1b[96m",
	brightWhite = "\x1b[97m",
}

shutils.BGCOLORS = {
	reset = "\x1b[0m",
	default = "\x1b[49m",
	black = "\x1b[40m",
	red = "\x1b[41m",
	green = "\x1b[42m",
	yellow = "\x1b[43m",
	blue = "\x1b[44m",
	magenta = "\x1b[45m",
	cyan = "\x1b[46m",
	white = "\x1b[47m",
	gray = "\x1b[100m",
	brightRed = "\x1b[101m",
	brightGreen = "\x1b[102m",
	brightYellow = "\x1b[103m",
	brightBlue = "\x1b[104m",
	brightMagenta = "\x1b[105m",
	brightCyan = "\x1b[106m",
	brightWhite = "\x1b[107m",
}

---@param prompt? string
function shutils.promptFormatToAnsi(prompt)
	prompt = prompt or shutils.DEFAULT_PROMPT
	-- save some disk I/O
	local user = shutils.getUser() or "guest"
	local hostname = shutils.getHostname()
	local cwd = shutils.getWorkingDirectory()
	local printPath = shutils.printablePath(cwd)
	return shutils.decodePromptWithVars(prompt, {
		["~"] = printPath,
		["n"] = user,
		["M"] = hostname,
		["#"] = user == "root" and "#" or ">",
		["d"] = cwd,
		["l"] = cwd,
		["D"] = function(s)
			---@type string
			return os.date(s or "%x")
		end,
		["T"] = function(s)
			---@type string
			return os.date("%X")
		end,
		["t"] = function(s)
			---@type string
			return os.date("%I:%M:%S %p")
		end,
		["E"] = "\x1b[0K",
		["F"] = function(s)
			return shutils.FGCOLORS[s] or "\x1b[39m"
		end,
		["K"] = function(s)
			return shutils.BGCOLORS[s] or "\x1b[49m"
		end,
	})
end

return shutils
