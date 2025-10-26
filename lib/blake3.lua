-- Blake 3 hashing
-- based off https://github.com/oconnor663/blake3_reference_impl_c/blob/main/reference_impl.c

local blake3 = {}

blake3.IV = {
	0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A, 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19
}

blake3.MSG_PERMUTATION = {
	2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8
}

blake3.OUT_LEN = 32
blake3.KEY_LEN = 32
blake3.BLOCK_LEN = 64
blake3.CHUNK_LEN = 1024

blake3.CHUNK_START = 1
blake3.CHUNK_END = 2
blake3.PARENT = 4
blake3.ROOT = 8
blake3.KEYED_HASH = 16
blake3.DERIVE_KEY_CONTEXT = 32
blake3.DERIVE_KEY_MATERIAL = 64

---@param x integer
function blake3.mk32bit(x)
	return x % (2^32)
end

---@param x integer
---@param n integer
function blake3.rotateRight(x, n)
	return blake3.mk32bit((x >> n) | (x << (32 - n)))
end

--- the magic g function
---@param buf integer[]
---@param a integer
---@param b integer
---@param c integer
---@param d integer
---@param mx integer
---@param my integer
function blake3.g(buf, a, b, c, d, mx, my)
	buf[a] = blake3.mk32bit(buf[a] + buf[b] + mx)
	buf[d] = blake3.rotateRight(buf[d] ~ buf[a], 16)
	buf[c] = blake3.mk32bit(buf[c] + buf[d])
	buf[b] = blake3.rotateRight(buf[b] ~ buf[c], 12)

	buf[a] = blake3.mk32bit(buf[a] + buf[b] + my)
	buf[d] = blake3.rotateRight(buf[d] ~ buf[a], 8)
	buf[c] = blake3.mk32bit(buf[c] + buf[d])
	buf[b] = blake3.rotateRight(buf[b] ~ buf[c], 7)
end

---@param state integer[]
---@param m integer[]
function blake3.round(state, m)
	blake3.g(state,1,5,9,13,m[1],m[2])
	blake3.g(state,2,6,10,14,m[3],m[4])
	blake3.g(state,3,7,11,15,m[5],m[6])
	blake3.g(state,4,8,12,16,m[7],m[8])

	-- diagionals
	blake3.g(state,1,6,11,16,m[9],m[10])
	blake3.g(state,2,7,12,13,m[11],m[12])
	blake3.g(state,3,8,9,14,m[13],m[14])
	blake3.g(state,4,5,10,15,m[15],m[16])
end

---@param m integer[]
---@return integer[]
function blake3.permute(m)
	local permuted = {}
	for i=1,16 do
		permuted[i] = m[blake3.MSG_PERMUTATION[i] + 1]
	end
	return permuted
end

---@return integer[]
function blake3.compress(chainingValue, blockWords, counter, blockLen, flags)
	local counterLow = blake3.mk32bit(counter)
	local counterHigh = blake3.mk32bit(counter >> 32)

	local state = {
		chainingValue[1],
		chainingValue[2],
		chainingValue[3],
		chainingValue[4],
		chainingValue[5],
		chainingValue[6],
		chainingValue[7],
		chainingValue[8],
		blake3.IV[1],
		blake3.IV[2],
		blake3.IV[3],
		blake3.IV[4],
		counterLow,
		counterHigh,
		blockLen,
		flags,
	}

	for _=1,7 do
		blake3.round(state, blockWords)
		blockWords = blake3.permute(blockWords)
	end

	for i=1,8 do
		state[i] = state[i] ~ state[i+8]
		state[i+8] = state[i+8] ~ chainingValue[i]
	end
	return state
end

---@param bytes string
---@param len integer
---@return integer[]
function blake3.wordsFromLEBytes(bytes, len)
	local words = {}
	for i=1,#bytes, 4 do
		local a, b, c, d = bytes:byte(i, i+3)
		a = a or 0
		b = b or 0
		c = c or 0
		d = d or 0
		local w = a + b * 256 + c * 256 * 256 + d * 256 * 256 * 256
		table.insert(words, w)
	end
	while #words < len do table.insert(words, 0) end
	return words
end

---@class blake3.output
---@field inputChainingValue integer[]
---@field blockWords integer[]
---@field counter integer
---@field blockLen integer
---@field flags integer

local output = {}

---@param self blake3.output
---@return integer[]
function output.chainingValue(self)
	local compressed = blake3.compress(self.inputChainingValue, self.blockWords, self.counter, self.blockLen, self.flags)
	for i=9,#compressed do compressed[i] = nil end
	assert(#compressed == 8)
	return compressed
end

---@param self blake3.output
---@param out string[]
---@param outLen integer
function output.rootBytes(self, out, outLen)
	local counter = 0
	local off = 1
	while outLen > 0 do
		local words = blake3.compress(self.inputChainingValue, self.blockWords, counter, self.blockLen, self.flags | blake3.ROOT)
		for word=1,16 do
			for byte=0, 3 do
				if outLen == 0 then return end
				out[off] = string.char((words[word] >> (8 * byte)) % 256)
				off = off + 1
				outLen = outLen - 1
			end
		end
		counter = counter + 1
	end
end

---@class blake3.chunkstate
---@field chainingValue integer[]
---@field chunkCounter integer
---@field block string
---@field blocksCompressed integer
---@field flags integer

local chunkstate = {}

function chunkstate.init(keyWords, counter, flags)
	assert(#keyWords == 8)
	---@type blake3.chunkstate
	return {
		chainingValue = table.copy(keyWords),
		chunkCounter = counter,
		block = "",
		blocksCompressed = 0,
		flags = flags,
	}
end

---@param self blake3.chunkstate
function chunkstate.len(self)
	return self.blocksCompressed * blake3.BLOCK_LEN + #self.block
end

---@param self blake3.chunkstate
function chunkstate.startflag(self)
	return (self.blocksCompressed == 0) and blake3.CHUNK_START or 0
end

---@param self blake3.chunkstate
---@param input string
function chunkstate.update(self, input)
	while #input > 0 do
		if #self.block == blake3.BLOCK_LEN then
			local blockWords = blake3.wordsFromLEBytes(self.block, 16)
			local out16 = blake3.compress(self.chainingValue, blockWords, self.chunkCounter, blake3.BLOCK_LEN, self.flags | chunkstate.startflag(self))
			self.chainingValue = out16
			self.blocksCompressed = self.blocksCompressed + 1
			self.block = ""
		end

		local want = blake3.BLOCK_LEN - #self.block
		local take = math.min(want, #input)
		self.block = self.block .. input:sub(1, take)
		input = input:sub(take+1)
	end
end

---@param self blake3.chunkstate
function chunkstate.output(self)
	---@type blake3.output
	return {
		inputChainingValue = table.copy(self.chainingValue),
		blockWords = blake3.wordsFromLEBytes(self.block, 16),
		counter = self.chunkCounter,
		blockLen = blake3.mk32bit(#self.block),
		flags = self.flags | chunkstate.startflag(self) | blake3.CHUNK_END,
	}
end

---@param leftChildPV integer[]
---@param rightChildPV integer[]
---@param keywords integer[]
---@param flags integer
local function parent_output(leftChildPV, rightChildPV, keywords, flags)
	---@return integer[]
	local blockWords = {}
	for i=1,8 do
		blockWords[i] = leftChildPV[i]
		blockWords[i+8] = rightChildPV[i]
	end
	---@type blake3.output
	return {
		inputChainingValue = table.copy(keywords),
		blockWords = table.copy(blockWords),
		counter = 0,
		blockLen = blake3.BLOCK_LEN,
		flags = blake3.PARENT | flags,
	}
end

---@param leftChildPV integer[]
---@param rightChildPV integer[]
---@param keywords integer[]
---@param flags integer
local function parent_cv(leftChildPV, rightChildPV, keywords, flags)
	return output.chainingValue(parent_output(leftChildPV, rightChildPV, keywords, flags))
end

---@class blake3.hasher
---@field chunkState blake3.chunkstate
---@field keywords integer[]
---@field cvStack integer[][]
---@field flags integer

function blake3.newRawHasher(keywords, flags)
	---@return blake3.hasher
	return {
		chunkState = chunkstate.init(keywords, 0, flags),
		keywords = table.copy(keywords),
		cvStack = {},
		flags = flags,
	}
end

function blake3.newHasher()
	return blake3.newRawHasher(blake3.IV, 0)
end

---@param key string
function blake3.newKeyedHasher(key)
	assert(#key == blake3.KEY_LEN, "bad key")
	return blake3.newRawHasher(blake3.wordsFromLEBytes(key, 8), blake3.KEYED_HASH)
end

---@param hasher blake3.hasher
---@param cv integer[]
---@param totalChunks integer
function blake3.addChunkCV(hasher, cv, totalChunks)
	while totalChunks % 2 == 0 do
		local child = table.remove(hasher.cvStack)
		cv = parent_cv(child, table.copy(cv), hasher.keywords, hasher.flags)
		totalChunks = totalChunks / 2
	end
	table.insert(hasher.cvStack, cv)
end

---@param hasher blake3.hasher
---@param input string
function blake3.update(hasher, input)
	while #input > 0 do
		if chunkstate.len(hasher.chunkState) == blake3.CHUNK_LEN then
			local chunkOutput = chunkstate.output(hasher.chunkState)
			local cv = output.chainingValue(chunkOutput)
			local totalChunks = hasher.chunkState.chunkCounter + 1
			blake3.addChunkCV(hasher, cv, totalChunks)
			hasher.chunkState = chunkstate.init(hasher.keywords, totalChunks, hasher.flags)
		end

		local want = blake3.CHUNK_LEN - chunkstate.len(hasher.chunkState)
		local take = math.min(want, #input)
		chunkstate.update(hasher.chunkState, input:sub(1, take))
		input = input:sub(take+1)
	end
end

---@param hasher blake3.hasher
---@param len? integer
function blake3.finalize(hasher, len)
	len = len or blake3.OUT_LEN
	local curOutput = chunkstate.output(hasher.chunkState)
	local parentsLeft = #hasher.cvStack
	while parentsLeft > 0 do
		local currentCV = output.chainingValue(curOutput)
		curOutput = parent_output(hasher.cvStack[parentsLeft], currentCV, hasher.keywords, hasher.flags)
		parentsLeft = parentsLeft - 1
	end
	local buf = {}
	output.rootBytes(curOutput, buf, len)
	return table.concat(buf)
end

---@param s string
---@param key? string
---@param len? integer
function blake3.hash(s, key, len)
	local hasher = key and blake3.newKeyedHasher(key) or blake3.newHasher()
	blake3.update(hasher, s)
	return blake3.finalize(hasher, len)
end

return blake3
