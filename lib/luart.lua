-- TODO: use io once it is made
function print(...)
	assert(syscall("write", 1, table.concat({...}, " ") .. "\n"))
end
