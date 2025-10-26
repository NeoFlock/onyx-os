--!lua

local s = ...

package.loaded.blake3 = nil
local key = "whats the Elvish word for friend"
local h = require("blake3").hash(s or "hi")
print(#h, "bytes")
print(require("hex").dump(h))
