local keyboard = require("keyboard")
local terminal = require("terminal")

---@param fd? integer
---@param outfd? integer
---@param hidden? string 
--- If hidden is nil, input is shown as normal.
--- If hidden is an empty string, no text is printed (except newlines and Ctrl-D or Ctrl-C)
--- If hidden is a non-empty string, every character is replaced with hidden.
return function(fd, outfd, hidden)
	fd = fd or 0
	outfd = outfd or 1
	-- this function executes in the context of the current process
	local buf = ""
	local term = terminal.wrap(fd)
	k.write(outfd, "\x1b[?25h")
	while true do
		---@type string?
		local ev, _, char, code = term:pull()
		if not ev then
			term:process()
		end
		if ev == "clipboard" then
			local pasted = string.gsub(code, ".", {
				-- erase the problematics
				["\r"] = " ",
				["\n"] = " ",
				["\x1b"] = " ",
				["\a"] = " ",
				["\b"] = " ",
				["\f"] = " ",
				["\v"] = " ",
				["\t"] = " ",
			})
			buf = buf .. pasted
			if hidden then
				if #hidden > 0 then
					k.write(outfd, pasted:gsub(".", hidden))
				end
			else
				k.write(outfd, pasted)
			end
		end
		if ev == "key_down" then
			if char == 3 then
				-- SIGINT
				k.write(outfd, "^C")
				k.write(outfd, "\x1b[?25l")
				error("interrupted") -- TODO: use signal
			elseif char == 4 then
				-- closing stdin
				k.write(outfd, "^D\n")
				k.write(outfd, "\x1b[?25l")
				return
			elseif code == keyboard.keys.enter then
				k.write(outfd, "\n")
				k.write(outfd, "\x1b[?25l")
				return buf .. "\n"
			elseif code == keyboard.keys.back then
				if #buf > 0 then
					if (not hidden) or (#hidden > 0) then
						k.write(outfd, "\b")
					end
					buf = buf:sub(1, -2)
				end
			elseif keyboard.isPrintable(char) then
				-- TODO: ANSI escapes and stuff
				local c = string.char(char)
				buf = buf .. c
				if hidden then
					if #hidden > 0 then
						k.write(outfd, hidden)
					end
				else
					k.write(outfd, c)
				end
			end
		end
		coroutine.yield() -- actually allow OS to process events
	end
end
