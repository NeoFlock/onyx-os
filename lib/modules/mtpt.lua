-- Minitel Partition Table support
-- https://git.shadowkat.net/izaya/OC-misc/src/branch/master/partition

---@type Kocos.module
return function(req, ...)
	if req == "dkms_init" then
		Kocos.refetchPartitions()
		return
	end
	if req == "FS-partition" then
		---@type Kocos.dev
		local dev = ...
		local drive, err = Kocos.virtualDriveFrom(dev)
		if not drive then return nil, err end
		local sectorSize = drive.getSectorSize()
		local lastSector = drive.readSector(math.floor(drive.getCapacity() / sectorSize))
		if not lastSector then return nil, Kocos.EHWPOISON end
		if lastSector:sub(21, 24) ~= "mtpt" then return end
		local partsInSector = math.floor(sectorSize / 32)
		local parts = {}
		local idx = 0
		for i=2,partsInSector do
			local off = (i - 1) * 32
			local chunk = lastSector:sub(off+1, off+32)
			local name = chunk:sub(1, 20):gsub("\0", "")
			local type = chunk:sub(21, 24)
			local start = string.tonumBE(chunk:sub(25, 28))
			local len = string.tonumBE(chunk:sub(29, 32))
			if name ~= "" then
				idx = idx + 1
				local addr = "P" .. i .. "-" .. drive.address
				Kocos.addDrivePartition(addr, drive, name, idx, start - 1, len, type, 0)
				table.insert(parts, addr)
			end
		end
		return parts
	end
end
