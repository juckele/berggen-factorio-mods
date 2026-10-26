-- Ping turret: a very slow, very long-range turret that lures demolishers by hurting them a
-- little. Kitbashed from the gun turret (body), the cannon shell (projectile, icon) and the
-- tank cannon (sound). Balance values are placeholders.

local TINT = { r = 0.95, g = 0.62, b = 0.38, a = 1 }
local RANGE = 96          -- past a demolisher's vision, so it is pinged from out of sight
local COOLDOWN = 15 * 60  -- one shot every 15 s
local TURN_TIME = 15 * 60 -- 15 s for a full turn
local DAMAGE = 20         -- physical; demolishers resist half, enough to enrage them

data:extend({ { type = "ammo-category", name = "demolisher-ping", hidden_in_factoriopedia = true } })

-- Turret
local turret = table.deepcopy(data.raw["ammo-turret"]["gun-turret"])
turret.name = "demolisher-ping-turret"
turret.icons = { { icon = turret.icon, icon_size = turret.icon_size, tint = TINT } }
turret.icon = nil
turret.minable = { mining_time = 0.5, result = "demolisher-ping-turret" }
turret.max_health = 1000
turret.rotation_speed = 1 / TURN_TIME
turret.prepare_range = RANGE + 4
turret.automated_ammo_count = 5
turret.inventory_size = 1
-- The body keeps the gun turret's graphics untinted, so its mask shows the player's colour like
-- other turrets. Only the icons are tinted, to tell it apart in inventories.
local attack = turret.attack_parameters
attack.type = "projectile"
attack.ammo_category = "demolisher-ping"
attack.ammo_categories = nil
attack.cooldown = COOLDOWN
attack.range = RANGE
attack.min_range = 0
attack.lead_target_for_projectile_speed = 1
attack.shell_particle = nil
local cannon = data.raw.gun["tank-cannon"]
if cannon and cannon.attack_parameters and cannon.attack_parameters.sound then
  attack.sound = table.deepcopy(cannon.attack_parameters.sound)
end

-- Projectile: a cannon shell that barely hurts.
local projectile = table.deepcopy(data.raw.projectile["cannon-projectile"])
projectile.name = "demolisher-ping-projectile"
projectile.piercing_damage = 0
projectile.action = {
  type = "direct",
  action_delivery = {
    type = "instant",
    target_effects = {
      { type = "damage", damage = { amount = DAMAGE, type = "physical" } },
      { type = "create-entity", entity_name = "explosion" },
    },
  },
}

local shell = table.deepcopy(data.raw.ammo["cannon-shell"])
shell.name = "demolisher-ping-shell"
shell.icons = { { icon = shell.icon, icon_size = shell.icon_size, tint = TINT } }
shell.icon = nil
shell.ammo_category = "demolisher-ping"
shell.order = "d[cannon-shell]-z[demolisher-ping-shell]"
shell.ammo_type = {
  target_type = "entity",
  action = {
    type = "direct",
    action_delivery = {
      type = "projectile",
      projectile = "demolisher-ping-projectile",
      starting_speed = 1,
      max_range = RANGE + 10,
      source_effects = { type = "create-explosion", entity_name = "explosion-gunshot" },
    },
  },
}

local item = table.deepcopy(data.raw.item["gun-turret"])
item.name = "demolisher-ping-turret"
item.icons = turret.icons
item.icon = nil
item.place_result = "demolisher-ping-turret"
item.order = "b[turret]-z[demolisher-ping-turret]"

data:extend({
  turret,
  projectile,
  shell,
  item,
  {
    type = "recipe",
    name = "demolisher-ping-turret",
    enabled = false,
    energy_required = 10,
    ingredients = {
      { type = "item", name = "gun-turret", amount = 1 },
      { type = "item", name = "tungsten-plate", amount = 10 },
      { type = "item", name = "steel-plate", amount = 10 },
    },
    results = { { type = "item", name = "demolisher-ping-turret", amount = 1 } },
  },
  {
    type = "recipe",
    name = "demolisher-ping-shell",
    enabled = false,
    energy_required = 2,
    ingredients = {
      { type = "item", name = "iron-plate", amount = 2 },
      { type = "item", name = "calcite", amount = 1 },
    },
    results = { { type = "item", name = "demolisher-ping-shell", amount = 2 } },
  },
  {
    type = "technology",
    name = "demolisher-ping-turret",
    icons = {
      { icon = "__base__/graphics/technology/gun-turret.png", icon_size = 256, tint = TINT },
    },
    effects = {
      { type = "unlock-recipe", recipe = "demolisher-ping-turret" },
      { type = "unlock-recipe", recipe = "demolisher-ping-shell" },
    },
    prerequisites = { "metallurgic-science-pack" },
    unit = {
      count = 300,
      ingredients = {
        { "automation-science-pack", 1 },
        { "logistic-science-pack", 1 },
        { "chemical-science-pack", 1 },
        { "space-science-pack", 1 },
        { "metallurgic-science-pack", 1 },
      },
      time = 30,
    },
  },
})
