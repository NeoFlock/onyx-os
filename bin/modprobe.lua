--!lua

local args = {...}

local verbose = false
local remove = false
local reload = false
local quiet = false

while true do
	if args[1] == "-r" or args[1] == "--remove" then
		table.remove(args, 1)
		remove = true
	elseif args[1] == "-v" or args[1] == "--verbose" then
		table.remove(args, 1)
		verbose = true
	elseif args[1] == "-R" or args[1] == "--reload" then
		table.remove(args, 1)
		reload = true
	elseif args[1] == "-q" or args[1] == "--quiet" then
		table.remove(args, 1)
		quiet = true
	elseif args[1] == "-h" or args[1] == "--help" then
print[[
modprobe [OPTS...] [MODULES...] - Add or remove modules
Options:
	-r / --remove - Remove modules instead of inserting them
	-v / --verbose - Print operations
	-R / --reload - Reload already active modules
	-q / --quiet - Ignore errors
]]
		return 0
	else
		break
	end
end

if remove then
	for _, mod in ipairs(args) do
		local ok, err = k.dkms_unload(mod)
		if not quiet then
			if ok then
				print("Removed", mod)
			else
				print(err)
			end
		end
	end
else
	for _, mod in ipairs(args) do
		local was = k.dkms_loaded(mod)
		local ok, err = k.dkms_load(mod, reload)
		if not quiet then
			if ok then
				print(was and "Reloaded" or "Loaded", mod)
			else
				print(err)
			end
		end
	end
end
