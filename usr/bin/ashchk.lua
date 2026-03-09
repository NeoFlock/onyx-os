--!lua
-- Check stuff with libash

local ash = require("libash")

local args = {...}

if args[1] == "lex" then
	for i=2,#args do
		local f = args[i]
		local data = assert(readfile(f))
		print("For", f)
		local toks, err, loc = ash.lex(data)
		if not toks then
			assert(err)
			assert(loc)
			print(string.format("error: %s:%d:%s", f, ash.lineOfOffset(data, loc), err))
			return 1
		end
		for _, tok in ipairs(toks) do
			print(tok.tt, #tok.data, tok.data)
		end
	end
	return 0
end
if args[1] == "parse" then
	for i=2,#args do
		local f = args[i]
		local data = assert(readfile(f))
		print("For", f)
		local nodes, err, loc = ash.parse(data)
		if not nodes then
			assert(err)
			assert(loc)
			print(string.format("error: %s:%d:%s", f, ash.lineOfOffset(data, loc), err))
			return 1
		end
		print(table.serialize(nodes))
	end
	return 0
end
print("Unknown action:", args[1])
return 1
