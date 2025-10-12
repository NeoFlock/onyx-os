--!lua

local url, file = ...

assert(url, "no url")

local s = assert(k.socket("AF_INET", "", "http"))
assert(k.connect(s, {address = url, port = 0}))
if file then
	if not k.exists(file) then
		assert(k.touch(file, 2^16-1))
	end
	local f = assert(k.open(file, "w"))
	local lastRead = k.uptime()
	local lastBuf = 0
	while true do
		local buf, err = k.read(s, math.huge)
		if err then error(err) end
		if not buf then break end
		lastBuf = lastBuf + #buf
		local now = k.uptime()
		if now - lastRead >= 0.1 then
			local delta = now - lastRead
			lastRead = now
			k.write(1, string.format("\r\x1b[0K%s / s", string.memformat(lastBuf / delta)))
			lastBuf = 0
		end
		assert(k.write(f, buf))
	end
	k.write(1, "\r\x1b[0K")
	k.close(f)
else
	while true do
		local buf, err = k.read(s, math.huge)
		if err then error(err) end
		if not buf then break end
		assert(k.write(1, buf))
	end
end
k.close(s)
