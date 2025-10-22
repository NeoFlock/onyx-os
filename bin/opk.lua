--!lua

-- Onyx Package Keeper

local args = {...}
local readline = require("readline")
local perms = require("perms")
local libopk = require("libopk", true) -- uncached cuz it can be quite heavy

local root = "/"

while #args > 0 do
	local arg = args[1]
	if arg:sub(1,1) ~= "-" then break end
	table.remove(args, 1)

	if arg == "--root" then
		root = table.remove(args, 1) or "/"
	else
		print("Unknown global option:", arg)
		return 1
	end
end

local action = table.remove(args, 1)

if (not action) or action == "help" then
	-- Help!!!!
	print("opk [global options] [action] [options] [...args]")
	print("Global options include:")
	print("\t--root <root> - The root to install programs into. Defaults to /. Mostly useful for installing the operating system.")
	print("Common invocations:")
	print("\topk help - Prints this help page")
	print("\topk sync - Update repo caches")
	print("\topk add [-Sy] <packages> - Add packages to the world. If not installed, marks version NONE as installed. Runs an update afterwards to install them. (-S to sync, -y to accept all packages automatically)")
	print("\topk rm [-c] <packages> - Remove packages (-c to clean afterwards)")
	print("\topk clean - Remove orphaned packages, aka installed packages not in the world and not needed by other packages")
	print("\topk update [-c] - Update packages with different versions than in their repos (-c to only check if updates are available)")
	print("\topk list [-piw] <pattern?> - List packages (-p to use Lua patterns, -i for installed only, -w for world only)")
	print("\topk repos - Display all repos")
	print("\topk query <package> - Display package information")
	print("\topk add-repo <name> <url> <opts?> - Add a repository (opts can be nothing or ? for optional)")
	print("\topk rm-repo [...names] - Remove repositories")
	return 0
end

---@param cmds string[]
local function execCommandList(cmds)
	local pid = assert(k.fork(function()
		assert(k.chroot(root))
		print("Running", #cmds, "commands")
		for _, cmd in ipairs(cmds) do
			print("+", cmd)
			os.execute(cmd)
		end
	end))
	k.waitpid(pid)
end

local function sync()
	local repos = libopk.getRepositories()
	print("Synchronizing " .. #repos .. " repos")
	for _, repo in ipairs(repos) do
		io.write("Caching " .. repo.name .. "...")
		io.flush()
		libopk.cacheRepo(repo)
		print("DONE")
	end
end

---@param all opk.repo
---@param list string[]
---@param package string
local function computeToInstall(all, list, package)
	if table.contains(list, package) then return end

	table.insert(list, package)

	local info = all[package]
	if info and info.dependencies then
		for _, dep in ipairs(info.dependencies) do
			computeToInstall(all, list, dep)
		end
	end
end

---@param all opk.repo
---@param p opk.installedData
local function install(all, p)
	print("Installing " .. p.package .. "...")
	local info = all[p.package]
	if info.preinstall then
		execCommandList(info.preinstall)
	end
	if info.tarURL then
		print("Tar URL unsupported, skipping...")
	end
	if info.files then
		---@type string[]
		local paths = {}
		for path in pairs(info.files) do
			table.insert(paths, path)
		end
		table.sort(paths, function(a, b) return #a < #b end)
		print("Updating", #paths, "files")
		for _, path in ipairs(paths) do
			local file = info.files[path]
			path = assert(k.join(root, path))
			print("Updating " .. path .. "...")
			if file.type == "regular" then
				-- TODO: download first, then commit
				local data = assert(libopk.downloadRepoFile(info.repo, file.path))
				local existed = k.exists(path)
				if not existed then assert(k.touch(path, file.perms or perms.everything)) end
				assert(writefile(path, data))
			end
		end
	end
	if info.postinstall then
		execCommandList(info.postinstall)
	end
end

---@param path string
---@param file opk.file
local function uninstallFile(path, file)
	if file.keep then return end
	os.remove(path)
end

---@param all opk.repo
---@param p string
local function uninstall(all, p)
	print("Installing " .. p .. "...")
	local info = all[p]
	if info.preuninstall then
		execCommandList(info.preuninstall)
	end
	if info.tarURL then
		print("Tar URL unsupported, skipping...")
	end
	if info.files then
		---@type string[]
		local paths = {}
		for path in pairs(info.files) do
			table.insert(paths, path)
		end
		table.sort(paths, function(a, b) return #a > #b end)
		print("Updating", #paths, "files")
		for _, path in ipairs(paths) do
			local file = info.files[path]
			print("Updating " .. path .. "...")
			path = assert(k.join(root, path))
			uninstallFile(path, file)
		end
	end
	if info.postuninstall then
		execCommandList(info.postuninstall)
	end
end

---@param all opk.repo
local function update(all, onlyCheck, autoAccept)
	local installed = libopk.getInstalled()

	---@type opk.installedData[]
	local toUpdate = {}

	for _, p in ipairs(installed) do
		local info = all[p.package]
		-- if it is gone, this is HORRIBLE
		if info then
			-- check version differences, fuck semver
			if info.version ~= p.version then
				table.insert(toUpdate, p)
				p.version = info.version
			end
		end
	end

	if #toUpdate == 0 then
		print("Nothing to update")
		return
	end

	local names = {}
	for i=1,#toUpdate do
		names[i] = toUpdate[i].package .. " v" .. toUpdate[i].version
	end
	print("To update:", table.concat(names, ", "))
	if onlyCheck then return end
	if not autoAccept then
		io.write("Install packages? [y/N] ")
		io.flush()
		local y = readline()
		if not y then return end
		if y:lower():sub(1,1) ~= "y" then return end
	end

	for _, p in ipairs(toUpdate) do
		install(all, p)
	end

	assert(libopk.writeInstalled(installed))
end

---@param name string
---@return opk.package?, string?
local function getPackage(name)
	local repos = libopk.getRepositories()
	for _, repo in ipairs(repos) do
		local packs, err = libopk.getPackageInfo(repo)
		if packs then
			for pack, info in pairs(packs) do
				if pack == name then return info end
			end
		else
			if not repo.optional then return nil, err end
		end
	end
	return nil, "no such package"
end

if action == "repos" then
	local repos = libopk.getRepositories()
	for _, repo in ipairs(repos) do
		print(repo.name, repo.type, repo.url, repo.optional and "optional" or nil)
	end
	return 0
end

if action == "query" then
	local info, err = getPackage(args[1])
	if not info then
		print("Error:", err)
		return 1
	end
	print(table.serialize(info, nil, table.colorTypeInfo))
	return 0
end

if action == "sync" then
	sync()
	return 0
end

if action == "list" then
	local isPattern = false
	local worldOnly = false
	local installedOnly = false
	if args[1] and args[1]:sub(1,1) == "-" then
		for i=2,#args[1] do
			local c = args[1]:sub(i, i)
			if c == "p" then isPattern = true end
			if c == "i" then installedOnly = true end
			if c == "w" then worldOnly = true end
		end
		table.remove(args, 1)
	end
	local pattern = args[1] or ""

	local function shouldBeIncluded(name)
		return string.contains(name, pattern, isPattern)
	end

	if worldOnly then
		for _, pack in ipairs(libopk.getWorld()) do
			if shouldBeIncluded(pack) then print(pack) end
		end
	elseif installedOnly then
		for _, installed in ipairs(libopk.getInstalled()) do
			if shouldBeIncluded(installed.package) then print(installed.package, "v" .. installed.version) end
		end
	else
		local everyPackage, err = libopk.everyPackage()
		if not everyPackage then
			print("Error:", err)
			return 1
		end
		for p in pairs(everyPackage) do
			if shouldBeIncluded(p) then print(p) end
		end
	end
	return 0
end

if action == "update" then
	local all, err = libopk.everyPackage()
	if not all then
		print("Error:", err)
		return 1
	end
	update(all, nil, args[1] == "-c")
	return 0
end

if action == "add" then
	local world = libopk.getWorld()
	local installed = libopk.getInstalled()
	local all, err = libopk.everyPackage()
	if not all then
		print("Error:", err)
		return 1
	end

	local toInstall = {}
	for _, p in ipairs(args) do
		if not table.contains(world, p) then table.insert(world, p) end
		computeToInstall(all, toInstall, p)
	end

	for _, p in ipairs(toInstall) do
		local found = false
		for _, i in ipairs(installed) do
			if i.package == p then
				found = true
				break
			end
		end
		if not found then
			table.insert(installed, {
				package = p,
				version = "NONE",
			})
		end
	end

	assert(libopk.writeWorld(world))
	assert(libopk.writeInstalled(installed))

	update(all)

	return 0
end

if action == "rm" then
	---@type string[]
	local toRemove = args
	local all, err = libopk.everyPackage()
	if not all then
		print("Error:", err)
		return 1
	end

	local world = libopk.getWorld()
	local installed = libopk.getInstalled()

	---@type string[]
	local newWorld = {}
	---@type opk.installedData[]
	local newInstalled = {}

	for _, p in ipairs(world) do
		if not table.contains(toRemove, p) then
			table.insert(newWorld, p)
		end
	end

	for _, p in ipairs(installed) do
		if not table.contains(toRemove, p.package) then
			table.insert(newInstalled, p)
		end
	end

	for _, p in ipairs(toRemove) do
		uninstall(all, p)
	end

	assert(libopk.writeWorld(newWorld))
	assert(libopk.writeInstalled(newInstalled))
	return 0
end

print("Unknown action:", action)
return 1
