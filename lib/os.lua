---@diagnostic disable: duplicate-set-field
-- os functions

os.touch = k.touch
os.mkdir = k.mkdir

function os.tmpname()
	local p
	repeat
		p = "/tmp/" .. k.getpid() .. "_" .. math.random(0, 9999999)
		if k.exists(p) then p = nil end
	until p
	return p
end

---@param varname string
---@return string?
function os.getenv(varname)
	return k.environ()[varname]
end

---@return table<string, string>
function os.getenvs()
	return k.environ()
end

---@param varname string
---@param val string?
function os.setenv(varname, val)
	k.environ()[varname] = val
end

os.exit = k.exit
os.exec = k.exec
os.fork = k.fork

---@param bin string
---@param argv? string[]
---@param env? table<string, string>
---@param namespace? _G
function os.executeBin(bin, argv, env, namespace)
	local child = assert(k.fork(function()
		assert(k.exec(bin, argv, env, namespace))
	end))
	local exit = assert(k.waitpid(child))
	return exit == 0, "exit", exit
end

---@param command string
function os.execute(command)
	local userdb = require("userdb")
	local shutils = require("shutils")
	local user = shutils.getUser()
	local shell = userdb.getShell(user)
	return os.executeBin(shell, {"-c", command})
end
