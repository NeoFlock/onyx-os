-- Ash as a library, useful for various shell things

local ash = {}

ash.whitespace = " \n\t\r\f\v"
ash.arraySplit = " \n\t"
ash.bannedSubstituteLetters = ".-()[]{}:="

ash.shellWorlds = {
	"while",
	"done",
	"if",
	"then",
	"else",
	"elif",
	"fi",
	"case",
	"in",
	"esac",
}

ash.shellSymbols = {
	"$(",
	")",
	"=",
	"&&",
	"||",
	">>",
	"<<",
	">",
	"|",
	"\n",
	";",
}

---@class ash.argument
---@field value? string
---@field substitution? string
---@field command? ash.command
---@field compound? ash.argument[]

---@class ash.command
--- echo hi
---@field simple? ash.argument[]
--- while condition; <block>; done;
---@field while? {condition: ash.command, body: ash.command[]}
--- if condition; then; <block>; fi
---@field if? {checks: {condition: ash.command, body: ash.command}[], fallback: ash.command[]}
--- op |
---@field pipeTo? ash.command
--- op > file
---@field outputTo? {fd: integer, file: string}
--- op >> file
---@field appendTo? {fd: integer, file: string}
--- op < file
---@field readFrom? string
--- op &&
---@field both? {left: ash.command, right: ash.command}
--- op ||
---@field either? {left: ash.command, right: ash.command}

---@alias ash.tt "text"|"word"|"substitution"|"symbol"|"space"|"command-end"

---@class ash.token
---@field tt ash.tt
---@field data string
---@field loc integer

---@param data string
---@return ash.token[]? tokens, string? error, integer? errloc
function ash.lex(data)
	---@type ash.token[]
	local toks = {}
	local off = 0
	while off < #data do
	::continue::
	end
	return toks
end

---@param tokens ash.token[]
---@return ash.command[]? commands, string? error, integer? errloc
function ash.parseTokens(tokens)

end

return ash
