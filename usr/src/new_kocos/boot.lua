Kocos.printk(Kocos.L_INFO, "Booting...")

while true do
	local e = {Kocos.pull(5)}
	Kocos.printkf(Kocos.L_INFO, "ev: %s", table.concat(e, " "))
end
