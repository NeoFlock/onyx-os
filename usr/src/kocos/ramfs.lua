---@class Kocos.ramfs.node
---@field fileData string?
---@field items table<string, Kocos.ramfs.node>?

---@class Kocos.ramfs.file
---@field mode "r"|"w"|"a"
---@field offset integer
---@field node Kocos.ramfs.node

---@class Kocos.ramfs
---@field label string?
---@field readonly boolean
---@field fds table<integer, Kocos.ramfs.file>
---@field image Kocos.ramfs.node

---@param ramfs Kocos.ramfs
---@param path string[]
---@return Kocos.ramfs.node?
local function processPathParts(ramfs, path)
	local node = ramfs.image
	while #path > 0 do
		local name = table.remove(path, 1)
		if not node.items then return end
		node = node.items[name]
		if not node then return end
	end
	return node
end

---@param ramfs Kocos.ramfs
---@param path string
---@return Kocos.ramfs.node?
local function processPath(ramfs, path)
	local s = string.split(Kocos.fs.canonical(path):sub(2), "/")
	return processPathParts(ramfs, s)
end

---@param ramfs Kocos.ramfs
---@param path string
---@return Kocos.ramfs.node?, string
local function processParentPath(ramfs, path)
	local s = string.split(Kocos.fs.canonical(path):sub(2), "/")
	local name = s[#s]
	s[#s] = nil
	return processPathParts(ramfs, s), name
end

---@param ramfs Kocos.ramfs
---@param address? string
function Kocos.addRamfsComponent(ramfs, address)
	address = address or string.randomGUID()
	return component.add {
		address = address,
		type = "filesystem",
		slot = -1,
		methods = {
			spaceUsed = {direct = true},
			spaceTotal = {direct = true},
			getLabel = {direct = true},
			setLabel = {direct = true},
			exists = {direct = true},
			size = {direct = true},
			list = {direct = true},
			isDirectory = {direct = true},
			isReadOnly = {direct = true},
			lastModified = {direct = true},
			makeDirectory = {direct = true},
			open = {direct = true},
			write = {direct = true},
			read = {direct = true},
			close = {direct = true},
		},
		invoke = function(method, ...)
			if method == "spaceUsed" then
				return computer.totalMemory() - computer.freeMemory()
			end
			if method == "spaceTotal" then
				return computer.totalMemory()
			end
			if method == "getLabel" then
				return ramfs.label
			end
			if method == "setLabel" then
				ramfs.label = tostring((...))
				return ramfs.label
			end
			if method == "exists" then
				local p = ...
				if p == "" then return true end
				return processPath(ramfs, p) ~= nil
			end
			if method == "size" then
				local p = ...
				if p == "" then return 0 end
				local node = processPath(ramfs, p)
				if not node then return 0 end
				if not node.fileData then return 0 end
				return #node.fileData
			end
			if method == "list" then
				local p = ...
				local node = p == "" and ramfs.image or processPath(ramfs, p)
				if not node then return nil, "no such file" end
				if not node.items then return end
				local items = {}
				for name, child in pairs(node.items) do
					if child.items then
						table.insert(items, name .. "/")
					else
						table.insert(items, name)
					end
				end
				return items
			end
			if method == "isDirectory" then
				local p = ...
				if p == "" then return true end
				local node = processPath(ramfs, p)
				if not node then return false end
				return node.items ~= nil
			end
			if method == "isReadOnly" then
				return ramfs.readonly
			end
			if method == "lastModified" then return 0 end
			if method == "makeDirectory" then
				local p = ...
				local parent, name = processParentPath(ramfs, p)
				if not parent then
					return false, p
				end
				if not parent.items then
					return false, p
				end
				parent.items[name] = parent.items[name] or {items={}}
				return true
			end
			if method == "open" then
				local p, m = ...
				m = m or "r"
				if ramfs.readonly and m ~= "r" then
					return nil, "readonly"
				end
				local n = processPath(ramfs, p)
				if m == "r" and not n then return nil, p end
				if not n then
					if ramfs.readonly then
						return nil, "readonly"
					end
					n = {
						fileData = "",
					}
					local parent, name = processParentPath(ramfs, p)
					if not parent then
						return nil, p
					end
					if not parent.items then
						return nil, p
					end
					parent.items[name] = n
				end
				if not n.fileData then return nil, "is a directory" end
				local fd = #ramfs.fds+1
				ramfs.fds[fd] = {
					mode = m,
					offset = m == "a" and #n.fileData or 0,
					node = n,
				}
				if m == "w" then
					n.fileData = ""
				end
				return fd
			end
			if method == "write" then
				local fd, data = ...
				local f = ramfs.fds[fd]
				if not f then return false, "bad file" end
				if f.mode == "r" then return false, "bad file" end
				local buf = f.node.fileData or ""
				if f.mode == "a" then f.offset = #buf end
				buf = buf:sub(1, f.offset) .. data .. buf:sub(f.offset+#data)
				f.node.fileData = buf
				f.offset = f.offset + #data
				return true
			end
			if method == "read" then
				local fd, len = ...
				local f = ramfs.fds[fd]
				if not f then return nil, "bad file" end
				if f.mode ~= "r" then return nil, "bad file" end
				local buf = f.node.fileData or ""
				len = len or math.min(#buf - f.offset)
				if f.offset >= #buf then
					return
				end
				local chunk = buf:sub(f.offset+1, f.offset+len)
				f.offset = f.offset + #chunk
				return chunk
			end
			if method == "close" then
				ramfs.fds[(...)] = nil
				return
			end
		end,
	}
end
