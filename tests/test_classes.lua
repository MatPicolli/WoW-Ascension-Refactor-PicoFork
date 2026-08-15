-- Headless tests for the class/spec default weights: that every entry in
-- both rosters is well formed, that a classic character's spec is detected
-- from the stock talent tabs, and that the profile it seeds survives the
-- name round-trip the "reset to defaults" and rename paths depend on.
--
-- Run from the addon folder, with any Lua 5.1 (the client's own version):
--     lua5.1 tests/test_classes.lua
-- Exits non-zero if anything fails. Nothing here loads in-game — the folder
-- isn't in Refactor.toc.

local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]+$") or "./"
package.path = ROOT .. "tests/?.lua;" .. package.path
local mock = require("wowmock")

local function load(f) assert(loadfile(ROOT .. f))() end
load("RefactorCompare/01_profiles.lua")
local C = RefactorCompareInternal
RefactorCompareDB = {}
C.MergeDefaults(RefactorCompareDB, C.DEFAULTS)
C.MergeDefaults(RefactorCompareDB.profiles.Default.weights, C.DEFAULT_WEIGHTS)
-- Owned by 10_config.lua / 06_bagicons.lua, which this test doesn't need.
C.RefreshConfig = function() end
C.RefreshOpenBags = function() end
load("RefactorCompare/02_classspec.lua")

local pass, fail = 0, 0
local function ok(cond, what)
    if cond then pass = pass + 1; print("  ok   " .. what)
    else fail = fail + 1; print("  FAIL " .. what) end
end
local function eq(a, b, what)
    ok(a == b, what .. "  (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end

local W = C.CLASS_SPEC_WEIGHTS

--------------------------------------------------------------------------
print("\n1. every weight key in every roster is a real stat")
--------------------------------------------------------------------------
-- A typo here is invisible in game: the weight is simply never applied and
-- the stat silently scores zero, which is exactly the class of bug worth
-- catching from outside the client.
local known = {}
for _, s in ipairs(C.STATS) do known[s.key] = true end
local badKeys, specCount, classCount = {}, 0, 0
for classKey, specs in pairs(W) do
    classCount = classCount + 1
    for _, spec in ipairs(specs) do
        specCount = specCount + 1
        for key, value in pairs(spec.weights) do
            if not known[key] then
                table.insert(badKeys, classKey .. "/" .. spec.name .. ": " .. key)
            elseif type(value) ~= "number" then
                table.insert(badKeys, classKey .. "/" .. spec.name .. ": " .. key .. " is not a number")
            end
        end
    end
end
ok(#badKeys == 0, "no unknown weight keys" ..
    (#badKeys > 0 and (" -- " .. table.concat(badKeys, ", ")) or ""))
ok(specCount > 100, "checked " .. specCount .. " specs across " .. classCount .. " class keys")

--------------------------------------------------------------------------
print("\n2. the ten classic classes are all present")
--------------------------------------------------------------------------
local CLASSIC = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
for _, key in ipairs(CLASSIC) do
    local specs = W[key]
    ok(specs ~= nil and #specs >= 3, key .. " has " ..
        (specs and #specs or 0) .. " specs")
end
-- Both spellings of the Death Knight key have to resolve: the class token is
-- DEATHKNIGHT, but the reset/rename paths rebuild the key from the display
-- name "Death Knight".
eq(W.DEATH_KNIGHT, W.DEATHKNIGHT, "DEATH_KNIGHT aliases DEATHKNIGHT")

--------------------------------------------------------------------------
print("\n3. the CoA roster is untouched")
--------------------------------------------------------------------------
for _, key in ipairs({ "BARBARIAN", "KNIGHT_OF_XOROTH", "SUN_CLERIC",
    "WITCH_HUNTER", "STARCALLER" }) do
    ok(W[key] ~= nil, key .. " still resolves")
end
eq(#W.STARCALLER, 4, "Starcaller still has its four specs")

--------------------------------------------------------------------------
print("\n4. a classic spec is detected from the stock talent tabs")
--------------------------------------------------------------------------
local function LoginAs(display, token, tabs, level)
    mock.class = { display, token }
    mock.talentTabs = tabs
    mock.level = level or 80
    RefactorCompareDB.charManualProfile = {}
    RefactorCompareDB.charAutoProfile = {}
    RefactorCompareDB.charProfiles = {}
    RefactorCompareDB.charManualArmor = {}
    C.AutoApplyClassSpec()
    return RefactorCompareDB.activeProfile
end

eq(LoginAs("Warrior", "WARRIOR", {
    { name = "Arms", pointsSpent = 3 },
    { name = "Fury", pointsSpent = 51 },
    { name = "Protection", pointsSpent = 17 },
}), "Warrior - Fury", "a fury warrior gets the fury profile")

eq(LoginAs("Death Knight", "DEATHKNIGHT", {
    { name = "Blood", pointsSpent = 17 },
    { name = "Frost", pointsSpent = 51 },
    { name = "Unholy", pointsSpent = 3 },
}), "Death Knight - Frost", "a death knight resolves through its own token")

eq(LoginAs("Druid", "DRUID", {
    { name = "Balance", pointsSpent = 0 },
    { name = "Feral Combat", pointsSpent = 55 },
    { name = "Restoration", pointsSpent = 16 },
}), "Druid - Feral Combat",
    "a talent tab name with a space matches its underscored entry")

-- Before level 10 there are no points anywhere; the first listed spec is the
-- placeholder, exactly as it is for the CoA classes.
eq(LoginAs("Mage", "MAGE", {
    { name = "Arcane", pointsSpent = 0 },
    { name = "Fire", pointsSpent = 0 },
    { name = "Frost", pointsSpent = 0 },
}, 4), "Mage - Arcane", "a fresh character falls back to the first spec")

--------------------------------------------------------------------------
print("\n5. the seeded profile carries the spec's weights")
--------------------------------------------------------------------------
LoginAs("Priest", "PRIEST", { { name = "Shadow", pointsSpent = 57 } })
local shadow = RefactorCompareDB.profiles["Priest - Shadow"]
ok(shadow ~= nil, "the profile was created")
eq(shadow.weights.SP, 1, "spell power weight seeded")
ok(shadow.weights.SPI > shadow.weights.INT,
    "shadow values spirit over intellect, as its talents make it")
-- Stats the spec doesn't list must be zeroed, not left to the generic
-- defaults, or a caster profile would quietly value strength.
eq(shadow.weights.STR, 0, "unlisted stats are zeroed")

--------------------------------------------------------------------------
print("\n6. the armor filter follows the class")
--------------------------------------------------------------------------
LoginAs("Rogue", "ROGUE", { { name = "Combat", pointsSpent = 51 } })
local at = RefactorCompareDB.armorTypes
ok(at.Leather and at.Cloth and not at.Mail and not at.Plate,
    "a rogue is filtered to leather and cloth")
LoginAs("Death Knight", "DEATHKNIGHT", { { name = "Blood", pointsSpent = 51 } })
at = RefactorCompareDB.armorTypes
ok(at.Plate and at.Mail and not at.Leather and not at.Cloth,
    "a death knight is filtered to plate and mail (alias key resolves)")

--------------------------------------------------------------------------
print("\n7. profile names round-trip back to their defaults")
--------------------------------------------------------------------------
-- "reset to defaults" rebuilds the lookup key from the profile NAME, so
-- every class and spec has to survive display-name -> key normalization.
-- This is what silently broke for underscored spec names in the past.
local misses = {}
for classKey, specs in pairs(W) do
    if classKey ~= "DEATH_KNIGHT" then -- the alias, same table as DEATHKNIGHT
        for _, spec in ipairs(specs) do
            local display = spec.name:gsub("_", " ")
            local rebuiltClass = C.NormalizeClassKey(classKey:gsub("_", " "))
            local list = W[rebuiltClass] or W[classKey]
            local found = false
            for _, s in ipairs(list or {}) do
                if s.name:lower() == display:lower():gsub(" ", "_") then found = true end
            end
            if not found then
                table.insert(misses, classKey .. " - " .. display)
            end
        end
    end
end
ok(#misses == 0, "every spec name survives the name round-trip" ..
    (#misses > 0 and (" -- " .. table.concat(misses, ", ")) or ""))

-- And the real thing, end to end, on a classic class.
LoginAs("Druid", "DRUID", { { name = "Feral Combat", pointsSpent = 55 } })
C.ActiveProfile().weights.AGI = 99
eq(C.ResetActiveProfileWeights(), true, "reset finds the druid's defaults")
eq(C.ActiveProfile().weights.AGI, W.DRUID[2].weights.AGI, "and restores them")

--------------------------------------------------------------------------
print("\n8. role variants are offered but never auto-picked")
--------------------------------------------------------------------------
-- 3.3.5 has one Feral Combat tab for both cat and bear, so the tank entry
-- can only ever be a deliberate choice.
local labels = {}
LoginAs("Druid", "DRUID", { { name = "Feral Combat", pointsSpent = 55 } })
for _, s in ipairs(C.GetClassSpecs()) do labels[s.label] = s.profileName end
ok(labels["Feral Tank"] == "Druid - Feral Tank", "the bear variant is in the picker")
eq(RefactorCompareDB.activeProfile, "Druid - Feral Combat",
    "but auto-detection still lands on the cat")
C.SelectSpecProfile("Feral Tank")
eq(RefactorCompareDB.activeProfile, "Druid - Feral Tank", "picking it switches over")
local bear = RefactorCompareDB.profiles["Druid - Feral Tank"]
ok(bear.weights.STA > bear.weights.AGI, "and it actually values stamina")
-- A deliberate pick has to survive the next login, or a bear would be put
-- back into cat weights every time it zoned.
C.AutoApplyClassSpec()
eq(RefactorCompareDB.activeProfile, "Druid - Feral Tank", "and auto-selection leaves it alone")

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
