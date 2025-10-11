local keyboard = require("keyboard")
local terminal = require("terminal")

---@param fd? integer
---@param outfd? integer
---@param hidden? string 
--- If hidden is nil, input is shown as normal.
--- If hidden is an empty string, no text is printed (except newlines and Ctrl-D or Ctrl-C)
--- If hidden is a non-empty string, every character is replaced with hidden.
return function(fd, outfd, hidden)
	fd = fd or terminal.STDIN
	outfd = outfd or terminal.STDOUT
	-- this function executes in the context of the current process
	local buf = ""
	local term = terminal.wrap(fd, outfd)
	term:showCursor()
	local ex, ey = term:getCursor()
	local cursor = 0
	local function hiddenText(text)
		if hidden then
			if #hidden == 0 then return hidden end
			return text:gsub(".", hidden)
		end
		return text
	end
	local function graphics()
		return hidden ~= ""
	end
	while true do
		---@type string?
		local ev, _, char, code = term:pullUntilEvent(true)
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
			term:write(hiddenText(pasted))
		end
		if ev == "interrupted" then
			-- SIGINT
			term:write(hiddenText("^C"))
			term:hideCursor()
			return
		end
		if ev == "key_down" then
			if char == 3 then
				-- SIGINT
				term:write(hiddenText"^C", "\n")
				term:hideCursor()
				return
			elseif char == 4 then
				-- closing stdin
				term:write(hiddenText"^D", "\n")
				term:hideCursor()
				return
			elseif code == keyboard.keys.enter then
				term:write("\n")
				term:hideCursor()
				return buf .. "\n"
			elseif code == keyboard.keys.back then
				if cursor > 0 then
					if graphics() then
						term:write("\b")
						term:clearScreenAfterCursor()
						term:saveCursor()
						term:write(buf:sub(cursor+1))
						term:restoreCursor()
					end
					buf = buf:sub(1, cursor-1) .. buf:sub(cursor+1)
					cursor = cursor - 1
				end
			elseif code == keyboard.keys.delete then
				if cursor < #buf then
					if graphics() then
						term:saveCursor()
						term:write(buf:sub(cursor+2))
						term:write(" ")
						term:restoreCursor()
					end
					buf = buf:sub(1, cursor) .. buf:sub(cursor+2)
				end
			elseif code == keyboard.keys.home then
				cursor = 0
				term:setCursor(ex, ey)
			elseif code == keyboard.keys["end"] then
				term:write(buf:sub(cursor+1))
				cursor = #buf
			elseif code == keyboard.keys.left then
				if cursor > 0 then
					cursor = cursor - 1
					term:setCursor(ex, ey)
					term:write(buf:sub(1, cursor))
					term:showCursor()
				end
			elseif code == keyboard.keys.right then
				if cursor < #buf then
					cursor = cursor + 1
					term:write(buf:sub(cursor, cursor))
					term:showCursor()
				end
			elseif keyboard.isPrintable(char) then
				-- TODO: ANSI escapes and stuff
				local c = string.char(char)
				if cursor >= #buf then
					-- super easy
					buf = buf .. c
					term:write(hiddenText(c))
					cursor = cursor + 1
				else
					-- shit got good here
					buf = buf:sub(1, cursor) .. c .. buf:sub(cursor+1)
					-- <before><cursor><after>
					cursor = cursor + 1
					term:write(hiddenText(c))
					term:saveCursor()
					term:write(hiddenText(buf:sub(cursor+1)))
					term:restoreCursor()
				end
			end
		end
	end
end
