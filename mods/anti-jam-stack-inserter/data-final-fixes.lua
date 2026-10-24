local shared = require("shared")
local util_lib = require("prototypes.util")

-- Build from and mine to whatever the stack inserter uses, after other mods' changes.
util_lib.sync_with_stack_inserter(data.raw.inserter[shared.name])
