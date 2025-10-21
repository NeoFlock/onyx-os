--!lua

-- Onyx Package Keeper

local args = {...}
local readline = require("readline")
local perms = require("perms")
local libopk = require("libopk", true) -- uncached cuz it can be quite heavy

local action = table.remove(args, 1)

if (not action) or action == "--help" or action == "help" then
	-- Help!!!!
	print("opk [action] [options] [...args]")
	print("Common invocations:")
	print("\topk sync - Update repo caches")
	print("\topk add [-Syu] <packages> - Add packages (-S to sync, -y to accept all packages automatically, -u to update system)")
	print("\topk rm [-c] <packages> - Remove packages (-c to clean afterwards)")
	print("\topk clean - Remove orphaned packages, aka installed packages not in the world")
	print("\topk update [-c] - Update packages with different versions than in their repos (-c to only check if updates are available)")
	print("\topk chrepo [-p] <repo> <packages> - Change the associated repository of installed packages (-p to use Lua patterns)")
	print("\topk list [-piw] <pattern?> - List packages (-p to use Lua patterns, -i for installed only, -w for world only)")
	print("\topk repos - Display all repos")
	print("\topk query <package> - Display package information")
	print("\topk add-repo <name> <url> <opts?> - Add a repository (opts can be nothing or ? for optional)")
	print("\topk rm-repo <name> - Remove a repository")
	return 0
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
local function update(all, autoAccept)
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
	print("To install:", table.concat(names, ", "))
	if not autoAccept then
		io.write("Install packages? [y/N] ")
		io.flush()
		local y = readline()
		if not y then return end
		if y:lower():sub(1,1) ~= "y" then return end
	end

	for _, p in ipairs(toUpdate) do
		print("Installing " .. p.package .. "...")
		local info = all[p.package]
		if info.preinstall then
			print("Running " .. #info.preinstall .. " commands")
			for _, cmd in ipairs(info.preinstall) do
				print("+", cmd)
				os.execute(cmd)
			end
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
				print("Updating " .. path .. "...")
				local file = info.files[path]
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
			print("Running " .. #info.postinstall .. " commands")
			for _, cmd in ipairs(info.postinstall) do
				print("+", cmd)
				os.execute(cmd)
			end
		end
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
			if shouldBeIncluded(installed.package) then print(installed.package) end
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
	update(all)
	return 0
end

print("Unknown action:", action)
return 1
