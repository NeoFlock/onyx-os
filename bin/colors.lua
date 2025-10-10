--!lua

for i=0, 15 do
	k.write(1, "\x1b[48;5;" .. i .. "m  \x1b[0m")
	if i == 7 then
		k.write(1, "\n")
	end
end
k.write(1, "\n")
