--!lua

local args = {...}

---@type string[]
local calls = {}

while args[1] do
	local first = args[1]
	if first:sub(1, 2) == "--" then
		table.remove(args, 1)
		if first == "--type" then
			table.insert(calls, "type")
		elseif first == "--address" then
			table.insert(calls, "address")
		elseif first == "--slot" then
			table.insert(calls, "slot")
		elseif first == "--blocksize" then
			table.insert(calls, "blocksize")
		elseif first == "--repartition" then
			table.insert(calls, "repartition")
		elseif first == "--methods" then
			table.insert(calls, "methods")
		elseif first == "--fields" then
			table.insert(calls, "fields")
		elseif first == "--label" then
			table.insert(calls, "getLabel")
		elseif first == "--field" then
			local opt = assert(table.remove(args, 1), "unspecified option")
			table.insert(calls, opt)
		else
			io.stderr:write("unknown option: ", first, "\n")
			return 1
		end
	else
		break
	end
end

local failed = 0
for _, dev in ipairs(args) do
	if #args > 1 then
		print(dev .. ":")
	end
	local fd = assert(k.open(dev, "r"))
	for _, call in ipairs(calls) do
		local pref = ""
		if #calls > 1 then
			pref = call .. ": "
		end
		local val, err = k.ioctl(fd, call)
		if err then
			io.stderr:write(pref, "error: ", err, "\n")
			failed = failed + 1
		else
			if type(val) == "table" then
				io.stdout:write(pref, table.serialize(val), "\n")
			else
				io.stdout:write(pref, val, "\n")
			end
		end
	end
	k.close(fd)
end
return failed
