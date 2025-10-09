--!lua

local function forkbomb()
	k.sleep(0.05)
	local a = assert(k.fork(forkbomb))
	local b = assert(k.fork(forkbomb))
	k.waitpid(a)
	k.waitpid(b)
end

forkbomb()
