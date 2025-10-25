-- Chacha20 encryption
-- Based off https://github.com/marcizhu/ChaCha20/blob/master/ChaCha20.h

local chacha20 = {}

-- the size of the encryption key, the most important part
chacha20.KEY_SIZE = 32
-- the nonce, similar to an IV, but better
chacha20.NONCE_SIZE = 12
-- we encrypt 64 bytes at once with magic
chacha20.BLOCK_SIZE = 64
chacha20.CONSTANT = "expand 32-byte k"

---@class chacha20.ctx
---@field state integer[]
---@field idx integer

---@param a integer
local function mk32bit(a)
	return math.floor(a) % (2^32)
end

chacha20.mk32bit = mk32bit

---@param s string
---@param i? integer
---@return integer
function chacha20.pack4(s, i)
	i = i or 1
	local a, b, c, d = s:byte(i, i+3)
	return a + b * 256 + c * 256 * 256 + d * 256 * 256 * 256
end

---@param i integer
---@return integer, integer, integer, integer
function chacha20.unpack4(i)
	local a = i % 256
	local b = math.floor(i / 256) % 256
	local c = math.floor(i / 256 / 256) % 256
	local d = math.floor(i / 256 / 256 / 256) % 256
	return a, b, c, d
end

---@param x integer
---@param n integer
function chacha20.rotl(x, n)
	return mk32bit((x << n) | (x >> (32 - n)))
end

---@param buf integer[]
---@param a integer
---@param b integer
---@param c integer
---@param d integer
function chacha20.qr(buf, a, b, c, d)
	buf[a] = mk32bit(buf[a] + buf[b])
	buf[d] = mk32bit(buf[d] ~ buf[a])
	buf[d] = chacha20.rotl(buf[d], 16)

	buf[c] = mk32bit(buf[c] + buf[d])
	buf[b] = mk32bit(buf[b] ~ buf[c])
	buf[b] = chacha20.rotl(buf[b], 12)

	buf[a] = mk32bit(buf[a] + buf[b])
	buf[d] = mk32bit(buf[d] ~ buf[a])
	buf[d] = chacha20.rotl(buf[d], 8)

	buf[c] = mk32bit(buf[c] + buf[d])
	buf[b] = mk32bit(buf[b] ~ buf[c])
	buf[b] = chacha20.rotl(buf[b], 7)
end

---@param key string
---@param nonce string
---@param count integer
function chacha20.init(key, nonce, count)
	---@type integer[]
	local state = {}
	state[0] = chacha20.pack4(chacha20.CONSTANT, 1)
	state[1] = chacha20.pack4(chacha20.CONSTANT, 5)
	state[2] = chacha20.pack4(chacha20.CONSTANT, 9)
	state[3] = chacha20.pack4(chacha20.CONSTANT, 13)
	state[4] = chacha20.pack4(key, 1)
	state[5] = chacha20.pack4(key, 5)
	state[6] = chacha20.pack4(key, 9)
	state[7] = chacha20.pack4(key, 13)
	state[8] = chacha20.pack4(key, 17)
	state[9] = chacha20.pack4(key, 21)
	state[10] = chacha20.pack4(key, 25)
	state[11] = chacha20.pack4(key, 29)
	state[12] = count
	state[13] = chacha20.pack4(nonce, 1)
	state[14] = chacha20.pack4(nonce, 5)
	state[15] = chacha20.pack4(nonce, 9)
	---@type chacha20.ctx
	return {
		state = state,
		idx = 0,
	}
end

---@param inData integer[]
---@param outData integer[]
function chacha20.block_next(inData, outData)
	for i=1,16 do
		outData[i-1] = inData[i-1]
	end
	-- 10 pairs of 2 rounds
	for _=1,10 do
		-- Columns are easy
		for i=0,3 do
			chacha20.qr(outData, i, i+4, i+8, i+12)
		end
		-- Didn't bother figuring out diagonals
		chacha20.qr(outData, 0, 5, 10, 15)
		chacha20.qr(outData, 1, 6, 11, 12)
		chacha20.qr(outData, 2, 7, 8, 13)
		chacha20.qr(outData, 3, 4, 9, 14)
	end

	for i=1,16 do
		outData[i-1] = mk32bit(outData[i-1] + inData[i-1])
	end
end

---@param ctx chacha20.ctx
---@param buffer string
---@return string
function chacha20.xor(ctx, buffer)
	---@type integer[]
	local keystream = {}
	local dataStuff = {}
	for i=1,#buffer/4 do
		dataStuff[i] = chacha20.pack4(buffer, i*4-3)
	end

	local stuffsPerStuff = chacha20.BLOCK_SIZE / 4

	for i=1,#dataStuff,stuffsPerStuff do
		chacha20.block_next(ctx.state, keystream)

		for j=1,stuffsPerStuff do
			dataStuff[i+j-1] = dataStuff[i+j-1] ~ keystream[j-1]
		end
	end

	local t = {}
	for i=1,#dataStuff do
		table.insert(t, string.char(chacha20.unpack4(dataStuff[i])))
	end
	return table.concat(t)
end

---@param buffer string
---@param key string
---@param nonce string
---@param count? integer
function chacha20.encryptOrDecrypt(buffer, key, nonce, count)
	count = count or 1 -- seems to work just fine

	local ctx = chacha20.init(key, nonce, count)
	return chacha20.xor(ctx, buffer)
end

---@param buffer string
---@param key string
---@param nonce string
---@param count? integer
function chacha20.encryptOrDecryptPadded(buffer, key, nonce, count)
	local pkcs7 = require("pkcs7")
	buffer = pkcs7.addPadding(buffer, chacha20.BLOCK_SIZE)
	count = count or 1 -- seems to work just fine

	local ctx = chacha20.init(key, nonce, count)
	buffer = chacha20.xor(ctx, buffer)
	return pkcs7.removePadding(buffer)
end

return chacha20
