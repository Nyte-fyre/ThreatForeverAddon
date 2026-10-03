"""Mocked smoke test for HealerThreat. Run: python tests/smoke.py (needs lupa).

Secret values are proxies that raise on compare, math and concat, so any
unguarded use in the addon fails the run.
"""
import os
import sys

try:
    from lupa import lua51 as lupa  # WoW runs Lua 5.1
except ImportError:
    import lupa

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "HealerThreat")

MOCKS = r'''
SECRETS = setmetatable({}, { __mode = "k" })
local smt = {}
for _, m in ipairs({ "__add", "__sub", "__mul", "__div", "__eq", "__lt", "__le", "__concat", "__unm" }) do
  smt[m] = function() error("secret value misused (" .. m .. ")") end
end
function secret(v) local p = setmetatable({ v = v }, smt); SECRETS[p] = true; return p end
issecretvalue = function(v) return SECRETS[v] == true end

out = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) out[#out + 1] = m end }
SOUNDS = {}
SOUNDKIT = { RAID_WARNING = 8959, UI_RAID_BOSS_WHISPER_WARNING = 37666 }
PlaySound = function(id) SOUNDS[#SOUNDS + 1] = id end

-- Generic widget: any unknown method is a no-op; text and values are recorded.
local wmt = {}
local DATA = { shown = true, text = true, value = true, checked = true, scripts = true }
wmt.__index = function(t, k)
  if DATA[k] then return nil end
  return function(self, ...)
    local a = { ... }
    if k == "SetText" or k == "SetFormattedText" then
      self.text = (k == "SetText") and a[1] or ("fmt:" .. tostring(SECRETS[a[2]] and "<secret>" or a[2]))
    elseif k == "SetValue" then self.value = SECRETS[a[1]] and "<secret>" or a[1]
    elseif k == "Show" then self.shown = true
    elseif k == "Hide" then self.shown = false
    elseif k == "IsShown" then return self.shown
    elseif k == "GetChecked" then return self.checked
    elseif k == "SetScript" then self.scripts = self.scripts or {}; self.scripts[a[1]] = a[2]
    elseif k == "GetPoint" then return "CENTER", nil, "CENTER", 10, 20
    elseif k == "CreateFontString" or k == "CreateTexture" or k == "CreateAnimationGroup" or k == "CreateAnimation" then
      return setmetatable({}, wmt)
    end
  end
end
FRAMES = {}
CreateFrame = function(_, name) local w = setmetatable({}, wmt); FRAMES[#FRAMES + 1] = w; if name then _G[name] = w end; return w end
UIParent = setmetatable({}, wmt)
UISpecialFrames = {}
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end end
unpack = unpack or table.unpack
SlashCmdList = {}
Settings = { RegisterCanvasLayoutCategory = function() return { GetID = function() return 1 end } end,
  RegisterAddOnCategory = function() end, OpenToCategory = function() end }

NOW = 0
GetTime = function() return NOW end
COMBAT = false
InCombatLockdown = function() return COMBAT end
GROUP = false
IsInGroup = function() return GROUP end
IsInRaid = function() return false end

-- World: unit token -> mob record { guid, name, status, scaled, secretDetail, secretStatus }
WORLD = {}
UnitExists = function(u) return WORLD[u] ~= nil end
UnitCanAttack = function(_, u) return WORLD[u] ~= nil end
UnitIsDead = function() return false end
UnitGUID = function(u) local m = WORLD[u]; if not m then return nil end; return m.secretGuid and secret(m.guid) or m.guid end
C_NamePlate = { GetNamePlateForUnit = function(u) return WORLD[u] and WORLD[u].plate end }
UnitName = function(u) return WORLD[u] and WORLD[u].name end
UnitThreatSituation = function(_, u)
  local m = WORLD[u]; if not m or m.status == nil then return nil end
  return m.secretStatus and secret(m.status) or m.status
end
UnitDetailedThreatSituation = function(_, u)
  local m = WORLD[u]; if not m or m.status == nil then return nil end
  local tank = m.status >= 2
  if m.secretDetail then return secret(tank), secret(m.status), secret(m.scaled), secret(255), secret(50) end
  return tank, m.status, m.scaled, 255, 50
end
'''

DRIVER = r'''
local f = FRAMES[1]
f.scripts.OnEvent(f, "ADDON_LOADED", "HealerThreat")
f.scripts.OnEvent(f, "PLAYER_LOGIN")
local function tick() NOW = NOW + 1; f.scripts.OnUpdate(f, 0.3) end
local main = HealerThreatFrame

-- Out of combat, nothing engaged: hidden.
tick(); assert(main.shown == false, "hidden out of combat")

-- Solo fight: target precise, the same mob also as nameplate1 (secret), plus a secret nameplate mob.
COMBAT = true
WORLD.target = { guid = "A", name = "Bear", status = 3, scaled = 100 }
WORLD.nameplate1 = { guid = "A", name = "Bear", status = 3, scaled = 100, secretDetail = true }
WORLD.nameplate2 = { guid = "B", name = "Wolf", status = 0, scaled = 40, secretDetail = true }
tick()
assert(main.shown, "shown in combat")
local list = HealerThreat_Test.Collect()
assert(#list == 1, "healer view: bear only (wolf is status 0, secret %), got " .. #list)
assert(#SOUNDS == 0, "no sound solo")

-- Group: healer, tank holds everything, then threat climbs on the target.
COMBAT = true; GROUP = true
f.scripts.OnEvent(f, "PLAYER_REGEN_ENABLED")
WORLD.target = { guid = "A", name = "Bear", status = 0, scaled = 60 }
WORLD.nameplate1 = { guid = "A", name = "Bear", status = 0, scaled = 60, secretDetail = true }
tick()
assert(#HealerThreat_Test.Collect() == 1, "60% >= showAt 50 visible")
assert(#SOUNDS == 0, "below warnAt")
WORLD.target.scaled = 85; tick()
assert(#SOUNDS == 1, "warn at 85%")
NOW = NOW + 5; WORLD.target.scaled = 90; tick()
assert(#SOUNDS == 1, "no repeat at same level")
-- Wolf (secret %, readable status) goes to status 1: visible + alert.
NOW = NOW + 5; WORLD.nameplate2.status = 1; tick()
assert(#SOUNDS == 2, "status 1 on nameplate mob alerts")
assert(#HealerThreat_Test.Collect() == 2, "wolf now visible")
-- Fully secret mob: hidden in healer view, shown with showAll.
WORLD.nameplate3 = { guid = "C", name = "Boar", status = 0, scaled = 10, secretDetail = true, secretStatus = true }
assert(#HealerThreat_Test.Collect() == 2, "fully secret hidden")
HealerThreatDB.showAll = true
assert(#HealerThreat_Test.Collect() == 3, "showAll shows all three")
tick()
-- Aggro.
NOW = NOW + 5; WORLD.target.status = 3; tick()
assert(#SOUNDS == 3, "aggro alert")

-- Dungeon: GUIDs secret; the target's nameplate is matched by frame instead.
HealerThreatDB.showAll = true
local plateA, plateB = {}, {}
WORLD = {
  target = { guid = "X", secretGuid = true, name = "Ogre", status = 0, scaled = 60, plate = plateA },
  nameplate1 = { guid = "X", secretGuid = true, name = "Ogre", status = 0, scaled = 60, secretDetail = true, plate = plateA },
  nameplate2 = { guid = "Y", secretGuid = true, name = "Imp", status = 0, scaled = 20, secretDetail = true, plate = plateB },
}
local rows = HealerThreat_Test.Collect()
assert(#rows == 2, "target and its nameplate merged, got " .. #rows)
assert(rows[1].precise, "the target (precise) row is the one kept")

-- Settings and slash commands.
SlashCmdList.HEALERTHREAT("unlock"); SlashCmdList.HEALERTHREAT("lock"); SlashCmdList.HEALERTHREAT("test")
COMBAT = false; tick(); assert(main.shown, "test rows show out of combat")
SlashCmdList.HEALERTHREAT("test"); SlashCmdList.HEALERTHREAT("off"); tick()
assert(main.shown == false, "disabled hides")
SlashCmdList.HEALERTHREAT("on"); SlashCmdList.HEALERTHREAT("")
print("ok: " .. #SOUNDS .. " alerts")
'''


def main():
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute(MOCKS)
    load_file = L.eval("function(src, name, ns) local fn = assert((loadstring or load)(src, name)); fn('HealerThreat', ns) end")
    ns = L.table()
    toc = open(os.path.join(ADDON, "HealerThreat.toc"), encoding="utf-8").read().splitlines()
    for line in toc:
        line = line.strip()
        if line and not line.startswith("#"):
            load_file(open(os.path.join(ADDON, line), encoding="utf-8").read(), line, ns)
    L.globals().HealerThreat_Test = L.table(Collect=lambda: ns.Threat.Collect(ns.Threat))
    try:
        L.execute(DRIVER)
    finally:
        for m in L.eval("out").values():
            print("  chat:", m)
    return 0


if __name__ == "__main__":
    sys.exit(main())
