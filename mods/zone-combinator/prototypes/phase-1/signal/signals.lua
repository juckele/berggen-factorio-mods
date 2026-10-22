local day_length_prototype = table.deepcopy(data.raw["virtual-signal"]["signal-everything"])
day_length_prototype.name = "zc-day-length"
day_length_prototype.icon = "__zone-combinator__/graphics/signal/sunrise.png"
day_length_prototype.icon_size = 512
day_length_prototype.order = "zone-combinator-a"
day_length_prototype.subgroup = "virtual-signal"

local solar_percent_prototype = table.deepcopy(data.raw["virtual-signal"]["signal-everything"])
solar_percent_prototype.name = "zc-solar"
solar_percent_prototype.icon = "__zone-combinator__/graphics/signal/sun.png"
solar_percent_prototype.icon_size = 512
solar_percent_prototype.order = "zone-combinator-b"
solar_percent_prototype.subgroup = "virtual-signal"

local threat_prototype = table.deepcopy(data.raw["virtual-signal"]["signal-everything"])
threat_prototype.name = "zc-threat"
threat_prototype.icon = "__zone-combinator__/graphics/signal/bullseye.png"
threat_prototype.icon_size = 512
threat_prototype.order = "zone-combinator-c"
threat_prototype.subgroup = "virtual-signal"

local robot_interference_prototype = table.deepcopy(data.raw["virtual-signal"]["signal-everything"])
robot_interference_prototype.name = "zc-robot-interference"
robot_interference_prototype.icon = "__zone-combinator__/graphics/signal/cloud-with-lightning.png"
robot_interference_prototype.icon_size = 512
robot_interference_prototype.order = "zone-combinator-d"
robot_interference_prototype.subgroup = "virtual-signal"

data:extend({day_length_prototype, solar_percent_prototype, threat_prototype, robot_interference_prototype})
