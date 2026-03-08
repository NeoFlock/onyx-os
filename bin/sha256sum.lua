--!lua

local sha256 = require("sha256")
local hex = require("hex")

local files = {...}

for _, file in ipairs(files) do
	local data, err = readfile(file)
	if not data then
		io.ewrite(file, ": ", err, "\n")
		return 1
	end
	local digest = sha256(data)
	print(hex.dump(digest), file)
end
