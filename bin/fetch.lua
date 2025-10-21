--!lua

local terminal = require("terminal")
local userdb = require("userdb")
local shutils = require("shutils")

local term = terminal.stdio()

---@type string[]
local infoLines = {}

local sysinfo = assert(k.sysinfo())
local mounts = assert(k.getMounts())
local hostname = shutils.getHostname()
local user = shutils.getUser()

local w, h = terminal.stdterm():getResolution()

local libopk = require("libopk", true)

table.insert(infoLines, "OS: " .. sysinfo.os)
table.insert(infoLines, "Kernel: " .. sysinfo.kernel)
table.insert(infoLines, "Host: " .. hostname)
table.insert(infoLines, "Uptime: " .. string.boottimefmt(k.uptime()))
table.insert(infoLines, "Boot: " .. sysinfo.bootAddress)
table.insert(infoLines, "User: " .. user)
table.insert(infoLines, "Shell: " .. userdb.getShell(user))
table.insert(infoLines, "Packages: " .. #libopk.getInstalled() .. " (opk)")
table.insert(infoLines, "Home: " .. userdb.getHome(user))
table.insert(infoLines, "Resolution: " .. w .. " x " .. h)
table.insert(infoLines, "Free Memory: " .. string.memformat(sysinfo.memfree) .. " / " .. string.memformat(sysinfo.memtotal))
table.insert(infoLines, "Energy: " .. sysinfo.energy .. " FE / " .. sysinfo.maxEnergy ..  "FE")
for dev, path in pairs(mounts) do
	local stat = assert(k.stat(path))
	local line = string.format("%s -> %s... (%s / %s %3.2f%%)", path, dev:sub(1, 6), string.memformat(stat.diskUsed), string.memformat(stat.diskTotal), stat.diskUsed / stat.diskTotal)
	table.insert(infoLines, line)
end

local clr=""
for i=0,7 do
	clr = clr .. "\x1b[38;5;" .. i .. "m  "
end
table.insert(infoLines, clr)
clr=""
for i=8,15 do
	clr = clr .. "\x1b[38;5;" .. i .. "m  "
end
table.insert(infoLines, clr)

local function getOsBrand()
	local brand = k.sysinfo().os
	local e = string.find(brand, "%s")
	if e then brand = brand:sub(1, e-1) end
	return brand
end

-- made with https://patorjk.com/software/taag/

local asciiColors = {
	ONYX = "\x1b[34m",
}
local asciiArt = {
	ONYX = [===[
    ,----..            ,--.                            
   /   /   \         ,--.'|             ,--,     ,--,  
  /   .     :    ,--,:  : |        ,---,|'. \   / .`|  
 .   /   ;.  \,`--.'`|  ' :       /_ ./|; \ `\ /' / ;  
.   ;   /  ` ;|   :  :  | | ,---, |  ' :`. \  /  / .'  
;   |  ; \ ; |:   |   \ | :/___/ \.  : | \  \/  / ./   
|   :  | ; | '|   : '  '; | .  \  \ ,' '  \  \.'  /    
.   |  ' ' ' :'   ' ;.    ;  \  ;  `  ,'   \  ;  ;     
'   ;  \; /  ||   | | \   |   \  \    '   / \  \  \    
 \   \  ',  / '   : |  ; .'    '  \   |  ;  /\  \  \   
  ;   :    /  |   | '`--'       \  ;  ;./__;  \  ;  \  
   \   \ .'   '   : |            :  \  \   : / \  \  ; 
    `---`     ;   |.'             \  ' ;   |/   \  ' | 
              '---'                `--``---'     `--`  
]===],
	Unnamed = [[
  _____  
 / ___ \ 
( (   ) )
 \/  / / 
    ( (  
    | |  
    (_)  
     _   
    (_)  
]]
}

local brand = getOsBrand()
local art = asciiArt[brand] or asciiArt.Unnamed
local color = asciiColors[brand] or ""

local asciiLines = string.split(art, "\n")
for i=#asciiLines, 1, -1 do
	if asciiLines[i] == "" then
		table.remove(asciiLines, i)
	end
end
local asciiWidth = 0
for _, line in ipairs(asciiLines) do
	asciiWidth = math.max(asciiWidth, #line)
end

for i=1, math.max(#infoLines, #asciiLines) do
	term:write(color, string.rightpad(asciiLines[i] or "", asciiWidth), "\x1b[0m", infoLines[i] or "", "\n")
end
