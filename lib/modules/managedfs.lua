local metadata = Kocos.getCmdlineStr("MANAGEDFS_METADATA", ".kocos")

---@class Kocos.managedfs.frecord
---@field uid integer
---@field gid integer
---@field perms integer
---@field ftype Kocos.filetype

---@class Kocos.managedfs
---@field dev Kocos.dev
---@field readonly boolean
---@field frecords? table<string, Kocos.managedfs.frecord>
---@field cmdline table<string, string>

---@type Kocos.descriptorHandler
local function managedfsHandler(desc, ev, ...)
	---@type Kocos.dev, integer, string
	local dev, fd, m = desc._dev, desc._fd, desc._mode
	if ev == "close" then
		return dev.close(fd)
	end
	if ev == "read" and m == "r" then
		return dev.read(fd, ...)
	end
	if ev == "write" and m ~= "r" then
		return dev.write(fd, ...)
	end
	if ev == "seek" then
		return dev.seek(fd, ...)
	end
	return nil, Kocos.EBADF
end

---@type Kocos.module
return function(req, ...)
	if req == "FS-mount" then
		---@type Kocos.dev, string
		local dev, cmdline = ...
		if dev.type ~= "filesystem" then return end -- ignore

		---@type Kocos.managedfs
		local state = {
			dev = dev,
			readonly = dev.isReadOnly(),
			frecords = nil,
			cmdline = Kocos.parseCmdline(cmdline),
		}

		if dev.exists(metadata) and state.cmdline["noMetadata"] ~= "true" then
			-- TODO: use a *way* more efficient format.
			-- Currently just for the ONYX root, it takes ~15K
			-- That is a lot of space to give up on.
			local fd, err = dev.open(metadata, "r")
			if not fd then return nil, err end

			local data = ""
			while true do
				local chunk, err = dev.read(fd, math.huge)
				if err then return nil, err end
				if not chunk then break end
				data = data .. chunk
			end

			local lines = string.split(data, "\n")
			local header = lines[1]
			if not header then return nil, Kocos.EHWPOISON end
			if header:sub(1, 6) ~= "KMETA " then return nil, "unsupported metadata format" end
			local headerInfo = string.split(header, " ")
			local ver = tonumber(headerInfo[2]) or math.huge
			state.frecords = {}
			if ver == 1 then
				for i=4,#lines do
					local parts = string.split(lines[i], " ")
					if #parts == 5 then
						state.frecords[parts[1]] = {
							ftype = parts[2] or "regular",
							uid = tonumber(parts[3]) or 0,
							gid = tonumber(parts[4]) or 0,
							perms = tonumber(parts[5]) or Kocos.P_DEFAULT,
						}
					end
				end
			else
				return nil, "unsupported metadata version"
			end
		end

		return state
	end
	if req == "FS-umount" or req == "FS-sync" then
		---@type Kocos.managedfs
		local state = ...
		-- Flush shi
		-- Fail in umount is silent, so pray to God it doesn't happen

		if state.frecords and state.dev.exists(metadata) and not state.readonly then
			local lines = {
				"KMETA 1",
				"PATH FTYPE OWNER GROUP PERMS",
			}
			for path, rec in pairs(state.frecords) do
				---@type Kocos.fstat?
				local stat = Kocos._defaultManagedFS("FS-stat", state, path)
				if stat then
					table.insert(lines, string.format("%s %s %d %d %d", path, stat.type, stat.uid, stat.gid, stat.perms))
				else
					table.insert(lines, string.format("%s %s %d %d %d", path, rec.ftype, rec.uid, rec.gid, rec.perms))
				end
			end
			local ser = table.concat(lines, "\n")
			local f, err = state.dev.open(metadata, "w")
			if not f then return nil, err end

			local ok, err = state.dev.write(f, ser)
			state.dev.close(f)
			return ok, err
		end
		return true
	end
	if req == "FS-open" then
		---@type Kocos.managedfs, string, string
		local state, path, mode = ...

		local fd, err = state.dev.open(path, mode)
		if not fd then return nil, err end

		---@type Kocos.descriptor
		return {
			type = "file",
			state = "normal",
			rc = 1,
			flags = 0,
			pid = 0,
			handler = managedfsHandler,
			_dev = state.dev,
			_fd = fd,
			_mode = mode,
		}
	end
	if req == "FS-touch" then
		---@type Kocos.managedfs, string, Kocos.filetype, integer, integer, integer
		local state, path, ftype, perms, uid, gid = ...

		if ftype ~= "regular" and ftype ~= "directory" and not state.frecords then
			return false, Kocos.EPERM
		end

		if path == metadata and ftype ~= "regular" then
			return false, Kocos.EPERM
		end

		if ftype == "directory" then
			local ok, err = state.dev.makeDirectory(path)
			if not ok then return false, err end
		else
			local f, err = state.dev.open(path, "a")
			if not f then return false, err end
			state.dev.close(f)
		end

		-- apparently we just created the new .kocos
		if path == metadata and not state.frecords then
			state.frecords = {}
		end

		if state.frecords then
			state.frecords[path] = {
				ftype = ftype,
				perms = perms,
				uid = uid,
				gid = gid,
			}
		end
		return true
	end
	if req == "FS-list" then
		---@type Kocos.managedfs, string
		local state, path = ...
		return state.dev.list(path)
	end
	if req == "FS-stat" then
		---@type Kocos.managedfs, string
		local state, path = ...

		if not state.dev.exists(path) then
			return nil, Kocos.ENOENT
		end

		---@type Kocos.fstat
		local stat = {
			type = state.dev.isDirectory(path) and "directory" or "regular",
			deviceAddress = state.dev.address,
			diskUsed = state.dev.spaceUsed(),
			diskTotal = state.dev.spaceTotal(),
			size = state.dev.size(path),
			diskSize = 0,
			uid = 0,
			gid = 0,
			inode = -1,
			lastModified = state.dev.lastModified(path),
			perms = 0,
			linkCount = 1,
		}

		stat.diskSize = stat.size

		if state.frecords and state.frecords[path] then
			local rec = state.frecords[path]
			stat.type = rec.ftype or stat.type
			stat.perms = rec.perms or 0
			stat.uid = rec.uid or 0
			stat.gid = rec.gid or 0
		else
			stat.perms = stat.type == "directory" and Kocos.P_ALL or Kocos.P_DEFAULT
		end

		if path == "" then
			-- don't care
			stat.perms = 511
			stat.type = "directory"
		end

		if path == metadata then
			-- Only root may change this file.
			-- The ability to change this file
			-- may be one of the most devastating powers there can be.
			stat.perms = 6*64 + 4*8 + 4
		end

		stat.perms = stat.perms or 0

		return stat
	end
	-- not handled
end
