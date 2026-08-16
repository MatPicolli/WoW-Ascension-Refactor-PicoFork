-- Headless tests for the slash-command surface, run against the full
-- ten-file load order rather than the handful of files the other suites
-- need. Two things are being guarded here: that every RefactorCompare file
-- still loads and initializes in order (a nil call at load takes the whole
-- addon down in game, with nothing but a Lua error to go on), and that the
-- commands do what they say -- particularly /rfc rescan, whose entire job
-- is to leave no cached state behind.
--
-- Run from the addon folder, with any Lua 5.1 (the client's own version):
--     lua5.1 tests/test_commands.lua
-- Exits non-zero if anything fails. Nothing here loads in-game — the folder
-- isn't in Refactor.toc.

local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]+$") or "./"
package.path = ROOT .. "tests/?.lua;" .. package.path
local mock = require("wowmock")

local pass, fail = 0, 0
local function ok(cond, what)
    if cond then pass = pass + 1; print("  ok   " .. what)
    else fail = fail + 1; print("  FAIL " .. what) end
end
local function eq(a, b, what)
    ok(a == b, what .. "  (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end

-- Client globals the later files touch at load that the other suites don't need.
GameTooltip = CreateFrame("GameTooltip", "GameTooltip")
ItemRefTooltip = CreateFrame("GameTooltip", "ItemRefTooltip")
MAX_NUM_ITEMS, MERCHANT_ITEMS_PER_PAGE, NUM_GROUP_LOOT_FRAMES = 10, 10, 4
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
SlashCmdList = {}

--------------------------------------------------------------------------
print("\n1. every RefactorCompare file loads, in .toc order")
--------------------------------------------------------------------------
local FILES = {
    "01_profiles", "02_classspec", "03_scan", "04_score", "05_tooltip",
    "06_bagicons", "07_questroll", "08_merchant", "09_lootalert", "10_config",
}
for _, name in ipairs(FILES) do
    local path = "RefactorCompare/" .. name .. ".lua"
    local chunk, err = loadfile(ROOT .. path)
    if chunk then
        local good, runErr = pcall(chunk)
        ok(good, path .. (good and "" or ": " .. tostring(runErr)))
    else
        ok(false, path .. ": " .. tostring(err))
    end
    -- 01 creates the saved variable's defaults; the ADDON_LOADED handler in
    -- 10 would normally do this, but 03 onward reads RefactorCompareDB at
    -- load time.
    if name == "01_profiles" then
        local C = RefactorCompareInternal
        RefactorCompareDB = {}
        C.MergeDefaults(RefactorCompareDB, C.DEFAULTS)
        C.MergeDefaults(RefactorCompareDB.profiles.Default.weights, C.DEFAULT_WEIGHTS)
    end
end

local C = RefactorCompareInternal
local Slash = SlashCmdList.REFACTORCOMPARE
ok(type(Slash) == "function", "the slash handler is registered")
eq(SLASH_REFACTORCOMPARE1, "/rfc", "under /rfc")

--------------------------------------------------------------------------
print("\n2. /rfc rescan clears every cache it promises to")
--------------------------------------------------------------------------
local LINK = "|Hitem:1234|h[Scaled Chestplate]|h"
mock.items[LINK] = { name = "Scaled Chestplate", quality = 3,
    equipLoc = "INVTYPE_CHEST", itemType = "Armor", itemSubType = "Plate" }
local function lines(ilvl, req, armor, str)
    return {
        { left = "Scaled Chestplate" },
        { left = "Item Level " .. ilvl },
        { left = "Chest", right = "Plate" },
        { left = armor .. " Armor" },
        { left = "+" .. str .. " Strength" },
        { left = "Requires Level " .. req },
    }
end
mock.render["link:" .. LINK] = function() return lines(40, 35, 200, 10) end
mock.bags["0:1"] = LINK
mock.render["bag:0:1"] = function() return lines(60, 55, 336, 20) end

-- Warm everything: a confirmed scan, its signature history, a verdict.
mock.equipped[5] = LINK
mock.render["inv:5"] = function() return lines(50, 45, 260, 14) end
for _ = 1, 3 do
    C.ScanItem(LINK, 0, 1, nil, nil, true)
    C.ScanItem(LINK, nil, nil, 5, nil, true)
    mock.Advance(0.3)
end
C.CompareItem(LINK, 0, 1)
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
ok(count(C.scanCache) > 0, "scans are cached before the rescan")
ok(count(C.scanSigs) > 0, "sample history is kept before the rescan")
local genBefore = C.generation

Slash("rescan")

eq(count(C.scanCache), 0, "every cached scan is gone")
eq(count(C.scanSigs), 0, "and so is its sample history")
eq(count(C.verdictCache), 0, "no verdict survives either")
ok(C.generation > genBefore, "the memo generation moved, so equipped scores recompute")

-- And the next look genuinely re-reads the item rather than answering from
-- something the wipe missed.
local rendersBefore = mock.renderCount["bag:0:1"]
local fresh = C.ScanItem(LINK, 0, 1)
eq(mock.renderCount["bag:0:1"], rendersBefore + 1, "the next scan re-renders the tooltip")
eq(fresh.confirmed, false, "and starts confirmation over from one sample")

--------------------------------------------------------------------------
print("\n3. rescan is reachable the ways a macro would reach it")
--------------------------------------------------------------------------
ok(type(RefactorCompareShared.Rescan) == "function",
    "RefactorCompareShared.Rescan() exists for /run and other addons")
C.ScanItem(LINK, 0, 1)
local dropped = RefactorCompareShared.Rescan()
ok(type(dropped) == "number" and dropped > 0,
    "it reports how many scans it dropped (" .. tostring(dropped) .. ")")
eq(count(C.scanCache), 0, "and clears the cache the same way")
C.ScanItem(LINK, 0, 1)
Slash("refresh")
eq(count(C.scanCache), 0, "/rfc refresh is accepted as an alias")

--------------------------------------------------------------------------
print("\n4. rescan drops the verdict drawn on an open tooltip")
--------------------------------------------------------------------------
-- The client won't re-fire OnTooltipSetItem for a tooltip it is already
-- showing, so without this the percentage under the cursor would outlive
-- the wipe.
GameTooltip.shown = true
GameTooltip.refactorCompareDone = LINK
GameTooltip.refactorOwnLine = 7
Slash("rescan")
eq(GameTooltip.refactorCompareDone, nil, "the handled-this-link guard is cleared")
eq(GameTooltip.refactorOwnLine, nil, "and the line the addon owned is forgotten")
GameTooltip.shown = false

--------------------------------------------------------------------------
print("\n5. the other commands run without erroring")
--------------------------------------------------------------------------
-- Toggles are checked for their effect; the rest just have to not blow up,
-- which is what a typo in a rarely-typed branch would do.
local before = RefactorCompareDB.compareSpinner
Slash("spinner")
ok(RefactorCompareDB.compareSpinner ~= before, "spinner toggles")
Slash("spinner")
eq(RefactorCompareDB.compareSpinner, before, "and toggles back")

Slash("verify")
eq(RefactorCompareDB.scanVerify, false, "verify turns confirmation off")
Slash("verify")
eq(RefactorCompareDB.scanVerify, true, "and back on")

for _, cmd in ipairs({ "", "toggle", "toggle", "alert", "alert", "bagicons",
    "bagicons", "quality 3", "quality", "weight AGI 2", "weight nonsense 1",
    "hitcap melee", "hitcap pvp", "hitcap off", "hitcap bogus",
    "profile list", "profile save Scratch", "profile Scratch",
    "secondary", "secondary Scratch", "secondary off", "profile delete Scratch",
    "debug", "debug", "auto", "gibberish" }) do
    local good, err = pcall(Slash, cmd)
    ok(good, "/rfc " .. (cmd == "" and "(no args)" or cmd)
        .. (good and "" or " -- " .. tostring(err)))
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
