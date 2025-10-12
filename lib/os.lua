-- os functions

---@param varname string
---@return string?
function os.getenv(varname)
	return k.environ()[varname]
end

---@return table<string, string>
function os.getenvs()
	return k.environ()
end

---@param varname string
---@param val string?
function os.setenv(varname, val)
	k.environ()[varname] = val
end
