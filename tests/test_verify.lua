-- Headless tests for the scan-confirmation state machine and the loading
-- spinner — the parts of the gear comparison whose behavior lives in time
-- (samples taken across frames) and can't be eyeballed from the code.
--
-- wowmock.lua stands in for the 3.3.5 client: a controllable clock, an item
-- database, scriptable tooltip renders (including the stale base-item
-- render Ascension's scaling produces), and a frame loop to drive OnUpdate.
--
-- Run from the addon folder, with any Lua 5.1 (the client's own version):
--     lua5.1 tests/test_verify.lua
-- Exits non-zero if anything fails. Nothing here loads in-game — the folder
-- isn't in Refactor.toc.

local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]+$") or "./"
package.path = ROOT .. "tests/?.lua;" .. package.path
local mock = require("wowmock")

local function load(f) assert(loadfile(ROOT .. f))() end

load("RefactorCompare/01_profiles.lua")
local C = RefactorCompareInternal
-- Stand in for the ADDON_LOADED init in 10_config.lua.
RefactorCompareDB = {}
C.MergeDefaults(RefactorCompareDB, C.DEFAULTS)
C.MergeDefaults(RefactorCompareDB.profiles.Default.weights, C.DEFAULT_WEIGHTS)
load("RefactorCompare/03_scan.lua")
load("RefactorCompare/04_score.lua")

local pass, fail = 0, 0
local function ok(cond, what)
    if cond then pass = pass + 1; print("  ok   " .. what)
    else fail = fail + 1; print("  FAIL " .. what) end
end
local function eq(a, b, what)
    ok(a == b, what .. "  (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end

local function lines(ilvl, req, armor, str)
    return {
        { left = "Scaled Chestplate" },
        { left = "Item Level " .. ilvl },
        { left = "Binds when picked up" },
        { left = "Chest", right = "Plate" },
        { left = armor .. " Armor" },
        { left = "+" .. str .. " Strength" },
        { left = "Requires Level " .. req },
    }
end

local LINK = "|Hitem:1234|h[Scaled Chestplate]|h"
mock.items[LINK] = { name = "Scaled Chestplate", quality = 3,
    equipLoc = "INVTYPE_CHEST", itemType = "Armor", itemSubType = "Plate" }
-- The base item the client falls back to: ilvl 40, 200 armor, +10 Strength.
mock.render["link:" .. LINK] = function() return lines(40, 35, 200, 10) end

--------------------------------------------------------------------------
print("\n1. a stable scaled instance confirms on the second spaced sample")
--------------------------------------------------------------------------
mock.bags["0:1"] = LINK
mock.render["bag:0:1"] = function() return lines(60, 55, 336, 20) end

local s1 = C.ScanItem(LINK, 0, 1)
ok(not s1.failed, "first sample reads")
eq(s1.stats.strength, 20, "scaled Strength parsed")
eq(s1.confirmed, false, "one sample is not enough to confirm")
eq(s1.pending, true, "so the scan reports as pending")

-- Back-to-back re-read: same numbers, but no time has passed, so it proves
-- nothing and must not confirm.
local s2 = C.ScanItem(LINK, 0, 1, nil, nil, true)
eq(s2.confirmed, false, "an immediate re-read does not confirm")

mock.Advance(0.25)
local s3 = C.ScanItem(LINK, 0, 1, nil, nil, true)
eq(s3.confirmed, true, "a sample taken after the gap confirms")
eq(s3.pending, nil, "confirmed scans are not pending")

--------------------------------------------------------------------------
print("\n2. a confirmed scan is served from cache without re-rendering")
--------------------------------------------------------------------------
local before = mock.renderCount["bag:0:1"]
for _ = 1, 50 do C.ScanItem(LINK, 0, 1) end
eq(mock.renderCount["bag:0:1"], before, "50 lookups, 0 extra tooltip renders")

--------------------------------------------------------------------------
print("\n3. the stale base render is caught instead of scored")
--------------------------------------------------------------------------
mock.bags["0:2"] = LINK
-- Classic Ascension symptom: scaled item level and required level, but the
-- stats still come back as the base item's.
mock.render["bag:0:2"] = function() return lines(60, 55, 200, 10) end
local stale = C.ScanItem(LINK, 0, 2)
eq(stale.failed, true, "a scaled instance rendering base stats is rejected")
eq(stale.giveUp, false, "and is worth retrying")

-- Same slot, armor alone stale (the case the addon already knew about).
mock.render["bag:0:2"] = function() return lines(60, 55, 200, 20) end
mock.Advance(0.5)
local staleArmor = C.ScanItem(LINK, 0, 2, nil, nil, true)
eq(staleArmor.failed, true, "a base armor value on a scaled instance is rejected")

-- Real numbers arrive: now it reads, and confirms on the next spaced sample.
mock.render["bag:0:2"] = function() return lines(60, 55, 336, 20) end
mock.Advance(0.5)
local good = C.ScanItem(LINK, 0, 2, nil, nil, true)
eq(good.failed, false, "the corrected render is accepted")
eq(good.confirmed, false, "but only provisionally")
mock.Advance(0.25)
eq(C.ScanItem(LINK, 0, 2, nil, nil, true).confirmed, true, "and confirms after that")

--------------------------------------------------------------------------
print("\n4. stats changing under a confirmed scan resets confirmation")
--------------------------------------------------------------------------
mock.render["bag:0:1"] = function() return lines(70, 65, 400, 28) end
mock.Advance(0.5)
local moved = C.ScanItem(LINK, 0, 1, nil, nil, true)
eq(moved.stats.strength, 28, "new numbers are picked up")
eq(moved.confirmed, false, "a changed signature starts confirmation over")
mock.Advance(0.25)
eq(C.ScanItem(LINK, 0, 1, nil, nil, true).confirmed, true, "then re-confirms")

--------------------------------------------------------------------------
print("\n5. an item the client never renders gives up instead of spinning")
--------------------------------------------------------------------------
mock.bags["0:3"] = LINK
mock.render["bag:0:3"] = function() return {} end
local last
for _ = 1, 8 do
    last = C.ScanItem(LINK, 0, 3, nil, nil, true)
    mock.Advance(0.3)
end
eq(last.failed, true, "still unreadable")
eq(last.giveUp, true, "and has stopped asking")

--------------------------------------------------------------------------
print("\n6. verdicts carry the pending flag, and only settle once confirmed")
--------------------------------------------------------------------------
-- Something worn to compare against, confirmed up front.
local EQ = "|Hitem:9999|h[Old Chestplate]|h"
mock.items[EQ] = { name = "Old Chestplate", quality = 2,
    equipLoc = "INVTYPE_CHEST", itemType = "Armor", itemSubType = "Plate" }
mock.equipped[5] = EQ
mock.render["link:" .. EQ] = function() return lines(30, 25, 150, 5) end
mock.render["inv:5"] = function() return lines(45, 40, 220, 8) end
for _ = 1, 3 do C.ScanItem(EQ, nil, nil, 5, nil, true); mock.Advance(0.3) end

mock.bags["0:4"] = LINK
mock.render["bag:0:4"] = function() return lines(60, 55, 336, 20) end
local v1, p1 = C.CompareItem(LINK, 0, 4)
ok(v1 ~= nil, "a verdict is produced from the very first read")
eq(v1.status, "upgrade", "and it says upgrade")
eq(v1.pending, true, "flagged provisional until confirmed")
eq(p1, true, "second return mirrors it")

mock.Advance(0.3)
local v2, p2 = C.CompareItem(LINK, 0, 4)
eq(v2.pending, nil, "confirmed on the next look")
eq(p2, false, "and reports settled")

--------------------------------------------------------------------------
print("\n7. the verifier settles items on its own clock")
--------------------------------------------------------------------------
mock.bags["0:5"] = LINK
mock.render["bag:0:5"] = function() return lines(60, 55, 336, 20) end
local first = C.ScanItem(LINK, 0, 5)
eq(first.confirmed, false, "starts unconfirmed")
-- Nothing looks at the item again; only the background verifier runs.
mock.Run(1.0)
local settled = C.ScanItem(LINK, 0, 5)
eq(settled.confirmed, true, "the verifier confirmed it with no UI involvement")

--------------------------------------------------------------------------
print("\n8. a bag change re-verifies without throwing the scan away")
--------------------------------------------------------------------------
local rendersBefore = mock.renderCount["bag:0:5"]
local entry = C.scanCache["b:0:5:" .. LINK]
ok(entry ~= nil, "the confirmed scan is still cached")
eq(C.MarkScanUnconfirmed("b:0:5:" .. LINK, entry), true, "flush marks it unconfirmed")
eq(entry.pending, true, "so it reads as pending again")
eq(C.ScanItem(LINK, 0, 5).stats.strength, 20,
    "and still answers immediately from the cached numbers")
eq(mock.renderCount["bag:0:5"], rendersBefore, "with no re-render to do it")
mock.Run(0.6)
eq(mock.renderCount["bag:0:5"], rendersBefore + 1,
    "exactly one confirming render for an unchanged item")
eq(C.ScanItem(LINK, 0, 5).confirmed, true, "confirmed again")

--------------------------------------------------------------------------
print("\n9. turning confirmation off restores single-read behavior")
--------------------------------------------------------------------------
RefactorCompareDB.scanVerify = false
C.WipeScanCache()
local once = C.ScanItem(LINK, 0, 1)
eq(once.confirmed, true, "one read is final")
eq(once.pending, nil, "nothing is ever pending")
RefactorCompareDB.scanVerify = true

--------------------------------------------------------------------------
print("\n10. the loading spinner")
--------------------------------------------------------------------------
GameTooltip = CreateFrame("GameTooltip", "GameTooltip")
ItemRefTooltip = CreateFrame("GameTooltip", "ItemRefTooltip")
load("RefactorCompare/05_tooltip.lua")
load("RefactorCompare/06_bagicons.lua")
ok(type(C.SpinnerShow) == "function", "05_tooltip loads and exports the spinner")

local button = CreateFrame("Frame", "MockBagButton")
button.shown = true
C.SpinnerShow(button, "refactorSpinner", button, "TOPRIGHT", -8, -9)
local sp = button.refactorSpinner
ok(sp ~= nil, "a spinner is attached to the button")
eq(sp.dots[1].shown, false, "nothing is drawn immediately (no flicker)")

mock.Run(0.2)
eq(sp.dots[1].shown, false, "still nothing while the wait is short")
mock.Run(0.4)
eq(sp.dots[1].shown, true, "dots appear once the comparison is actually slow")
eq(sp.dots[3].shown, true, "all three of them")

-- Re-asserting while it runs must not restart the reveal delay.
C.SpinnerShow(button, "refactorSpinner", button, "TOPRIGHT", -8, -9)
mock.Run(0.1)
eq(sp.dots[1].shown, true, "a redraw does not reset it back to hidden")

C.SpinnerHide(button, "refactorSpinner")
eq(sp.dots[1].shown, false, "hiding stops it")
mock.Run(0.3)
eq(sp.dots[1].shown, false, "and it stays stopped")

-- An owner that disappears while still pending (bag closed, tooltip gone)
-- must release the spinner rather than animate against a hidden anchor.
C.SpinnerShow(button, "refactorSpinner", button, "TOPRIGHT", -8, -9)
mock.Run(0.5)
eq(sp.dots[1].shown, true, "running again")
button.shown = false
mock.Run(0.1)
eq(sp.dots[1].shown, false, "an anchor that goes away stops the spinner")
eq(sp.active, nil, "and releases its slot in the budget")
button.shown = true

RefactorCompareDB.compareSpinner = false
C.SpinnerShow(button, "refactorSpinner", button, "TOPRIGHT", -8, -9)
mock.Run(0.6)
eq(sp.dots[1].shown, false, "turned off, nothing is ever drawn")
RefactorCompareDB.compareSpinner = true

--------------------------------------------------------------------------
print("\n11. a full bag wall settles quickly and stops working when done")
--------------------------------------------------------------------------
C.WipeScanCache()
local SLOTS = 100
for i = 1, SLOTS do
    mock.bags["1:" .. i] = LINK
    mock.render["bag:1:" .. i] = function() return lines(60, 55, 336, 20) end
    mock.renderCount["bag:1:" .. i] = 0
end
-- One redraw's worth of first looks, the way opening a bag would.
for i = 1, SLOTS do C.ScanItem(LINK, 1, i) end

local start = mock.Now()
local settleTime
for _ = 1, 200 do
    mock.Run(0.05, 0.05)
    local done = true
    for i = 1, SLOTS do
        local e = C.scanCache["b:1:" .. i .. ":" .. LINK]
        if not (e and e.confirmed) then done = false break end
    end
    if done then settleTime = mock.Now() - start break end
end
ok(settleTime ~= nil and settleTime < 1.5,
    string.format("all %d slots confirmed in %.2fs", SLOTS, settleTime or -1))

local total = 0
for i = 1, SLOTS do total = total + mock.renderCount["bag:1:" .. i] end
eq(total, SLOTS * 2, "exactly two renders per item — the first look plus one confirmation")

-- With nothing left unconfirmed the verifier must stop costing anything.
mock.Run(1.0)
local after = 0
for i = 1, SLOTS do after = after + mock.renderCount["bag:1:" .. i] end
eq(after, total, "and no further renders once everything is settled")

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
