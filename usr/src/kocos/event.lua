--- Non-buffered event stream
--- Use listeners to ensure all events are processed and none are skipped
--- Based off OpenOS' event library, but with many subtle differences

Kocos.event = {}

---@type function[]
Kocos.event.listeners = {}
---@type table<integer, {times: integer, interval: number, deadline: number, func: function}>
Kocos.event.timers = {}

function Kocos.event.notifyListeners(...)
	for _, func in ipairs(Kocos.event.listeners) do
		local ok, err = xpcall(func, debug.traceback, ...)
		if not ok then
			Kocos.printkf(Kocos.L_ERROR, "Signal handler error: %s", err)
		end
	end
end

function Kocos.event.listen(func)
	table.insert(Kocos.event.listeners, func)
end

function Kocos.event.forget(func)
	for i=#Kocos.event.listeners, 1, -1 do
		if Kocos.event.listeners[i] == func then
			table.remove(Kocos.event.listeners, i)
		end
	end
end

function Kocos.event.processTimers()
	local toCancel = {}

	for id, timer in pairs(Kocos.event.timers) do
		local now = computer.uptime()
		if timer.deadline <= now then
			timer.times = timer.times - 1
			timer.deadline = now + timer.interval
			timer.func()
		end
		if timer.times < 1 then
			table.insert(toCancel, id)
		end
	end

	for _, id in ipairs(toCancel) do Kocos.event.cancel(id) end
end

function Kocos.event.minTimeTilNextTimer(timeleft)
	for _, timer in pairs(Kocos.event.timers) do
		local timerleft = timer.deadline - computer.uptime()
		timeleft = math.min(timeleft, timerleft)
	end
	return math.max(timeleft, Kocos.args.minEventPoll or 0)
end

---@param interval number
---@param func function
---@param times? integer
function Kocos.event.timer(interval, func, times)
	times = times or 1

	local id = #Kocos.event.timers
	while Kocos.event.timers[id] do id = id + 1 end
	Kocos.event.timers[id] = {
		interval = interval,
		func = func,
		times = times,
		deadline = computer.uptime() + interval,
	}
	return id
end

function Kocos.event.cancel(id)
	Kocos.event.timers[id] = nil
end

---@param timeout? number
function Kocos.event.pull(timeout)
	timeout = timeout or (Kocos.args.pollInterval or 0)
	local deadline = computer.uptime() + timeout

	while true do
		local now = computer.uptime()
		if now > deadline then return end
		local timeleft = Kocos.event.minTimeTilNextTimer(deadline - now)
		local s = {computer.pullSignal(timeleft)}
		Kocos.event.processTimers()
		if s[1] then
			Kocos.event.notifyListeners(table.unpack(s))
			return table.unpack(s)
		end
	end
end

---@type fun(ev: string, ...)
Kocos.event.push = computer.pushSignal
