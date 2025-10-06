local keyboard = require("keyboard")

return function()
	-- this function executes in the context of the current process

	local buf = ""
	while true do
		---@type string?
		local c = syscall("read", 0, 1)
		if not c then return end
		if c == "\r" or c == "\n" then
			syscall("write", 1, "\n")
			return buf .. "\n"
		elseif c == "\b" then
			syscall("write", 1, "\b")
			buf = buf:sub(1, -2)
		elseif c:byte() == 3 then
			-- SIGINT
			syscall("write", 1, "^C")
			error("interrupted") -- TODO: use signal
		elseif c:byte() == 4 then
			-- closing stdin
			syscall("write", 0, "^D")
			return
		elseif #c > 0 then
			-- TODO: ANSI escapes and stuff
			buf = buf .. c
			syscall("write", 1, c)
		end
		coroutine.yield() -- actually allow OS to process events
	end
end
