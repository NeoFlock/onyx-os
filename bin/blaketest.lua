--!lua

local s = ...

package.loaded.blake3 = nil
local h = require("blake3").hash(s or "", "whats the Elvish word for friend")
print(#h, "bytes")
print(require("hex").dump(h))
