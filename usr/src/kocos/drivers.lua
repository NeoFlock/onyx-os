-- KOCOS drivers are simple functions
-- They are effectively request handlers
-- This is to minimize memory usage

---@type function[]
Kocos.drivers = {}

function Kocos.addDriver(driver)
	table.insert(Kocos.drivers, 1, driver)
	Kocos.event.notifyListeners("driver_added", driver)
end

function Kocos.removeDriver(driver)
	for i=#Kocos.drivers,1, -1 do
		if Kocos.drivers[i] == driver then
			table.remove(Kocos.drivers, i)
		end
	end
	Kocos.event.notifyListeners("driver_removed", driver)
end

Kocos.printk(Kocos.L_DEBUG, "driver system loaded")
