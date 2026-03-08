-- Credit to Blendi Goose, who wrote this a while back

local sha256_block = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
}

local function sha256_preprocess(input)
	local len = #input
	local bitlen = len * 8 -- whoah no way
	input = input .. '\128' -- wtf sha

	local padc = 64 - ((len + 9) % 64)
	if padc ~= 64 then
		input = input .. string.rep("\0", padc)
	end

	-- now for some really really bad code (on purpose)
	input = input .. string.char(
		bitlen >> 56 & 0xFF,
		bitlen >> 48 & 0xFF,
		bitlen >> 40 & 0xFF,
		bitlen >> 32 & 0xFF,
		bitlen >> 24 & 0xFF,
		bitlen >> 16 & 0xFF,
		bitlen >> 8 & 0xFF,
		bitlen & 0xFF
	)

	return input
end

local function sha256_ror(x, y)
  return ((x >> y) | (x << (32 - y))) & 0xFFFFFFFF
end

local function sha256_processChunk(chunk, hash)
	local w = {}

	for i = 1, 64 do
		if i <= 16 then
			w[i] = string.byte(chunk, (i - 1) * 4 + 1) << 24 |
			string.byte(chunk, (i - 1) * 4 + 2) << 16 |
			string.byte(chunk, (i - 1) * 4 + 3) << 8 |
			string.byte(chunk, (i - 1) * 4 + 4)
		else
			local s0 = sha256_ror(w[i - 15], 7) ~ sha256_ror(w[i - 15], 18) ~ (w[i - 15] >> 3)
			local s1 = sha256_ror(w[i - 2], 17) ~ sha256_ror(w[i - 2], 19) ~ (w[i - 2] >> 10)
			w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xFFFFFFFF
		end
	end

	local a, b, c, d, e, f, g, h = table.unpack(hash)

	for i = 1, 64 do
		local s1 = sha256_ror(e, 6) ~ sha256_ror(e, 11) ~ sha256_ror(e, 25)
		local ch = (e & f) ~ ((~e) & g)
		local temp1 = (h + s1 + ch + sha256_block[i] + w[i]) & 0xFFFFFFFF
		local s0 = sha256_ror(a, 2) ~ sha256_ror(a, 13) ~ sha256_ror(a, 22)
		local maj = (a & b) ~ (a & c) ~ (b & c)
		local temp2 = (s0 + maj) & 0xFFFFFFFF

		h = g
		g = f
		f = e
		e = (d + temp1) & 0xFFFFFFFF
		d = c
		c = b
		b = a
		a = (temp1 + temp2) & 0xFFFFFFFF
	end

	hash[1] = (hash[1] + a) & 0xFFFFFFFF
	hash[2] = (hash[2] + b) & 0xFFFFFFFF
	hash[3] = (hash[3] + c) & 0xFFFFFFFF
	hash[4] = (hash[4] + d) & 0xFFFFFFFF
	hash[5] = (hash[5] + e) & 0xFFFFFFFF
	hash[6] = (hash[6] + f) & 0xFFFFFFFF
	hash[7] = (hash[7] + g) & 0xFFFFFFFF
	hash[8] = (hash[8] + h) & 0xFFFFFFFF
end

---@param message string
---@return string
return function(message)
	message = sha256_preprocess(message)

	local hash = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19} -- sha shenanigans
	for i = 1,#message, 64 do
		sha256_processChunk(message:sub(i, i+63), hash)
	end

	local result = ""
	for i = 1,8 do
		local part = hash[i]
		result = result .. string.char(part >> 24) .. string.char((part >> 16) & 0xff) .. string.char((part >> 8) & 0xff) .. string.char(part & 0xff)
	end

	return result
end
