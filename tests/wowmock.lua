-- Minimal 3.3.5 client stand-in: enough of the API surface for
-- RefactorCompare/01_profiles.lua, 03_scan.lua and 04_score.lua to load and
-- run headless under lua5.1.

local M = {}

-- Controllable clock -------------------------------------------------------
local now = 1000
function M.Now() return now end
function M.Advance(dt) now = now + dt end
GetTime = function() return now end

-- Item database ------------------------------------------------------------
-- items[link] = { name, quality, reqLevel, itemType, itemSubType, equipLoc }
M.items = {}
GetItemInfo = function(link)
    local it = M.items[link]
    if not it then return nil end
    return it.name, link, it.quality or 3, 0, it.reqLevel or 1,
        it.itemType or "Armor", it.itemSubType or "Plate", 1,
        it.equipLoc or "INVTYPE_CHEST"
end

-- Tooltip renders ----------------------------------------------------------
-- M.render[key] = function() return { {left=, right=} ... } end
-- key is "bag:<b>:<s>", "inv:<slot>", "link:<link>"
M.render = {}
M.renderCount = {}

local function CountRender(key)
    M.renderCount[key] = (M.renderCount[key] or 0) + 1
end

-- Frames -------------------------------------------------------------------
local frameMT = {}
frameMT.__index = frameMT
function frameMT:SetScript(k, fn) self.scripts[k] = fn end
function frameMT:GetScript(k) return self.scripts[k] end
function frameMT:HookScript(k, fn) self.scripts[k] = fn end
function frameMT:Show() self.shown = true end
function frameMT:Hide() self.shown = false end
function frameMT:IsShown() return self.shown end
function frameMT:IsVisible() return self.shown end
function frameMT:RegisterEvent() end
function frameMT:UnregisterAllEvents() end
function frameMT:SetPoint() end
function frameMT:ClearAllPoints() end
function frameMT:SetWidth() end
function frameMT:SetHeight() end
function frameMT:SetSize() end
function frameMT:SetAlpha() end
function frameMT:SetVertexColor() end
function frameMT:SetTexCoord(...) self.texCoord = { ... } end
function frameMT:GetTexCoord() return unpack(self.texCoord or { 0, 0, 0, 1, 1, 0, 1, 1 }) end
function frameMT:SetDesaturated() end
-- Records what was drawn (args as given) so a test can tell "an atlas
-- succeeded" from "fell back to a flat color" from "nothing was ever set".
function frameMT:SetTexture(...) self.textureArgs = { ... }; return true end
function frameMT:GetName() return self.name end
function frameMT:GetID() return self.id or 0 end
function frameMT:GetParent() return self.parent end
function frameMT:SetOwner() end
function frameMT:GetOwner() end
function frameMT:CreateTexture()
    local t = setmetatable({ scripts = {}, shown = false }, frameMT)
    if M.createdTextures then M.createdTextures[#M.createdTextures + 1] = t end
    return t
end
function frameMT:CreateFontString()
    return setmetatable({ scripts = {}, shown = false }, frameMT)
end

-- Generic no-op surface for everything else RefactorUI.lua's widgets call
-- (Frame/Button/EditBox/Slider/FontString/Texture methods alike -- this
-- mock doesn't distinguish object types the way the real client does, so
-- one fat interface covers all of them). Getters return a value shaped
-- like the real one so arithmetic on the result doesn't blow up; setters
-- that matter for a test override individually on the instance.
function frameMT:SetText(t) self.text = t end
function frameMT:GetText() return self.text end
function frameMT:GetStringWidth() return self.text and (#self.text * 6) or 10 end
function frameMT:GetStringHeight() return 12 end
function frameMT:SetTextColor() end
function frameMT:SetJustifyH() end
function frameMT:SetTextInsets() end
function frameMT:SetFontObject() end
function frameMT:SetNormalFontObject() end
function frameMT:SetDisabledFontObject() end
function frameMT:SetFontString() end
function frameMT:SetHighlightTexture() end
function frameMT:SetAllPoints() end
function frameMT:SetFrameStrata() end
function frameMT:SetFrameLevel() end
function frameMT:SetToplevel() end
function frameMT:SetMovable() end
function frameMT:SetClampedToScreen() end
function frameMT:EnableMouse() end
function frameMT:EnableMouseWheel() end
function frameMT:RegisterForDrag() end
function frameMT:RegisterForClicks() end
function frameMT:StartMoving() end
function frameMT:StopMovingOrSizing() end
function frameMT:SetOrientation() end
function frameMT:SetMinMaxValues(lo, hi) self.minV, self.maxV = lo, hi end
function frameMT:SetValueStep() end
function frameMT:SetValue(v) self.value = v end
function frameMT:GetValue() return self.value or 0 end
function frameMT:GetThumbTexture() return nil end
function frameMT:SetScrollChild() end
function frameMT:SetGradientAlpha() end
function frameMT:SetBlendMode() end
function frameMT:SetBackdrop() end
function frameMT:SetBackdropColor() end
function frameMT:SetBackdropBorderColor() end
function frameMT:Enable() self.enabled = true end
function frameMT:Disable() self.enabled = false end
function frameMT:IsEnabled() return self.enabled ~= false end
function frameMT:LockHighlight() end
function frameMT:UnlockHighlight() end
function frameMT:IsMouseOver() return false end
function frameMT:GetCenter() return 0, 0 end
function frameMT:GetEffectiveScale() return 1 end
function frameMT:GetWidth() return self.width or 100 end
function frameMT:GetNumRegions() return 0 end
function frameMT:GetRegions() end
function frameMT:IsObjectType() return false end
function frameMT:SetAutoFocus() end
function frameMT:SetFocus() end
function frameMT:ClearFocus() end
function frameMT:HasFocus() return false end
function frameMT:HighlightText() end
function frameMT:AddLine() end
function frameMT:AddMessage() end

-- Tooltip behavior: lines come from M.render, exposed as the global
-- "<name>TextLeft<i>" / "<name>TextRight<i>" font strings the scanner reads.
-- What the tooltip currently claims to be showing; set M.shownItem or the
-- frame's own .item to drive the (name, link) pair addons read back.
function frameMT:GetItem()
    local it = self.item
    if not it then return nil end
    return it.name, it.link
end
function frameMT:ClearLines() self.lines = {} end
function frameMT:NumLines() return #(self.lines or {}) end
function frameMT:SetLines(lines)
    self.lines = lines or {}
    for i = 1, 40 do
        local l = _G[self.name .. "TextLeft" .. i]
        local r = _G[self.name .. "TextRight" .. i]
        local entry = self.lines[i]
        l.text = entry and entry.left or nil
        l.color = entry and entry.color or { 1, 1, 1 }
        r.text = entry and entry.right or nil
        r.shown = entry ~= nil and entry.right ~= nil
        r.color = entry and entry.rightColor or { 1, 1, 1 }
    end
end
local function Feed(tip, key)
    CountRender(key)
    local fn = M.render[key]
    tip:SetLines(fn and fn() or {})
end
function frameMT:SetBagItem(bag, slot) Feed(self, "bag:" .. bag .. ":" .. slot) end
function frameMT:SetInventoryItem(_, slot) Feed(self, "inv:" .. slot) end
function frameMT:SetHyperlink(link) Feed(self, "link:" .. link) end
function frameMT:SetMerchantItem(i) Feed(self, "merchant:" .. i) end
function frameMT:SetBuybackItem(i) Feed(self, "buyback:" .. i) end
function frameMT:SetLootRollItem(i) Feed(self, "roll:" .. i) end
function frameMT:SetLootItem(i) Feed(self, "loot:" .. i) end
function frameMT:SetQuestItem(t, i) Feed(self, "quest:" .. t .. ":" .. i) end
function frameMT:SetQuestLogItem(t, i) Feed(self, "questlog:" .. t .. ":" .. i) end

local fsMT = {}
fsMT.__index = fsMT
function fsMT:GetText() return self.text end
function fsMT:GetTextColor()
    local c = self.color or { 1, 1, 1 }
    return c[1], c[2], c[3]
end
function fsMT:IsShown() return self.shown end
function fsMT:SetText(t) self.text = t end
function fsMT:SetTextColor() end
function fsMT:Show() self.shown = true end
function fsMT:Hide() self.shown = false end

M.frames = {}
CreateFrame = function(kind, name, parent, template)
    local f = setmetatable({ scripts = {}, shown = false, name = name,
        parent = parent, lines = {} }, frameMT)
    if name then
        _G[name] = f
        if kind == "GameTooltip" then
            for i = 1, 40 do
                _G[name .. "TextLeft" .. i] = setmetatable({}, fsMT)
                _G[name .. "TextRight" .. i] = setmetatable({}, fsMT)
            end
        end
    end
    table.insert(M.frames, f)
    return f
end

-- Drives every frame's OnUpdate for `seconds`, in `step`-sized ticks, the
-- way the client's frame loop would.
function M.Run(seconds, step)
    step = step or 0.05
    local t = 0
    while t < seconds do
        M.Advance(step)
        t = t + step
        for _, f in ipairs(M.frames) do
            local fn = f.shown and f.scripts.OnUpdate
            if fn then fn(f, step) end
        end
    end
end

-- Stock Blizzard globals RefactorUI.lua reads directly (real WotLK client
-- data, not addon-specific) -- present on every 3.3.5-family client this
-- addon targets, Ascension and otherwise, so it belongs in the generic
-- mock rather than a test-specific stub.
ITEM_QUALITY_COLORS = {
    [0] = { r = 0.62, g = 0.62, b = 0.62, hex = "|cff9d9d9d" },
    [1] = { r = 1.00, g = 1.00, b = 1.00, hex = "|cffffffff" },
    [2] = { r = 0.12, g = 1.00, b = 0.00, hex = "|cff1eff00" },
    [3] = { r = 0.00, g = 0.44, b = 0.87, hex = "|cff0070dd" },
    [4] = { r = 0.64, g = 0.21, b = 0.93, hex = "|cffa335ee" },
    [5] = { r = 1.00, g = 0.50, b = 0.00, hex = "|cffff8000" },
    [6] = { r = 0.90, g = 0.80, b = 0.50, hex = "|cffe6cc80" },
    [7] = { r = 0.00, g = 0.80, b = 1.00, hex = "|cff00ccff" },
}
for q = 0, 7 do
    _G["ITEM_QUALITY" .. q .. "_DESC"] = "Quality " .. q
end

-- Everything else the files touch at load or call time --------------------
UIParent = CreateFrame("Frame", "UIParent")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg)
    if M.verbose then print("  [chat] " .. msg) end
end }
tinsert = table.insert
tremove = table.remove
NUM_BAG_SLOTS = 4
NUM_CONTAINER_FRAMES = 1
M.equipped = {}
M.bags = {}
GetInventoryItemLink = function(_, slot) return M.equipped[slot] end
GetContainerItemLink = function(bag, slot) return M.bags[bag .. ":" .. slot] end
GetContainerNumSlots = function() return 16 end
GetContainerItemInfo = function() return nil, nil, false end
GetItemCount = function() return 1 end
IsSpellKnown = function() return true end
GetCombatRating = function() return 0 end
GetCombatRatingBonus = function() return 0 end
CursorHasItem = function() return false end
PickupContainerItem = function() end
EquipCursorItem = function() end
hooksecurefunc = function() end
IsAddOnLoaded = function() return false end

-- Configurable SetAtlas behavior, for testing how atlas-consuming code
-- reacts to different clients:
--   nil/"none" -> no SetAtlas method at all (true stock 3.3.5, no atlas
--                 support whatsoever)
--   "ok"       -> SetAtlas exists and always succeeds (a client with full
--                 atlas support, or one that happens to know every name
--                 this addon asks for)
--   "throws"   -> SetAtlas exists but THROWS for any atlas name not in
--                 M.knownAtlases, instead of quietly returning false --
--                 this is the confirmed, reported shape: a real client
--                 (Project Ebonhold) implements SetAtlas via a third-party
--                 compatibility shim that errors "SetAtlas: Atlas named
--                 X does not exist" for anything it doesn't recognize.
--                 M.knownAtlases stays empty by default, matching the
--                 real case where an Ascension-only atlas name is never
--                 one that shim knows.
M.knownAtlases = {}
M.createdTextures = {}
function M.SetAtlasBehavior(mode)
    if mode == "ok" then
        frameMT.SetAtlas = function(self, atlas) self.atlas = atlas; return true end
    elseif mode == "throws" then
        frameMT.SetAtlas = function(self, atlas)
            if M.knownAtlases[atlas] then self.atlas = atlas; return true end
            error("SetAtlas: Atlas named " .. tostring(atlas) .. " does not exist")
        end
    else
        frameMT.SetAtlas = nil
    end
end
M.SetAtlasBehavior(nil)

UnitName = function() return "Tester" end
GetRealmName = function() return "Bronzebeard" end

-- Class and talent trees. M.class is { displayName, classToken }; M.talentTabs
-- is an ordered list of { name, pointsSpent }, matching GetTalentTabInfo.
M.class = { "Warrior", "WARRIOR" }
M.talentTabs = {}
UnitClass = function() return M.class[1], M.class[2] end
UnitLevel = function() return M.level or 80 end
GetNumTalentTabs = function() return #M.talentTabs end
GetTalentTabInfo = function(i)
    local tab = M.talentTabs[i]
    if not tab then return nil end
    return tab.name, nil, tab.pointsSpent or 0
end
GameTooltip_ClearMoney = function() end

return M
