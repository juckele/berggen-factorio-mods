local shared = {}

shared.name = "anti-jam-stack-inserter"
shared.base_name = "stack-inserter"
shared.to_anti_jam = "anti-jam-stack-inserter-from-stack-inserter"
shared.to_stack = "stack-inserter-from-anti-jam-stack-inserter"
shared.conversion_setting = "anti-jam-stack-inserter-conversion-recipes"

-- Multiplied into the stack inserter's sprites. Silver turns the purple of the
-- old 1.1 filter inserter; the yellow trim comes out orange.
shared.tint = {r = 0.75, g = 0.45, b = 1.0, a = 1.0}

return shared
