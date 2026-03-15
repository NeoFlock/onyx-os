-- RamFS module

---@class Kocos.ramNode
---@field uid integer
---@field gid integer
---@field perms integer
---@field lastModified integer
---@field dir? table<string, Kocos.ramNode>
---@field regular? string

---@param tree Kocos.ramNode
---@param path string
---@param keepLast boolean
---@return Kocos.ramNode?, string?
local function resolvePath(tree, path, keepLast)
	if path == "" then return tree end
	local parts = string.split(path, "/")

	while true do
		if #parts == 1 and keepLast then return tree, parts[1] end
		if #parts == 0 then return tree end

		local child = table.remove(parts, 1)
		tree = tree.dir[child]
		if not tree then return end
	end
end

---@class Kocos.ramDescriptor: Kocos.descriptor
---@field _node Kocos.ramNode
---@field _cur integer
---@field _mode "r"|"a"|"w"

---@param handle Kocos.ramDescriptor
---@param req Kocos.descriptorReq
local function handleFd(handle, req, ...)
	if req == "close" then return true end
	if req == "write" then
		if handle._mode == "r" then return false, Kocos.EBADF end
		---@type string
		local data = ...
		if handle._mode == "a" then
			handle._node.regular = handle._node.regular .. data
			handle._cur = #handle._node.regular
			return true
		end
		local cur = handle._cur
		local reg = assert(handle._node.regular)
		handle._node.regular = string.sub(reg, 1, cur) .. data .. string.sub(reg, cur+#data+1)
		handle._cur = handle._cur + cur
		return true
	end
	if req == "read" then
		if handle._mode ~= "r" then return nil, Kocos.EBADF end
		---@type integer
		local len = ...
		local data = assert(handle._node.regular)

		local remaining = #data - handle._cur
		if remaining <= 0 then return end
		if len > remaining then len = remaining end

		local chunk = data:sub(1 + handle._cur, len + handle._cur)
		handle._cur = handle._cur + #chunk
		return chunk
	end
	if req == "seek" then
		if handle._mode == "a" then return nil, Kocos.EBADF end
		---@type string, integer
		local whence, off = ...

		local cur = handle._cur
		local data = assert(handle._node.regular)

		if whence == "set" then
			cur = off
		elseif whence == "end" then
			cur = #data - off
		elseif whence == "cur" then
			cur = cur + off
		end

		handle._cur = math.clamp(cur, 0, #data)
		return handle._cur
	end
	return nil, Kocos.EBADF
end

---@param req string
---@param state Kocos.ramNode
local function _ramfsDriver(req, state, ...)
	if req == "FS-umount" or req == "FS-sync" then
		return
	end
	if req == "FS-open" then
		---@type string, string
		local path, mode = ...

		local node = resolvePath(state, path, false)
		if not node then return nil, Kocos.ENOENT end
		if node.dir then return nil, Kocos.EISDIR end
		if not node.regular then return nil, Kocos.EHWPOISON end

		---@type Kocos.ramDescriptor
		return {
			type = "file",
			state = "normal",
			rc = 1,
			flags = 0,
			pid = 0,
			handler = handleFd,
			_cur = 0,
			_mode = mode,
			_node = node,
		}
	end
	if req == "FS-list" then
		---@type string
		local path = ...
		local node = resolvePath(state, path, false)
		if not node then return nil, Kocos.ENOENT end
		if not node.dir then return nil, Kocos.ENOTDIR end
		local ents = {}
		for k in pairs(node.dir) do table.insert(ents, k) end
		return ents
	end
	if req == "FS-stat" then
		---@type string
		local path = ...

		local node = resolvePath(state, path, false)
		if not node then return nil, Kocos.ENOENT end

		---@type Kocos.fstat
		local stat = {
			type = "regular",
			deviceAddress = "ramfs",
			diskUsed = 0,
			diskTotal = 0,
			size = 0,
			diskSize = 0,
			uid = node.uid,
			gid = node.gid,
			inode = -1,
			linkCount = 1,
			lastModified = node.lastModified,
			perms = node.perms,
		}

		if node.regular then
			stat.type = "regular"
			stat.size = #node.regular
		elseif node.dir then
			stat.type = "directory"
		end

		return stat
	end
end

Kocos.loadModuleCode("karmemfs", _EMBED_MIN("lib/modules/karmemfs.lua"))

---@param data string
---@param cmdline? string
---@return Kocos.mountState?, string?
function Kocos.ramfsFor(data, cmdline)
	cmdline = cmdline or ""
	---@type Kocos.ramNode?, string?
	local node, err

	for _, mod in pairs(Kocos.mods) do
		node, err = mod("FS-ramfs", data, cmdline)
		if err then return nil, err end
		if node then break end
	end

	if not node then
		return nil, Kocos.ENODRIVER
	end
	---@type Kocos.mountState
	local state = {
		state = node,
		cmdline = cmdline,
		device = "ramfs",
		driver = _ramfsDriver,
	}
	return state
end
