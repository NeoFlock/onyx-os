--!lua

while true do
	local buf = ""
	for _=1,4096 do
		buf = buf .. string.char(math.random(0, 255))
	end
	k.write(1, buf)
	coroutine.yield()
end
