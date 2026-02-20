---@type function[]
Kocos.listeners = {}

---@type table<integer, {times: integer, interval: number, deadline: number, func: function}>
Kocos.timers = {}
local nextTimer = 0

function Kocos.notifyListeners(...)
	if select("#", ...) == 0 then return end
	for _, func in ipairs(Kocos.listeners) do
		local ok, err = xpcall(func, debug.traceback, ...)
		if not ok then
			Kocos.printkf(Kocos.L_ERROR, "Event handler error: %s", err)
		end
	end
end

function Kocos.listen(func)
	table.insert(Kocos.listeners, func)
end

function Kocos.forget(func)
	for i=#Kocos.listeners, 1, -1 do
		if Kocos.listeners[i] == func then
			table.remove(Kocos.listeners, i)
		end
	end
end

function Kocos.processTimers()
	local toCancel = {}

	for id, timer in pairs(Kocos.timers) do
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

	for _, id in ipairs(toCancel) do Kocos.cancelTimer(id) end
end

function Kocos.minTimeTilNextTimer(timeleft)
	for _, timer in pairs(Kocos.timers) do
		local timerleft = timer.deadline - computer.uptime()
		timeleft = math.min(timeleft, timerleft)
	end
	return math.max(timeleft, Kocos.getCmdlineNum("MIN_POLL", 0.05))
end

---@param interval number
---@param func function
---@param times? integer
function Kocos.timer(interval, func, times)
	times = times or 1

	local id = nextTimer
	-- just in case
	while Kocos.timers[id] do id = id + 1 end
	nextTimer = id + 1
	Kocos.timers[id] = {
		interval = interval,
		func = func,
		times = times,
		deadline = computer.uptime() + interval,
	}
	return id
end

function Kocos.cancelTimer(id)
	Kocos.timers[id] = nil
end

---@param timeout? number
function Kocos.pull(timeout)
	timeout = timeout or Kocos.getCmdlineNum("POLL_INT", 0)
	local deadline = computer.uptime() + timeout

	while true do
		local now = computer.uptime()
		local timeleft = Kocos.minTimeTilNextTimer(deadline - now)
		local s = {computer.pullSignal(timeleft)}
		Kocos.processTimers()
		if s[1] then
			Kocos.notifyListeners(table.unpack(s))
			return table.unpack(s)
		end
		if now > deadline then return end
	end
end

---@type fun(ev: string, ...)
Kocos.push = computer.pushSignal
