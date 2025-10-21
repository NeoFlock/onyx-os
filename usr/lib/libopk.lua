-- TODO: HTTP and Minitel support

---@alias opk.repo table<string, opk.package>

---@class opk.package
---@field description string
---@field version string
---@field authors string
---@field license string
---@field dependencies? string[]
---@field tarURL? string
---@field files? table<string, opk.file>
---@field preinstall? string[]
---@field postinstall? string[]
--- Internal
---@field repo? opk.repoData

---@class opk.file
---@field path string
---@field type Kocos.fs.ftype
---@field owner? string
---@field group? string
---@field perms? integer
--- If true, the file isn't overwritten if it exists
---@field default? boolean
--- If true, the file isn't deleted when uninstalled
---@field keep? boolean

---@alias opk.repoType "on-disk"|"http"|"minitel"

---@class opk.repoData
---@field name string
---@field url string
---@field type opk.repoType
---@field optional boolean

---@class opk.installedData
---@field package string
---@field version string

local libopk = {}

function libopk.getRepositories()
	---@type opk.repoData[]
	local t = {}
	for line in io.lines("/etc/opk/repositories") do
		local parts = string.split(line, " ")
		if #parts > 1 then
			local name = parts[1]
			local path = parts[2]
			local opts = parts[3]
			---@type opk.repoType
			local repotype = "on-disk"
			if string.startswith(path, "http://") then
				repotype = "http"
			end
			if string.startswith(path, "https://") then
				repotype = "http"
			end
			---@type opk.repoData
			local data = {
				name = name,
				type = repotype,
				url = path,
				optional = string.contains(opts, "?"),
			}
			table.insert(t, data)
		end
	end
	return t
end

---@param data opk.repoData
function libopk.findRepoCache(data)
	if data.type == "on-disk" then
		return data.url .. "/OPKREPO"
	else
		return "/etc/opk/cache_" .. data.name
	end
end

---@param data opk.repoData
---@return string?, string?
function libopk.downloadRepoFile(data, file)
	if data.type == "on-disk" then
		local truepath = k.join(data.url, file)
		return readfile(truepath)
	end
	-- TODO: other ones
	return nil, "bad repo type"
end

---@param data opk.repoData
---@return boolean, string?
function libopk.cacheRepo(data)
	if data.type == "on-disk" then return false end -- already on-disk
	local cachePath = libopk.findRepoCache(data)
	local toCache, err = libopk.downloadRepoFile(data, "OPKREPO")
	if not toCache then return false, err end
	return writefile(cachePath, toCache)
end

---@param data opk.repoData
---@return opk.repo?, string?
function libopk.getPackageInfo(data)
	local cachePath = libopk.findRepoCache(data)
	local cache, err = readfile(cachePath)
	if not cache then return nil, err end
	return table.deserialize(cache)
end

---@return string[]
function libopk.getWorld()
	local world = {}
	for line in io.lines("/etc/opk/world") do
		if line ~= "" then table.insert(world, line) end
	end
	return world
end

---@return opk.installedData[]
function libopk.getInstalled()
	local installed = {}
	for line in io.lines("/etc/opk/installed") do
		local parts = string.split(line, " ")
		if #parts == 2 then
			---@type opk.installedData
			local data = {
				package = parts[1],
				version = parts[2],
			}
			table.insert(installed, data)
		end
	end
	return installed
end

---@param world string[]
---@return boolean, string?
function libopk.writeWorld(world)
	return writefile("/etc/opk/world", table.concat(world, "\n") .. "\n")
end

---@param installed opk.installedData[]
---@return boolean, string?
function libopk.writeInstalled(installed)
	local t = {}
	for _, info in ipairs(installed) do
		table.insert(t, info.package .. " " .. info.version)
	end
	return writefile("/etc/opk/installed", table.concat(t, "\n") .. "\n")
end

---@return opk.repo?, string?
function libopk.everyPackage()
	---@type opk.repo
	local all = {}

	for _, repo in ipairs(libopk.getRepositories()) do
		local info, err = libopk.getPackageInfo(repo)
		if info then
			for p, pinfo in pairs(info) do
				pinfo.repo = repo
				all[p] = pinfo
			end
		elseif not repo.optional then
			return nil, err
		end
	end

	return all
end

return libopk
