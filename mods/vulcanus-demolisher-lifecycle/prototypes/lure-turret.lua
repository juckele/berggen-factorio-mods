-- Lure turret: a very slow, very long-range turret that lures demolishers by hurting them a
-- little. Built on the gun turret's prototype with the tank cannon's sound. Graphics are the
-- mod's own placeholders (graphics/README.md lists every sheet's layout). Balance values are
-- placeholders.

local util = require("util")
local G = "__vulcanus-demolisher-lifecycle__/graphics/"

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
turret.icon = G .. "icons/lure-turret.png"
turret.icon_size = 64
turret.icons = nil
turret.corpse = "demolisher-lure-turret-remnants"
turret.water_reflection = nil

-- Head sheets, all 160x160 frames at scale 0.5. Raising: 4 directions (N, E, S, W) by 5 frames,
-- frame 1 folded. Shooting: 64 directions by 2 frames (2 = recoil) in 4 stripe files of 16
-- directions each. Shadows are 208 px wide frames, 12 px further right.
local HEAD_SHIFT = util.by_pixel(0, -24)
local HEAD_SHADOW_SHIFT = util.by_pixel(12, -24)

local function raising(file, args, extra)
  local layer = {
    filename = G .. "entity/lure-turret/" .. file,
    priority = "medium",
    width = file:find("shadow") and 208 or 160,
    height = 160,
    direction_count = 4,
    frame_count = args.frame_count or 5,
    line_length = args.line_length or 5,
    run_mode = args.run_mode or "forward",
    shift = file:find("shadow") and HEAD_SHADOW_SHIFT or HEAD_SHIFT,
    scale = 0.5,
  }
  for k, v in pairs(extra or {}) do layer[k] = v end
  return layer
end

local function extension(args)
  return {
    layers = {
      raising("lure-turret-raising.png", args),
      raising("lure-turret-raising-mask.png", args, { flags = { "mask" }, apply_runtime_tint = true }),
      raising("lure-turret-raising-shadow.png", args, { draw_as_shadow = true }),
    },
  }
end

local function shooting(suffix, frame_count, extra)
  local shadow = suffix == "-shadow"
  local stripes = {}
  for i = 1, 4 do
    stripes[i] = {
      filename = G .. "entity/lure-turret/lure-turret-shooting" .. suffix .. "-" .. i .. ".png",
      width_in_frames = frame_count,
      height_in_frames = 16,
    }
  end
  local layer = {
    width = shadow and 208 or 160,
    height = 160,
    frame_count = frame_count,
    direction_count = 64,
    shift = shadow and HEAD_SHADOW_SHIFT or HEAD_SHIFT,
    stripes = stripes,
    scale = 0.5,
  }
  for k, v in pairs(extra or {}) do layer[k] = v end
  return layer
end

local function attack_animation(frame_count)
  return {
    layers = {
      shooting("", frame_count),
      shooting("-mask", frame_count, { flags = { "mask" }, apply_runtime_tint = true }),
      shooting("-shadow", frame_count, { draw_as_shadow = true }),
    },
  }
end

turret.folded_animation = extension({ frame_count = 1, line_length = 1 })
turret.preparing_animation = extension({})
turret.prepared_animation = attack_animation(1)
turret.attacking_animation = attack_animation(2)
turret.folding_animation = extension({ run_mode = "backward" })
turret.graphics_set = {
  base_visualisation = {
    animation = {
      layers = {
        { filename = G .. "entity/lure-turret/lure-turret-base.png", priority = "high",
          width = 160, height = 160, shift = util.by_pixel(0, -2), scale = 0.5 },
        { filename = G .. "entity/lure-turret/lure-turret-base-mask.png", flags = { "mask", "low-object" },
          width = 160, height = 160, shift = util.by_pixel(0, -2), apply_runtime_tint = true, scale = 0.5 },
        { filename = G .. "entity/lure-turret/lure-turret-base-shadow.png", priority = "high",
          width = 208, height = 160, shift = util.by_pixel(12, -2), draw_as_shadow = true, scale = 0.5 },
      },
    },
  },
}

local attack = turret.attack_parameters
attack.type = "projectile"
attack.ammo_category = "demolisher-lure"
attack.ammo_categories = nil
attack.cooldown = COOLDOWN
attack.range = RANGE
attack.min_range = 0
attack.lead_target_for_projectile_speed = 1
attack.shell_particle = nil
-- The head's pivot is 18 px above the entity centre; the muzzle about a tile out from it.
attack.projectile_center = { 0, -0.5625 }
attack.projectile_creation_distance = 1.0
local cannon = data.raw.gun["tank-cannon"]
if cannon and cannon.attack_parameters and cannon.attack_parameters.sound then
  attack.sound = table.deepcopy(cannon.attack_parameters.sound)
end

-- Projectile: a cannon shell that barely hurts.
local projectile = table.deepcopy(data.raw.projectile["cannon-projectile"])
projectile.name = "demolisher-lure-projectile"
projectile.piercing_damage = 0
projectile.animation = {
  filename = G .. "entity/lure-shell/lure-shell.png",
  draw_as_glow = true,
  width = 32,
  height = 64,
  priority = "high",
  scale = 0.5,
}
projectile.shadow = {
  filename = G .. "entity/lure-shell/lure-shell-shadow.png",
  draw_as_shadow = true,
  width = 32,
  height = 64,
  priority = "high",
  scale = 0.5,
}
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
shell.icon = G .. "icons/lure-shell.png"
shell.icon_size = 64
shell.icons = nil
shell.pictures = nil
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
item.icon = G .. "icons/lure-turret.png"
item.icon_size = 64
item.icons = nil

-- Remnants: 2 variations of 192x192.
local remnants = table.deepcopy(data.raw.corpse["gun-turret-remnants"])
remnants.name = "demolisher-lure-turret-remnants"
remnants.localised_name = { "remnant-name", { "entity-name.demolisher-lure-turret" } }
remnants.icon = G .. "icons/lure-turret.png"
remnants.icon_size = 64
remnants.icons = nil
remnants.animation_overlay = nil
remnants.animation = {}
for i = 0, 1 do
  remnants.animation[i + 1] = {
    filename = G .. "entity/lure-turret/remnants/lure-turret-remnants.png",
    width = 192,
    height = 192,
    x = 192 * i,
    frame_count = 1,
    direction_count = 1,
    shift = util.by_pixel(0, 4),
    scale = 0.5,
  }
end

data:extend({
  turret,
  remnants,
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
    icon = G .. "technology/lure-turret.png",
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
