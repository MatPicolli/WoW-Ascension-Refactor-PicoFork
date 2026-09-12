-- Headless regression test for the config window (RefactorUI.lua) against
-- the confirmed real-world failure: a client whose SetAtlas throws for any
-- atlas name it doesn't recognize, instead of quietly returning false.
--
-- Reported live on Project Ebonhold via BugSack:
--   ...SharedExtendedMethods.lua:157: SetAtlas: Atlas named
--   UI-Frame-DiamondMetal-CornerTopLeft-8x does not exist
--   ...RefactorUI.lua:201: in function <RefactorUI.lua:199>   (ApplyAtlas)
--   ...RefactorUI.lua:2268: in function `piece`               (BuildMetalBorder)
--   ...RefactorUI.lua:2651: in function `Toggle`
--
-- Every atlas name this window uses (UI-Frame-DiamondMetal-*, the
-- redbutton kit, the minimal-scrollbar kit) is one Ascension itself added
-- client-side. A client that implements SetAtlas through some other means
-- -- a bundled compatibility shim, in Ebonhold's case -- has no reason to
-- recognize any of them, and this particular shim errors instead of
-- failing quietly. ApplyAtlas's old `if tex.SetAtlas then tex:SetAtlas(...)`
-- had no defense against that: one corner piece throwing took the ENTIRE
-- window down with it, since Lua unwinds the whole call stack on an
-- uncaught error -- every page, checkbox and nav label queued after the
-- failing piece in BuildWindow's single top-to-bottom construction never
-- got created, leaving only whatever had already drawn (the plain
-- background) on screen. Exactly the reported symptom: a big blank panel.
--
-- Run from the addon folder, with any Lua 5.1 (the client's own version):
--     lua5.1 tests/test_ui.lua
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

-- Minimal client scaffolding RefactorUI.lua needs beyond wowmock's default
-- surface: a real chat tooltip pair (used incidentally by shared code
-- paths), a Minimap frame for the minimap button, and the small
-- RefactorCompareShared/RefactorToastShared/RefactorQoL/RefactorCCShared
-- surface this file reads its config through (this test isn't exercising
-- those other modules, so bare stand-ins are enough). Set up once: these
-- don't depend on the atlas scenario, only the addon file itself does.
GameTooltip = CreateFrame("GameTooltip", "GameTooltip")
ItemRefTooltip = CreateFrame("GameTooltip", "ItemRefTooltip")
Minimap = CreateFrame("Frame", "Minimap")
UISpecialFrames = {}
UnitName = function() return "Tester" end
GetRealmName = function() return "Realm" end

RefactorCompareDB = { profiles = { Default = { weights = {}, customWeights = {} } },
    activeProfile = "Default" }
RefactorCompareShared = {
    GetDB = function() return RefactorCompareDB end,
    IsEnabled = function() return false end,
    STATS = {},
    Weights = function() return {} end,
    ActiveProfile = function() return RefactorCompareDB.profiles.Default end,
    GetClassSpecs = function() return nil end,
}
RefactorToastShared = {}
RefactorQoL = { GetDB = function() return {} end }
RefactorCCShared = { GetDB = function() return {} end }

-- RefactorUI.lua builds its window ONCE (a file-scope `local window`,
-- populated lazily the first time Toggle() runs) and just shows/hides it
-- after that -- so testing three different client behaviors needs three
-- independent constructions, not one shared Toggle() call reused three
-- times. loadfile() returns a fresh chunk on every call, which on
-- execution defines entirely new local upvalues (a new `window`, starting
-- nil again) and reassigns the global RefactorUI table outright
-- (`RefactorUI = {}` at file scope) -- so simply re-loading and re-running
-- the file is a clean, independent instance each time.
local function FreshLoad()
    assert(loadfile(ROOT .. "RefactorUI.lua"))()
end

--------------------------------------------------------------------------
print("\n1. baseline: a true stock client with no atlas support at all")
--------------------------------------------------------------------------
-- The window has always been expected to work this way -- ApplyAtlas's
-- other fallback branch. Establishing this passes BEFORE testing the
-- throwing-shim case rules out the fix having broken the ordinary path.
mock.SetAtlasBehavior(nil)
local okLoad, err = pcall(FreshLoad)
ok(okLoad, "RefactorUI.lua loads with no SetAtlas method at all" ..
    (okLoad and "" or (": " .. tostring(err))))
local okToggle, terr = pcall(RefactorUI.Toggle)
ok(okToggle, "Toggle() completes" .. (okToggle and "" or (": " .. tostring(terr))))
ok(RefactorUIWindow and RefactorUIWindow:IsShown(), "and the window is shown")

--------------------------------------------------------------------------
print("\n2. a client whose SetAtlas throws on unrecognized names (Ebonhold-shaped)")
--------------------------------------------------------------------------
mock.SetAtlasBehavior("throws") -- knownAtlases stays empty: recognizes nothing
mock.createdTextures = {}
local okLoad2, lerr2 = pcall(FreshLoad)
ok(okLoad2, "RefactorUI.lua loads" .. (okLoad2 and "" or (": " .. tostring(lerr2))))
local okToggle2, err2 = pcall(RefactorUI.Toggle)
ok(okToggle2, "Toggle() completes without propagating the atlas error" ..
    (okToggle2 and "" or (": " .. tostring(err2))))
ok(RefactorUIWindow and RefactorUIWindow:IsShown(),
    "and the window is fully built and shown, not left half-constructed")

-- The concrete fix: pieces that got a throwing SetAtlas call still end up
-- with SOMETHING visible (the C_BORDER-tinted flat fallback) instead of a
-- texture that was never set at all. Every atlas-based piece in this
-- window hits that fallback here, since knownAtlases is empty -- so this
-- should be a large fraction of everything CreateTexture produced during
-- construction, not one lucky exception. (This is also, incidentally, the
-- proof that construction reached far past the first border corner --
-- the exact point the unguarded version died at -- since only a handful
-- of the textures below belong to the border itself.)
local withFallback, total = 0, 0
for _, tex in ipairs(mock.createdTextures) do
    total = total + 1
    local args = tex.textureArgs
    if args and type(args[1]) == "number" then
        withFallback = withFallback + 1
    end
end
ok(total > 10, "the window created a realistic number of textures (" .. total .. ")")
ok(withFallback > 10,
    withFallback .. " of " .. total .. " textures fell back to a visible flat color "
    .. "instead of staying blank")

--------------------------------------------------------------------------
print("\n3. a client with real, working atlas support")
--------------------------------------------------------------------------
-- Guards the other direction: wrapping SetAtlas in pcall must not turn a
-- client that actually supports these atlases into one that silently
-- skips them for no reason.
mock.SetAtlasBehavior("ok")
local okLoad3, lerr3 = pcall(FreshLoad)
ok(okLoad3, "RefactorUI.lua loads" .. (okLoad3 and "" or (": " .. tostring(lerr3))))
local okToggle3, err3 = pcall(RefactorUI.Toggle)
ok(okToggle3, "Toggle() still completes on a client with full atlas support" ..
    (okToggle3 and "" or (": " .. tostring(err3))))
ok(RefactorUIWindow and RefactorUIWindow:IsShown(), "and the window shows")

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
