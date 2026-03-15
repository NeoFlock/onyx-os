--!lua

for _, mod in ipairs({...}) do
	assert(syscalls.dkms_unload(mod))
end
return 0
