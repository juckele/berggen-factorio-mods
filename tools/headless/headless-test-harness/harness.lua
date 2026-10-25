-- Test helpers for mods run by tools/headless/headless.py.
--
--   local H = require("__headless-test-harness__/harness")
--   H.scenario, H.phase, H.params     -- from the test spec, via the generated headless-test-config mod
--   H.check(name, condition, detail)  -- prints TEST PASS/FAIL, returns condition
--   H.equal(name, actual, expected)
--   H.info(name, value)               -- prints TEST INFO, never fails
--   H.at(offset, fn)                  -- run fn on the offset-th tick of this phase (1 = first tick)
--   H.after(delay, fn)                -- run fn `delay` ticks after the current tick
--   H.done()                          -- marks the phase's checks as finished
--   H.install()                       -- registers on_tick for H.at; call once at file scope
--
-- A test mod that calls H.install() must not register on_tick itself. Scheduling state lives in
-- Lua locals, which is fine for single-process headless runs but would desync multiplayer.

local config = require("__headless-test-config__/config")

local H = {
  scenario = config.scenario,
  phase = config.phase,
  params = config.params or {},
}

local function emit(kind, name, detail)
  local line = "TEST " .. kind .. " " .. name
  if detail ~= nil then
    line = line .. " :: " .. tostring(detail):gsub("\n", " ")
  end
  print(line)
end

function H.check(name, condition, detail)
  emit(condition and "PASS" or "FAIL", name, detail)
  return condition and true or false
end

function H.equal(name, actual, expected)
  local ok = actual == expected
  return H.check(name, ok, "expected " .. serpent.line(expected) .. ", got " .. serpent.line(actual))
end

function H.info(name, value)
  emit("INFO", name, type(value) == "table" and serpent.line(value) or value)
end

function H.done()
  emit("DONE", H.phase)
end

local schedule = {}
local start_tick = nil

function H.at(offset, fn)
  schedule[#schedule + 1] = { offset = offset, fn = fn }
end

-- Run fn `delay` ticks from now (from an event handler during the phase).
function H.after(delay, fn)
  H.at(H.phase_tick() + delay, fn)
end

function H.phase_tick()
  if not start_tick then return 0 end
  return game.tick - start_tick + 1
end

function H.install()
  script.on_event(defines.events.on_tick, function(event)
    if not start_tick then start_tick = event.tick end
    local offset = event.tick - start_tick + 1
    for _, entry in ipairs(schedule) do
      if entry.offset == offset then
        local ok, err = pcall(entry.fn)
        if not ok then emit("FAIL", "error-at-tick-" .. offset, err) end
      end
    end
  end)
end

return H
