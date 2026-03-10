--!lua

local readline = require("readline")
local shutils = require("shutils")
local userdb = require("userdb")
local libash = require("libash")

local exec = {}

local statTime = os.time()

---@type table<string, fun(): string>
local magicVars = {
	SECONDS = function()
		return tostring(os.time() - statTime)
	end,
}

---@type table<string, string>[]
exec.scope = {{}}
---@type table<string, {args: string[], body: ash.command[]}>
exec.funcs = {}

exec.lastExit = 0

---@alias ash.stdio {inp: integer, out: integer, err: integer, term: integer}

---@type table<string, fun(args: string[], std: ash.stdio, env: table<string, string>): integer>
local builtin = {}

function builtin.exit(args)
	k.exit(tonumber(args[1]))
end

function builtin.cd(args, std)
	local ok, err = k.chdir(args[1] or userdb.getHome(shutils.getUser()))
	if not ok then
		k.write(std.err, "cd: " .. err .. "\n")
	end
	return ok and 0 or 1
end

function builtin.which(args, std)
	local wrong = 0
	for _, arg in ipairs(args) do
		---@type string?
		local place
		if builtin[arg] then
			place = "builtin shell command"
		elseif table.contains(libash.shellWords, arg) then
			place = "reserved shell word"
		else
			place = shutils.search(arg)
		end

		if place then
			k.write(std.out, arg .. ": " .. place .. "\n")
		else
			k.write(std.err, "could not find " .. arg .. "\n")
			wrong = wrong + 1
		end
	end
	return wrong
end

function builtin.export(args, std)
	local malformed = 0
	for _, var in ipairs(args) do
		local eql = string.find(var, "=")
		if eql then
			local name = string.sub(var, 1, eql-1)
			local val = string.sub(var, eql+1)
			os.setenv(name, val)
		else
			malformed = malformed + 1
			k.write(std.err, "malformed export assignment: " .. var .. "\n")
		end
	end
	return malformed
end

builtin["local"] = function(args, std)
	local curScope = exec.scope[#exec.scope]
	local malformed = 0
	for _, var in ipairs(args) do
		local eql = string.find(var, "=")
		if eql then
			local name = string.sub(var, 1, eql-1)
			local val = string.sub(var, eql+1)
			curScope[name] = val
		else
			malformed = malformed + 1
			k.write(std.err, "malformed local assignment: " .. var .. "\n")
		end
	end
	return malformed
end

function builtin.eval(args, std)
	local failed = 0
	for _, arg in ipairs(args) do
		local cmds, err = libash.parse(arg)
		if cmds then
			for _, cmd in ipairs(cmds) do
				local e = exec.runCommand(cmd, std)
				if e ~= 0 then
					failed = failed + 1
					k.write(std.err, "eval expression returned: " .. e .. "\n")
				end
			end
		else
			k.write(std.err, "eval error: " .. err .. "\n")
		end
	end
	return failed
end

function builtin.exec(args, std)
	local bin = table.remove(args, 1)
	args[0] = bin
	local _, err = k.exec(bin, args)
	-- exec returned, thus error
	k.write(std.err, "exec error: " .. err .. "\n")
	return 1
end

local args = {...}

---@param arg ash.argument
---@param std ash.stdio
---@return string[]
function exec.processArgument(arg, std)
	if arg.value then
		return {arg.value}
	elseif arg.substitution then
		if arg.substitution == "$?" then
			return {tostring(exec.lastExit)}
		end
		if arg.substitution == "$$" then
			return {tostring(k.getpid())}
		end
		if arg.substitution == "$#" then
			return {tostring(#args)}
		end
		if arg.substitution == "$@" then
			return table.copy(args)
		end
		if arg.substitution == "$*" then
			return {table.concat(args, " ")}
		end
		for i=#exec.scope,1,-1 do
			local locals = exec.scope[i]
			if locals[arg.substitution] then
				return {locals[arg.substitution]}
			end
		end
		return {os.getenv(arg.substitution) or ""}
	elseif arg.command then

	elseif arg.compound then
		local allVars = {""}

		for _, sub in ipairs(arg.compound) do
			local parts = exec.processArgument(sub, std)
			allVars[#allVars] = allVars[#allVars] .. parts[1]
			for i=2,#parts do table.insert(allVars, parts[i]) end
		end

		if #allVars == 0 then allVars[1] = "" end
		return allVars
	end
	return {""}
end

---@param command ash.command
---@param std ash.stdio
---@return integer
function exec.runCommand(command, std)
	if command.simple then
		---@type string[]
		local argv = {}
		local i = 0

		for _, arg in ipairs(command.simple) do
			local data = exec.processArgument(arg, std)
			for _, str in ipairs(data) do
				argv[i] = str
				i = i + 1
			end
		end

		if i == 0 then return 0 end
		return exec.runParts(argv, nil, std)
	end
	k.write(std.err, "ash: unsupported command type. THIS IS A BUG.\n")
	return 1
end

---@param var string
---@param val string
function exec.setVar(var, val)
	for i=#exec.scope, 1, -1 do
		local locs = exec.scope[i]
		if locs[var] or i == 1 then
			locs[var] = val
			return
		end
	end
end

---@param argv string[]
---@param env? table<string, string>
---@param std ash.stdio
---@return integer
function exec.runParts(argv, env, std)
	env = env or k.environ()
	local cmd = argv[0]

	if not cmd then
		exec.lastExit = 0
		return 0
	end

	if builtin[cmd] then
		exec.lastExit = builtin[cmd](argv, std, env)
		return exec.lastExit
	end

	if string.find(cmd, "=") then
		local assigns = {}
		local last = 0
		for i=0,#argv do
			local a = argv[i]
			if not a then break end
			local eql = string.find(a, "=")
			if not eql then break end
			local name = string.sub(a, 1, eql-1)
			local val = string.sub(a, eql+1)
			assigns[name] = val
			last = i
		end

		if last == #argv then
			-- just assignments
			for var, val in pairs(assigns) do
				exec.setVar(var, val)
			end
			return 0
		else
			local newEnv = table.copy(env)
			for var, val in pairs(assigns) do
				newEnv[var] = val
			end
			local nargs = {}
			for i=last+1,#argv do
				nargs[i - last - 1] = argv[i]
			end
			return exec.runParts(nargs, newEnv, std)
		end
	end

	local bin = k.exists(cmd) and cmd or shutils.search(cmd)
	if bin then
		local child, err = k.fork(function()
			local ok, err = k.exec(bin, argv, env)
			if not ok then
				k.write(std.err, "exec error: " .. err .. "\n")
				k.exit(1)
			end
			k.exit(0)
		end)
		if not child then
			k.write(std.err, "internal fork: " .. err .. "\n")
			return 1
		end
		k.ioctl(std.term, "setfgpid", child)
		exec.lastExit = k.waitpid(child)
		return exec.lastExit
	end
	k.write(std.err, "ash: unknown command: " .. cmd .. "\n")
	exec.lastExit = 1
	return exec.lastExit
end

if args[1] == "-c" then
	local cmds, err = libash.parse(args[2])
	if cmds then
		for _, cmd in ipairs(cmds) do
			exec.runCommand(cmd, {
				inp = 0,
				out = 1,
				err = 2,
				term = 3,
			})
		end
	else
		k.write(2, string.format("error: %s", err))
	end
	return
elseif args[1] then
	local script = args[1]
	local data = assert(readfile(script))
	local code, err, loc = libash.parse(data)
	if code then
		for _, cmd in ipairs(code) do
			exec.runCommand(cmd, {
				inp = 0,
				out = 1,
				err = 2,
				term = 3,
			})
		end
	else
		k.write(2, string.format("error: %s:%d:%s", script, libash.lineOfOffset(data, loc or 0), err))
	end
	return
end

local shlvl = 1 + (tonumber(os.getenv("SHLVL")) or 0)
os.setenv("SHLVL", tostring(shlvl))

print("\x1b[36mAsh\x1b[32m v0.0.1\x1b[0m")
local history = {}
while true do
	os.setenv("PWD", shutils.getWorkingDirectory())
	k.write(1, shutils.promptFormatToAnsi(os.getenv("PS1")))
	k.write(1, "\x1b[0m ")
	local line = readline(nil, nil, nil, function(i) return history[i] end)
	if not line then return end
	local l = line:sub(1, -2)
	-- de-duplication
	if history[1] ~= l then
		table.insert(history, 1, l)
	end
	local cmds, err = libash.parse(line)
	if cmds then
		for _, cmd in ipairs(cmds) do
			exec.runCommand(cmd, {
				inp = 0,
				out = 1,
				err = 2,
				term = 3,
			})
		end
	else
		k.write(2, string.format("error: %s", err))
	end
end
