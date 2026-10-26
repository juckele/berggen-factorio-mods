-- Lure turret: a very slow, very long-range turret that lures demolishers by hurting them a
-- little. Kitbashed from the gun turret (body), the cannon shell (projectile, icon) and the
-- tank cannon (sound). Balance values are placeholders.

local RANGE = 96          -- past a demolisher's vision, so it is hit from out of sight
local COOLDOWN = 15 * 60  -- one shot every 15 s
local TURN_TIME = 15 * 60 -- 15 s for a full turn
local DAMAGE = 20         -- physical; demolishers resist half, enough to enrage them

data:extend({ { type = "ammo-category", name = "demolisher-lure", hidden_in_factoriopedia = true } })

-- Turret
local turret = table.deepcopy(data.raw["ammo-turret"]["gun-turret"])
turret.name = "demolisher-lure-turret"
turret.minable = { mining_time = 0.5, result = "demolisher-lure-turret" }
turret.max_health = 1000
turret.rotation_speed = 1 / TURN_TIME
turret.prepare_range = RANGE + 4
turret.automated_ammo_count = 5
turret.inventory_size = 1
-- Graphics and icons are the gun turret's and cannon shell's, unchanged, until real art exists.
local attack = turret.attack_parameters
attack.type = "projectile"
attack.ammo_category = "demolisher-lure"
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
projectile.name = "demolisher-lure-projectile"
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
shell.name = "demolisher-lure-shell"
shell.ammo_category = "demolisher-lure"
shell.order = "d[cannon-shell]-z[demolisher-lure-shell]"
shell.ammo_type = {
  target_type = "entity",
  action = {
    type = "direct",
    action_delivery = {
      type = "projectile",
      projectile = "demolisher-lure-projectile",
      starting_speed = 1,
      max_range = RANGE + 10,
      source_effects = { type = "create-explosion", entity_name = "explosion-gunshot" },
    },
  },
}

local item = table.deepcopy(data.raw.item["gun-turret"])
item.name = "demolisher-lure-turret"
item.place_result = "demolisher-lure-turret"
item.order = "b[turret]-z[demolisher-lure-turret]"

data:extend({
  turret,
  projectile,
  shell,
  item,
  {
    type = "recipe",
    name = "demolisher-lure-turret",
    enabled = false,
    energy_required = 10,
    ingredients = {
      { type = "item", name = "gun-turret", amount = 1 },
      { type = "item", name = "tungsten-plate", amount = 10 },
      { type = "item", name = "steel-plate", amount = 10 },
    },
    results = { { type = "item", name = "demolisher-lure-turret", amount = 1 } },
  },
  {
    type = "recipe",
    name = "demolisher-lure-shell",
    enabled = false,
    energy_required = 2,
    ingredients = {
      { type = "item", name = "iron-plate", amount = 2 },
      { type = "item", name = "calcite", amount = 1 },
    },
    results = { { type = "item", name = "demolisher-lure-shell", amount = 2 } },
  },
  {
    type = "technology",
    name = "demolisher-lure-turret",
    icon = "__base__/graphics/technology/gun-turret.png",
    icon_size = 256,
    effects = {
      { type = "unlock-recipe", recipe = "demolisher-lure-turret" },
      { type = "unlock-recipe", recipe = "demolisher-lure-shell" },
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
