Kocos = {}

_KVERSION = "KOCOS v0.-1.0"
_OSVERSION = _OSVERSION or "Unnamed KOCOS"

local argv = {...}

---@alias Kocos.device {address: string, type: string, slot: integer}|table

---@class Kocos.config
---@field debugger? string
---@field root? string
---@field ramfs? string
---@field noOcelotLog? boolean
---@field minLog? integer
---@field pollInterval? number
---@field minEventPoll? number
---@field useExtremelySecurePidGeneration? boolean
---@field packagePath? string
---@field packageCPath? string
---@field luaExecRT? string
---@field luaExecRTF? string

---@type Kocos.config
Kocos.args = {}

if argv[1] == "kocos" then
	-- KOCOS boot protocol
	Kocos.args = argv[2]
elseif not argv[1] then
	-- generic boot protocol
else
	error("Unknown boot protocol! This is catastrophic")
end

Kocos.disableScreenLogging = false
Kocos.disableDefaultPanicHandler = false

function Kocos.poweroff(reboot)
	Kocos.event.notifyListeners("poweroff", reboot)
	computer.shutdown(reboot)
end

package = {}
package.preload = {}
package.loaded = {}
package.path = Kocos.args.packagePath or "?.lua;?/init.lua;/lib/?.lua;/lib/?/init.lua;/usr/lib/?.lua;/usr/lib/?/init.lua;/usr/local/lib/?.lua;/usr/local/lib/?/init.lua"
package.cpath = Kocos.args.packageCPath or "lib?.so;/lib/lib?.so;/usr/lib/lib?.so;/usr/local/lib/lib?.so"
package.config = [[
/
;
?
!
-]]
