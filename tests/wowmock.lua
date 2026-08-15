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
function frameMT:SetTexCoord() end
function frameMT:SetDesaturated() end
function frameMT:SetTexture() return true end
function frameMT:GetName() return self.name end
function frameMT:GetID() return self.id or 0 end
function frameMT:GetParent() return self.parent end
function frameMT:SetOwner() end
function frameMT:GetOwner() end
function frameMT:CreateTexture()
    return setmetatable({ scripts = {}, shown = false }, frameMT)
end
function frameMT:CreateFontString()
    return setmetatable({ scripts = {}, shown = false,
        SetText = function() end, GetStringWidth = function() return 10 end },
        frameMT)
end

-- Tooltip behavior: lines come from M.render, exposed as the global
-- "<name>TextLeft<i>" / "<name>TextRight<i>" font strings the scanner reads.
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
UnitName = function() return "Tester" end
GetRealmName = function() return "Bronzebeard" end
GameTooltip_ClearMoney = function() end

return M
