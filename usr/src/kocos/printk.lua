Kocos.L_DEBUG = 0
Kocos.L_INFO = 1
Kocos.L_AUTOFIX = 2
Kocos.L_WARN = 3
Kocos.L_ERROR = 4
Kocos.L_PANIC = 5

local oc = component.list("ocelot")()

---@param text string
function Kocos.scr_write(text)
	-- No screen available
end

---@return string?
function Kocos.scr_read()
	return nil -- no input source available
end

function Kocos._scr_reader(...)
	-- nothing to react to
end

---@return string[]
function Kocos.scr_addrs()
	return {}
end

local gpu, screen = component.list("gpu")(), component.list("screen")()

if gpu and screen then
	component.invoke(gpu, "bind", screen)
	component.invoke(gpu, "setForeground", 0xFFFFFF)
	component.invoke(gpu, "setBackground", 0x000000)

	local x, y = 1, 1
	local w, h = component.invoke(gpu, "maxResolution")
	component.invoke(gpu, "setResolution", w, h)
	component.invoke(gpu, "fill", 1, 1, w, h, " ")

	local buf = ""

	local function flush()
		component.invoke(gpu, "set", x - #buf, y, buf)
		buf = ""
	end

	local function putc(c)
		if c == "\n" then
			flush()
			y = y + 1
			x = 1
		elseif c == "\r" then
			flush()
			x = 1
		elseif c == "\t" then
			flush()
			x = x + 4
		else
			buf = buf .. c
			x = x + 1
		end

		if x > w then
			flush()
			x = 1
			y = y + 1
		end

		if y > h then
			component.invoke(gpu, "copy", 1, 2, w, h-1, 0, -1)
			y = h
			component.invoke(gpu, "fill", 1, y, w, 1, " ")
		end
	end

	function Kocos.scr_write(text)
		for i=1,unicode.len(text) do
			putc(unicode.sub(text, i, i))
		end
		flush()
	end

	local keyboard = component.invoke(screen, "getKeyboards")[1]
	local keybuf = ""

	function Kocos._scr_reader(ev, kbAddr, chr, cod)
		if kbAddr ~= keyboard then return end
		if ev == "key_down" then
			keybuf = keybuf .. string.char(chr)
			return
		end
		if ev == "clipboard" then
			keybuf = keybuf .. chr
			return
		end
	end

	---@return string?
	function Kocos.scr_read()
		local oldbuf = keybuf
		keybuf = ""
		return oldbuf
	end

	---@return string[]
	function Kocos.scr_addrs()
		return {gpu, screen, keyboard}
	end
end

Kocos.event.listen(Kocos._scr_reader)

---@param text string
function Kocos.writelog(text)
	-- No version when output available
	if oc and not Kocos.args.noOcelotLog then
		component.invoke(oc, "log", text)
	end
	-- typically done after boot to not fight the kernel logger
	if Kocos.disableScreenLogging then return end
	Kocos.scr_write(text)
end

function Kocos.printk(severity, msg)
	if Kocos.args.minLog then
		if severity < Kocos.args.minLog then return end
	end

	local uptime = computer.uptime()

	Kocos.event.notifyListeners("kocos_log", uptime, severity, msg)

	local names = {
		[Kocos.L_DEBUG] = "DEBUG",
		[Kocos.L_INFO] = "INFO",
		[Kocos.L_AUTOFIX] = "AUTOFIX",
		[Kocos.L_WARN] = "WARN",
		[Kocos.L_ERROR] = "ERROR",
		[Kocos.L_PANIC] = "PANIC",
	}

	local rawText = string.format("[%5.3f %s] %s\n", uptime, names[severity] or "UNKNOWN", msg)
	Kocos.writelog(rawText)

	if severity == Kocos.L_PANIC then
		if Kocos.disableDefaultPanicHandler then
			Kocos.event.notifyListeners("kocos_panic", uptime, msg)
			return
		end
		computer.beep(500)
		while true do
			pcall(Kocos.event.pull)
		end
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

Kocos.printk(Kocos.L_INFO, "printk loaded")
