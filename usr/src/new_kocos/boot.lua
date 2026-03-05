Kocos.printk(Kocos.L_INFO, "Booting...")

while true do
	Kocos.tickProcesses()
	local e = {Kocos.pull(0.05)}
	if e[1] then
		Kocos.printkf(Kocos.L_INFO, "ev: %s", table.concat(e, " "))
	end
end
