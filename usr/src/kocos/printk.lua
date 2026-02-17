Kocos.L_DEBUG = 0
Kocos.L_INFO = 1
Kocos.L_AUTOFIX = 2
Kocos.L_WARN = 3
Kocos.L_ERROR = 4
Kocos.L_PANIC = 5
Kocos.L_RAWTEXT = 6

local oc = component.list("ocelot")()
local serial = component.list("serial")()

local gpu, screen = component.list("gpu")(), component.list("screen")()
if gpu and screen then
	component.invoke(gpu, "bind", screen)
end
local currentY = 0

function Kocos.clearscr()
	if not gpu then return end
	local w, h = component.invoke(gpu, "getResolution")
	component.invoke(gpu, "fill", 1, 1, w, h, " ")
	gpu = nil
	screen = nil
end

function Kocos.setprintcolor(clr)
	if gpu then
		component.invoke(gpu, "setForeground", clr)
	end
end

function Kocos.printk(severity, msg)
	local uptime = computer.uptime()

	Kocos.event.notifyListeners("kocos_log", uptime, severity, msg)

	if Kocos.args.minLog then
		if severity < Kocos.args.minLog then return end
	end

	local names = {
		[Kocos.L_DEBUG] = "DEBUG",
		[Kocos.L_INFO] = "INFO",
		[Kocos.L_AUTOFIX] = "AUTOFIX",
		[Kocos.L_WARN] = "WARN",
		[Kocos.L_ERROR] = "ERROR",
		[Kocos.L_PANIC] = "PANIC",
	}

	local rawText = severity == Kocos.L_RAWTEXT and msg or string.format("[%5.3f %s] %s", uptime, names[severity] or "UNKNOWN", msg)
	if oc then
		component.invoke(oc, "log", rawText)
	end
	if serial then
		component.invoke(serial, "write", rawText .. "\n")
	end
	if gpu and screen and not Kocos.disableScreen then
		local w, h = component.invoke(gpu, "getResolution")

		currentY = currentY + 1
		while currentY >= h do
			component.invoke(gpu, "copy", 1, 1, w, h-1, 0, -1)
			component.invoke(gpu, "fill", 1, currentY, w, 1, " ")
			currentY = currentY - 1
		end
		component.invoke(gpu, "set", 1, currentY, rawText)
	end

	if severity == Kocos.L_PANIC then
		if Kocos.disableDefaultPanicHandler then
			Kocos.event.notifyListeners("kocos_panic", uptime, msg)
			return
		end
		pcall(Kocos.event.pull, 5)
		computer.shutdown(true)
	end
end

function Kocos.printkf(severity, fmt, ...)
	Kocos.printk(severity, string.format(fmt, ...))
end

function Kocos.panick(msg)
	Kocos.printk(Kocos.L_PANIC, msg)
end

function Kocos.panickf(fmt, ...)
	Kocos.panick(string.format(fmt, ...))
end

Kocos.printk(Kocos.L_DEBUG, "printk loaded")
