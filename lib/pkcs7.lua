-- PKCS#7 padding

local pkcs7 = {}

---@param data string
---@param blockSize integer
function pkcs7.addPadding(data, blockSize)
	local added = blockSize - (#data % blockSize)
	return data .. string.rep(string.char(added), added)
end

---@param data string
function pkcs7.removePadding(data)
	local added = data:byte(#data)
	return data:sub(1, -added - 1)
end

return pkcs7
