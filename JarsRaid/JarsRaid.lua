-- JarsRaid.lua  v1.0.0
-- Clean, from-scratch raid frames.
-- * Same visual style as JarsRaidFrames (dark bg, 4-texture borders, class colours, role icons)
-- * Conventional AuraDataByIndex filters — no Blizzard-hook cache needed
-- * 5 independent, configurable aura placement slots per frame
--     Each slot: position (5 choices), count, filter string, icon size
-- * Debuff-type coloured borders (Magic=blue, Curse=purple, Poison=green, Disease=brown)
-- * /jr  or  /jarsraid  opens the config panel

-- ─────────────────────────────────────────────────────────────────────────────
-- Saved variables & defaults
-- ─────────────────────────────────────────────────────────────────────────────
JarsRaidDB = JarsRaidDB or {}

local DEFAULTS = {
    frameWidth      = 90,
    frameHeight     = 32,
    borderSize      = 6,
    borderColor     = { r = 0,   g = 0,   b = 0,   a = 1 },
    showNames       = true,
    showClassColors = true,
    showRoleIcon    = true,
    font            = "Fonts\\FRIZQT__.TTF",
    fontSize        = 10,
    fontShadow      = false,
    nameAnchor      = "CENTER",      -- CENTER | TOP_LEFT | TOP_RIGHT | BOTTOM_LEFT | BOTTOM_RIGHT
    nameFontSize    = 10,
    nameOutline     = "NONE",        -- NONE | OUTLINE | THICKOUTLINE
    texture         = "Flat",
    columns         = 5,
    padding         = 4,
    layoutDirection = "HORIZONTAL",  -- "HORIZONTAL" = fill row-by-row; "VERTICAL" = fill column-by-column
    sortBy          = "ROLE",        -- "ROLE" | "CLASS" | "GROUP" | "NAME"
    sortByName      = true,
    useInParty      = true,
    locked          = false,
    hideBlizzardFrames = true,
    threatBorder    = false,  -- Red/orange border overlay when a unit has high threat
    showRangeAlpha  = true,   -- Fade out-of-range frames
    rangeAlpha      = 30,     -- Alpha % for out-of-range frames (0-100)
    -- 5 aura placement slots (icons within each slot are always horizontal)
    slots = {
        [1] = { enabled = true,  position = "BOTTOM_RIGHT", count = 6, filter = "HELPFUL|RAID",   iconSize = 14 },
        [2] = { enabled = true,  position = "BOTTOM_LEFT",  count = 3, filter = "HARMFUL",        iconSize = 14 },
        [3] = { enabled = false, position = "TOP_RIGHT",    count = 4, filter = "HELPFUL|PLAYER", iconSize = 12 },
        [4] = { enabled = false, position = "TOP_LEFT",     count = 4, filter = "HELPFUL",        iconSize = 12 },
        [5] = { enabled = false, position = "CENTER",       count = 3, filter = "HARMFUL",        iconSize = 12 },
    },
    -- Boss frames
    bossEnabled     = false,
    bossAttach      = "LEFT",   -- "LEFT" | "TOP"
    bossFrameWidth  = 90,
    bossFrameHeight = 32,
    bossCount       = 5,        -- how many boss frames to show (1-5)
    -- My Frame: independent aura config applied only to THIS player's raid frame
    myFrameEnabled = false,
    mySlots = {
        [1] = { enabled = true,  position = "BOTTOM_RIGHT", count = 4, filter = "HELPFUL|PLAYER", iconSize = 14 },
        [2] = { enabled = false, position = "BOTTOM_LEFT",  count = 3, filter = "HARMFUL",        iconSize = 14 },
        [3] = { enabled = false, position = "TOP_RIGHT",    count = 3, filter = "HELPFUL",        iconSize = 12 },
        [4] = { enabled = false, position = "TOP_LEFT",     count = 3, filter = "HELPFUL",        iconSize = 12 },
        [5] = { enabled = false, position = "CENTER",       count = 3, filter = "HARMFUL",        iconSize = 12 },
    },
    -- HoT Frames: 4 centralized icon slots for tracking specific healer HoTs/buffs (up to 3 spells per slot)
    hotFrames = {
        [1] = { enabled = true,  spell1 = 0, spell2 = 0, spell3 = 0, iconSize = 14 },
        [2] = { enabled = false, spell1 = 0, spell2 = 0, spell3 = 0, iconSize = 14 },
        [3] = { enabled = false, spell1 = 0, spell2 = 0, spell3 = 0, iconSize = 14 },
        [4] = { enabled = false, spell1 = 0, spell2 = 0, spell3 = 0, iconSize = 14 },
    },
    hotFramesPadding = 30,  -- horizontal spacing between HoT icons (pixels)
    -- Container position (saved on move)
    posX = 0,
    posY = 100,
}

-- Maximum icons we pre-allocate per slot (hard cap; user count is capped here too)
local MAX_SLOT_ICONS = 10

-- ─────────────────────────────────────────────────────────────────────────────
-- Dark UI palette (same as JarsRaidFrames)
-- ─────────────────────────────────────────────────────────────────────────────
local UI = {
    bg        = { 0.10, 0.10, 0.12, 0.95 },
    header    = { 0.13, 0.13, 0.16, 1    },
    accent    = { 1.0,  0.55, 0.0,  1    },
    accentDim = { 0.70, 0.35, 0.0,  1    },
    text      = { 0.90, 0.90, 0.90, 1    },
    textDim   = { 0.55, 0.55, 0.58, 1    },
    border    = { 0.22, 0.22, 0.26, 1    },
    btnNormal = { 0.18, 0.18, 0.22, 1    },
    btnHover  = { 0.24, 0.24, 0.28, 1    },
    btnPress  = { 0.14, 0.14, 0.17, 1    },
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Module state
-- ─────────────────────────────────────────────────────────────────────────────
local raidFrames     = {}
local containerFrame = nil
local bossFrames     = {}   -- up to 5 boss unit frames
local bossContainer  = nil  -- parent frame for boss frames
local configFrame    = nil
local playerClass    = nil
local characterKey   = nil  -- per-character key for HoT frames config (Realm-Character)
local testMode       = false
local testMembers    = nil  -- fake member list when test mode is active

-- ─────────────────────────────────────────────────────────────────────────────
-- DB helpers
-- ─────────────────────────────────────────────────────────────────────────────
local function D(key)
    if JarsRaidDB[key] ~= nil then return JarsRaidDB[key] end
    return DEFAULTS[key]
end

local function DS(slotIdx, key)
    local s = JarsRaidDB.slots and JarsRaidDB.slots[slotIdx]
    if s and s[key] ~= nil then return s[key] end
    local ds = DEFAULTS.slots[slotIdx]
    return ds and ds[key]
end

local function SetDS(slotIdx, key, val)
    if not JarsRaidDB.slots then JarsRaidDB.slots = {} end
    if not JarsRaidDB.slots[slotIdx] then JarsRaidDB.slots[slotIdx] = {} end
    JarsRaidDB.slots[slotIdx][key] = val
end

-- My-frame slot helpers (reads from JarsRaidDB.mySlots / DEFAULTS.mySlots)
local function DM(slotIdx, key)
    local s = JarsRaidDB.mySlots and JarsRaidDB.mySlots[slotIdx]
    if s and s[key] ~= nil then return s[key] end
    local ds = DEFAULTS.mySlots[slotIdx]
    return ds and ds[key]
end

local function SetDM(slotIdx, key, val)
    if not JarsRaidDB.mySlots then JarsRaidDB.mySlots = {} end
    if not JarsRaidDB.mySlots[slotIdx] then JarsRaidDB.mySlots[slotIdx] = {} end
    JarsRaidDB.mySlots[slotIdx][key] = val
end

-- Get per-character key for HoT frames storage (Realm-Character format)
local function GetCharacterKey()
    if not characterKey then
        local name = UnitName("player") or "Unknown"
        local realm = GetRealmName() or "Unknown"
        characterKey = realm .. "-" .. name
    end
    return characterKey
end

-- HoT Frames slot helpers (DH = read hotFrames config - per-character storage)
local function DH(slotIdx, key)
    local charKey = GetCharacterKey()
    local charData = JarsRaidDB.characterHotFrames and JarsRaidDB.characterHotFrames[charKey]
    if charData then
        local s = charData[slotIdx]
        if s and s[key] ~= nil then return s[key] end
    end
    -- Fall back to DEFAULTS
    local ds = DEFAULTS.hotFrames[slotIdx]
    return ds and ds[key]
end

local function SetDH(slotIdx, key, val)
    local charKey = GetCharacterKey()
    if not JarsRaidDB.characterHotFrames then JarsRaidDB.characterHotFrames = {} end
    if not JarsRaidDB.characterHotFrames[charKey] then JarsRaidDB.characterHotFrames[charKey] = {} end
    if not JarsRaidDB.characterHotFrames[charKey][slotIdx] then JarsRaidDB.characterHotFrames[charKey][slotIdx] = {} end
    JarsRaidDB.characterHotFrames[charKey][slotIdx][key] = val
end

local function GetHotFramesPadding()
    if JarsRaidDB.hotFramesPadding ~= nil then return JarsRaidDB.hotFramesPadding end
    return DEFAULTS.hotFramesPadding
end

local function SetHotFramesPadding(val)
    JarsRaidDB.hotFramesPadding = val
end

-- Cycle forward through a list (wraps around)
local function CycleNext(list, current)
    local idx = 1
    for i, v in ipairs(list) do if v == current then idx = i; break end end
    return list[(idx % #list) + 1]
end

-- Cycle backward through a list (wraps around)
local function CyclePrev(list, current)
    local idx = 1
    for i, v in ipairs(list) do if v == current then idx = i; break end end
    return list[((idx - 2) % #list) + 1]
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Dispel / debuff-type helpers
-- ─────────────────────────────────────────────────────────────────────────────
local function GetPlayerDispelTypes()
    if not playerClass then
        playerClass = select(2, UnitClass("player"))
    end
    local t = {
        PRIEST  = { Magic = true, Disease = true },
        PALADIN = { Magic = true, Poison = true, Disease = true },
        SHAMAN  = { Magic = true, Curse = true,  Poison = true },
        DRUID   = { Magic = true, Curse = true,  Poison = true },
        MAGE    = { Curse = true },
        MONK    = { Magic = true, Poison = true, Disease = true },
        EVOKER  = { Magic = true, Poison = true },
        WARLOCK = { Magic = true },
    }
    return t[playerClass] or {}
end

-- Returns r, g, b for a debuff type, or nil for unknown/none
local function GetDebuffTypeColor(dispelName)
    if dispelName == "Magic"   then return 0.4, 0.7, 1.0 end
    if dispelName == "Curse"   then return 0.8, 0.2, 1.0 end
    if dispelName == "Poison"  then return 0.2, 1.0, 0.2 end
    if dispelName == "Disease" then return 0.8, 0.6, 0.0 end
    return nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Whitelisted HoT spells for HoT Frames feature
-- ─────────────────────────────────────────────────────────────────────────────
local WHITELISTED_HOTS = {
    -- Preservation Evoker
    355941, 363502, 364343, 366155, 367364, 373267, 376788,
    -- Augmentation Evoker
    360827, 395152, 410089, 410263, 410686, 413984,
    -- Resto Druid
    774, 8936, 33763, 48438, 155777,
    -- Disc Priest
    17, 194384, 1253593,
    -- Holy Priest
    139, 41635, 77489,
    -- Mistweaver Monk
    115175, 119611, 124682, 450769,
    -- Restoration Shaman
    974, 383648, 61295, 207400, 382024, 444490,
    -- Holy Paladin
    53563, 156322, 156910, 1244893,
    -- Long-term Raid Buffs
    1459, 6673, 21562, 369459, 462854, 474754,
    -- Blessing of the Bronze Auras
    381732, 381741, 381746, 381748, 381749, 381750, 381751, 381752, 381753, 381754, 381756, 381757, 381758,
    -- Long-term Self Buffs
    433568, 433583,
    -- Rogue Poisons
    2823, 8679, 3408, 5761, 315584, 381637, 381664,
    -- Shaman Imbuements
    319773, 319778, 382021, 382022, 457496, 457481, 462757, 462742,
    -- Resource-like Auras
    205473, 260286,
    -- Sated/Exhaustion Debuffs
    57723, 57724, 80354, 95809, 160455, 264689, 390435,
    -- Deserter Debuffs
    26013, 71041,
    -- Skyriding
    427490, 447959, 447960,
}

local function IsSpellWhitelisted(spellID)
    if not spellID or spellID == 0 then return true end  -- Empty slot always valid
    for _, id in ipairs(WHITELISTED_HOTS) do
        if id == spellID then return true end
    end
    return false
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Raid-member sorting
-- ─────────────────────────────────────────────────────────────────────────────
local rolePriority = { TANK = 1, HEALER = 2, DAMAGER = 3, NONE = 4 }

local function GetUnitRole(unit)
    if UnitGroupRolesAssigned then
        return UnitGroupRolesAssigned(unit) or "NONE"
    end
    return "NONE"
end

local function SortRaidMembers()
    local members = {}
    if IsInRaid() then
        for i = 1, 40 do
            if UnitExists("raid" .. i) then
                local u = "raid" .. i
                table.insert(members, {
                    unit  = u,
                    name  = UnitName(u) or "",
                    class = select(2, UnitClass(u)) or "",
                    role  = GetUnitRole(u),
                    group = select(3, GetRaidRosterInfo(i)) or 0,
                })
            end
        end
    elseif D("useInParty") and IsInGroup() and not IsInRaid() then
        table.insert(members, {
            unit  = "player",
            name  = UnitName("player") or "",
            class = select(2, UnitClass("player")) or "",
            role  = GetUnitRole("player"),
            group = 1,
        })
        for i = 1, 4 do
            if UnitExists("party" .. i) then
                local u = "party" .. i
                table.insert(members, {
                    unit  = u,
                    name  = UnitName(u) or "",
                    class = select(2, UnitClass(u)) or "",
                    role  = GetUnitRole(u),
                    group = 1,
                })
            end
        end
    end

    local sortBy   = D("sortBy")
    local byName   = D("sortByName")
    table.sort(members, function(a, b)
        if sortBy == "ROLE" and a.role ~= b.role then
            return (rolePriority[a.role] or 99) < (rolePriority[b.role] or 99)
        elseif sortBy == "CLASS" and a.class ~= b.class then
            return a.class < b.class
        elseif sortBy == "GROUP" and a.group ~= b.group then
            return a.group < b.group
        end
        if byName then return a.name < b.name end
        return false
    end)
    return members
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Name-text anchor helper
-- ─────────────────────────────────────────────────────────────────────────────
local function ApplyNameAnchor(fstr, anchor)
    fstr:ClearAllPoints()
    if anchor == "TOP_LEFT" then
        fstr:SetPoint("TOPLEFT",  16, -2)
        fstr:SetPoint("TOPRIGHT", -2, -2)
        fstr:SetJustifyH("LEFT")
        fstr:SetJustifyV("TOP")
    elseif anchor == "TOP_RIGHT" then
        fstr:SetPoint("TOPLEFT",  16, -2)
        fstr:SetPoint("TOPRIGHT", -2, -2)
        fstr:SetJustifyH("RIGHT")
        fstr:SetJustifyV("TOP")
    elseif anchor == "BOTTOM_LEFT" then
        fstr:SetPoint("BOTTOMLEFT",  16, 2)
        fstr:SetPoint("BOTTOMRIGHT", -2, 2)
        fstr:SetJustifyH("LEFT")
        fstr:SetJustifyV("BOTTOM")
    elseif anchor == "BOTTOM_RIGHT" then
        fstr:SetPoint("BOTTOMLEFT",  16, 2)
        fstr:SetPoint("BOTTOMRIGHT", -2, 2)
        fstr:SetJustifyH("RIGHT")
        fstr:SetJustifyV("BOTTOM")
    else -- CENTER
        fstr:SetPoint("LEFT",  16, 0)
        fstr:SetPoint("RIGHT", -2, 0)
        fstr:SetJustifyH("CENTER")
        fstr:SetJustifyV("MIDDLE")
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Icon-frame factory (used by all 5 aura slots)
-- ─────────────────────────────────────────────────────────────────────────────
local function MakeIconRow(parent, n)
    local icons = {}
    for i = 1, n do
        local f = CreateFrame("Frame", nil, parent)
        f:SetSize(14, 14)
        f:SetFrameStrata("HIGH")
        f:EnableMouse(false)

        f.bg = f:CreateTexture(nil, "BACKGROUND")
        f.bg:SetAllPoints()
        f.bg:SetColorTexture(0, 0, 0, 0.8)

        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetAllPoints()
        f.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

        f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        f.cooldown:SetAllPoints()
        f.cooldown:SetDrawEdge(false)
        f.cooldown:SetDrawSwipe(true)
        f.cooldown:SetHideCountdownNumbers(true)

        f.count = f:CreateFontString(nil, "OVERLAY")
        f.count:SetPoint("BOTTOMRIGHT", 1, 0)
        f.count:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")

        f:Hide()
        icons[i] = f
    end
    return icons
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Frame creation
-- ─────────────────────────────────────────────────────────────────────────────
local function CreateRaidFrame(parent)
    local fw = D("frameWidth")
    local fh = D("frameHeight")
    local bs = D("borderSize")
    local bc = D("borderColor")

    local frame = CreateFrame("Button", nil, parent, "SecureUnitButtonTemplate")
    frame:SetSize(fw, fh)
    frame:RegisterForClicks("AnyUp")
    frame:SetAttribute("*type1", "target")
    frame:SetAttribute("*type2", "togglemenu")
    frame.unit = nil

    -- Dark background
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0.1, 0.1, 0.1, 0.9)

    -- 4-texture border
    frame.border = {}
    frame.border.top = frame:CreateTexture(nil, "BORDER")
    frame.border.top:SetPoint("TOPLEFT"); frame.border.top:SetPoint("TOPRIGHT")
    frame.border.top:SetHeight(bs)
    frame.border.top:SetColorTexture(bc.r, bc.g, bc.b, bc.a)

    frame.border.bottom = frame:CreateTexture(nil, "BORDER")
    frame.border.bottom:SetPoint("BOTTOMLEFT"); frame.border.bottom:SetPoint("BOTTOMRIGHT")
    frame.border.bottom:SetHeight(bs)
    frame.border.bottom:SetColorTexture(bc.r, bc.g, bc.b, bc.a)

    frame.border.left = frame:CreateTexture(nil, "BORDER")
    frame.border.left:SetPoint("TOPLEFT"); frame.border.left:SetPoint("BOTTOMLEFT")
    frame.border.left:SetWidth(bs)
    frame.border.left:SetColorTexture(bc.r, bc.g, bc.b, bc.a)

    frame.border.right = frame:CreateTexture(nil, "BORDER")
    frame.border.right:SetPoint("TOPRIGHT"); frame.border.right:SetPoint("BOTTOMRIGHT")
    frame.border.right:SetWidth(bs)
    frame.border.right:SetColorTexture(bc.r, bc.g, bc.b, bc.a)

    -- Health bar
    frame.healthBar = CreateFrame("StatusBar", nil, frame)
    frame.healthBar:SetPoint("TOPLEFT",     bs,  -bs)
    frame.healthBar:SetPoint("BOTTOMRIGHT", -bs,  bs)
    frame.healthBar:SetFrameLevel(frame:GetFrameLevel() + 1)

    frame.healthBar.bg = frame.healthBar:CreateTexture(nil, "BACKGROUND")
    frame.healthBar.bg:SetAllPoints()
    frame.healthBar.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)

    frame.healthBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    frame.healthBar:SetOrientation("HORIZONTAL")
    frame.healthBar:SetMinMaxValues(0, 100)
    frame.healthBar:SetValue(100)
    frame.healthBar:SetStatusBarColor(0, 1, 0)

    -- Name text
    local fp   = D("font")
    local fz   = D("fontSize")
    local ff   = D("fontShadow") and "OUTLINE" or ""
    local nfz  = D("nameFontSize")
    local nff  = D("nameOutline") ~= "NONE" and D("nameOutline") or ""

    frame.nameText = frame.healthBar:CreateFontString(nil, "OVERLAY")
    frame.nameText:SetFont(fp, nfz, nff)
    frame.nameText:SetTextColor(1, 1, 1, 1)
    ApplyNameAnchor(frame.nameText, D("nameAnchor"))
    frame.nameText:SetWordWrap(false)

    -- Health-percent text
    frame.healthText = frame.healthBar:CreateFontString(nil, "OVERLAY")
    frame.healthText:SetFont(fp, fz, ff)
    frame.healthText:SetTextColor(1, 1, 1, 1)
    frame.healthText:SetPoint("RIGHT", -2, 0)
    frame.healthText:SetJustifyH("RIGHT")

    -- Role icon (left edge of health bar)
    frame.roleIcon = frame:CreateTexture(nil, "ARTWORK")
    frame.roleIcon:SetSize(14, 14)
    frame.roleIcon:SetPoint("LEFT", frame.healthBar, "LEFT", 2, 0)

    -- Dispel-highlight overlay (shown + tinted when a player-dispellable debuff is present)
    -- Must be a child frame above healthBar so it renders on top of the health fill
    frame.highlightFrame = CreateFrame("Frame", nil, frame)
    frame.highlightFrame:SetAllPoints()
    frame.highlightFrame:SetFrameLevel(frame:GetFrameLevel() + 10)

    frame.dispelHighlight = frame.highlightFrame:CreateTexture(nil, "OVERLAY")
    frame.dispelHighlight:SetAllPoints()
    frame.dispelHighlight:SetColorTexture(1, 0, 0, 0.15)
    frame.dispelHighlight:Hide()

    -- Threat-border overlay (orange/red when unit has significant threat)
    frame.threatHighlight = frame.highlightFrame:CreateTexture(nil, "OVERLAY")
    frame.threatHighlight:SetAllPoints()
    frame.threatHighlight:SetColorTexture(1, 0, 0, 0)
    frame.threatHighlight:Hide()

    -- 5 aura slots — each gets MAX_SLOT_ICONS pre-allocated icon frames
    frame.slotIcons = {}
    for s = 1, 5 do
        frame.slotIcons[s] = MakeIconRow(frame, MAX_SLOT_ICONS)
    end

    -- 5 "My Frame" override slots — same pre-allocation, different config source
    frame.mySlotIcons = {}
    for s = 1, 5 do
        frame.mySlotIcons[s] = MakeIconRow(frame, MAX_SLOT_ICONS)
    end

    -- 4 HoT frame slots (up to 3 icons each, independently configurable)
    frame.hotSlotIcons = {}
    for s = 1, 4 do
        frame.hotSlotIcons[s] = MakeIconRow(frame, 1)  -- Single icon per slot
    end

    frame._healthInit = false
    frame:Hide()
    return frame
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Aura-slot icon positioning  (always horizontal within a slot)
-- CENTER:       icons centred horizontally, grow to the right
-- TOP_LEFT:     anchored top-left,    grow right
-- TOP_RIGHT:    anchored top-right,   grow left
-- BOTTOM_LEFT:  anchored bottom-left, grow right
-- BOTTOM_RIGHT: anchored bottom-right,grow left
-- ─────────────────────────────────────────────────────────────────────────────
local function PositionSlot(frame, slotIdx)
    local icons = frame.slotIcons and frame.slotIcons[slotIdx]
    if not icons then return end

    local count   = math.min(DS(slotIdx, "count") or 4, MAX_SLOT_ICONS)
    local size    = DS(slotIdx, "iconSize") or 14
    local pos     = DS(slotIdx, "position") or "BOTTOM_RIGHT"
    local spacing = size + 2

    for i = 1, MAX_SLOT_ICONS do
        local ic = icons[i]
        if not ic then break end
        ic:SetSize(size, size)
        ic:ClearAllPoints()

        if i <= count then
            local offset = (i - 1) * spacing
            if pos == "CENTER" then
                local totalW = (count - 1) * spacing
                ic:SetPoint("LEFT", frame, "CENTER", offset - totalW / 2, 0)
            elseif pos == "TOP_LEFT" then
                ic:SetPoint("TOPLEFT",    frame, "TOPLEFT",    offset + 2,  -2)
            elseif pos == "TOP_RIGHT" then
                ic:SetPoint("TOPRIGHT",   frame, "TOPRIGHT",  -offset - 2,  -2)
            elseif pos == "BOTTOM_LEFT" then
                ic:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", offset + 2,   2)
            else -- BOTTOM_RIGHT
                ic:SetPoint("BOTTOMRIGHT",frame, "BOTTOMRIGHT",-offset - 2,  2)
            end
        end
    end
end

local function PositionAllSlots(frame)
    for s = 1, 5 do PositionSlot(frame, s) end
end

-- My-frame slot positioning (mirrors PositionSlot but uses DM() for settings)
local function PositionMySlot(frame, slotIdx)
    local icons = frame.mySlotIcons and frame.mySlotIcons[slotIdx]
    if not icons then return end
    local count   = math.min(DM(slotIdx, "count") or 4, MAX_SLOT_ICONS)
    local size    = DM(slotIdx, "iconSize") or 14
    local pos     = DM(slotIdx, "position") or "BOTTOM_RIGHT"
    local spacing = size + 2
    for i = 1, MAX_SLOT_ICONS do
        local ic = icons[i]
        if not ic then break end
        ic:SetSize(size, size)
        ic:ClearAllPoints()
        if i <= count then
            local offset = (i - 1) * spacing
            if pos == "CENTER" then
                local totalW = (count - 1) * spacing
                ic:SetPoint("LEFT", frame, "CENTER", offset - totalW / 2, 0)
            elseif pos == "TOP_LEFT" then
                ic:SetPoint("TOPLEFT",     frame, "TOPLEFT",    offset + 2,  -2)
            elseif pos == "TOP_RIGHT" then
                ic:SetPoint("TOPRIGHT",    frame, "TOPRIGHT",  -offset - 2,  -2)
            elseif pos == "BOTTOM_LEFT" then
                ic:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT", offset + 2,   2)
            else
                ic:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",-offset - 2,  2)
            end
        end
    end
end

local function PositionAllMySlots(frame)
    for s = 1, 5 do PositionMySlot(frame, s) end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- HoT Frames positioning: 4 icons distributed across frame (far-left, left-center, right-center, far-right)
-- ─────────────────────────────────────────────────────────────────────────────
local function PositionHotSlots(frame)
    local fw = D("frameWidth")
    local padding = GetHotFramesPadding()

    for slotIdx = 1, 4 do
        local icons = frame.hotSlotIcons and frame.hotSlotIcons[slotIdx]
        if icons and icons[1] then
            local size = DH(slotIdx, "iconSize") or 14
            icons[1]:SetSize(size, size)
            icons[1]:ClearAllPoints()

            -- Calculate total width: 4 slots × 1 icon + 3 gaps (padding between them)
            local totalWidth = 4 * size + 3 * padding

            -- If total width exceeds frame width, scale down spacing
            local spacing = padding
            if totalWidth > fw then
                spacing = (fw - 4 * size) / 3
            end

            -- Calculate position for this slot's icon
            local leftMargin = (fw - totalWidth) / 2
            local xOffset = leftMargin + size / 2 + (slotIdx - 1) * (size + spacing) - fw / 2

            icons[1]:SetPoint("CENTER", frame, "CENTER", xOffset, 0)
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Update a single aura slot on a frame
-- ─────────────────────────────────────────────────────────────────────────────
local function UpdateAuraSlot(frame, unit, slotIdx)
    local icons = frame.slotIcons and frame.slotIcons[slotIdx]
    if not icons then return end

    local enabled = DS(slotIdx, "enabled")
    local count   = math.min(DS(slotIdx, "count") or 4, MAX_SLOT_ICONS)
    local filter  = DS(slotIdx, "filter") or "HELPFUL"

    if not enabled then
        for i = 1, MAX_SLOT_ICONS do if icons[i] then icons[i]:Hide() end end
        return
    end

    local shown    = 0
    local auraSlot = 1

    while shown < count and auraSlot <= 40 do
        local ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, unit, auraSlot, filter)
        if not ok or not auraData then break end

        local ic = icons[shown + 1]
        if ic then
            local texOk = pcall(function() ic.icon:SetTexture(auraData.icon) end)
            if texOk then
                -- Stack count
                pcall(function()
                    if auraData.applications and auraData.applications > 1 then
                        ic.count:SetText(auraData.applications)
                    else
                        ic.count:SetText("")
                    end
                end)
                -- Cooldown spiral
                pcall(function()
                    if ic.cooldown and auraData.expirationTime and auraData.duration then
                        if C_StringUtil and C_StringUtil.TruncateWhenZero
                           and C_StringUtil.TruncateWhenZero(auraData.duration) then
                            ic.cooldown:SetCooldownFromExpirationTime(
                                auraData.expirationTime, auraData.duration)
                            ic.cooldown:SetReverse(true)
                            ic.cooldown:Show()
                        else
                            ic.cooldown:Hide()
                        end
                    end
                end)
                ic:Show()
                shown = shown + 1
            end
        end
        auraSlot = auraSlot + 1
    end

    -- Hide unused
    for i = shown + 1, MAX_SLOT_ICONS do
        if icons[i] then icons[i]:Hide() end
    end
end

-- My-frame variant: same logic but reads from mySlotIcons + DM() config
local function UpdateMyAuraSlot(frame, unit, slotIdx)
    local icons = frame.mySlotIcons and frame.mySlotIcons[slotIdx]
    if not icons then return end

    local enabled = DM(slotIdx, "enabled")
    local count   = math.min(DM(slotIdx, "count") or 4, MAX_SLOT_ICONS)
    local filter  = DM(slotIdx, "filter") or "HELPFUL"

    if not enabled then
        for i = 1, MAX_SLOT_ICONS do if icons[i] then icons[i]:Hide() end end
        return
    end

    local shown    = 0
    local auraSlot = 1

    while shown < count and auraSlot <= 40 do
        local ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, unit, auraSlot, filter)
        if not ok or not auraData then break end

        local ic = icons[shown + 1]
        if ic then
            local texOk = pcall(function() ic.icon:SetTexture(auraData.icon) end)
            if texOk then
                pcall(function()
                    ic.count:SetText(auraData.applications and auraData.applications > 1
                        and auraData.applications or "")
                end)
                pcall(function()
                    if ic.cooldown and auraData.expirationTime and auraData.duration then
                        if C_StringUtil and C_StringUtil.TruncateWhenZero
                           and C_StringUtil.TruncateWhenZero(auraData.duration) then
                            ic.cooldown:SetCooldownFromExpirationTime(
                                auraData.expirationTime, auraData.duration)
                            ic.cooldown:SetReverse(true)
                            ic.cooldown:Show()
                        else
                            ic.cooldown:Hide()
                        end
                    end
                end)
                ic:Show()
                shown = shown + 1
            end
        end
        auraSlot = auraSlot + 1
    end

    for i = shown + 1, MAX_SLOT_ICONS do
        if icons[i] then icons[i]:Hide() end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- HoT Frames: Track specific healer HoTs/buffs cast by player (HELPFUL|PLAYER filter)
-- ─────────────────────────────────────────────────────────────────────────────
local function UpdateHotSlot(frame, unit, slotIdx)
    local icons = frame.hotSlotIcons and frame.hotSlotIcons[slotIdx]
    if not icons or not icons[1] then return end

    local enabled = DH(slotIdx, "enabled")

    if not enabled then
        icons[1]:Hide()
        return
    end

    local ic = icons[1]

    -- Check up to 3 spells in priority order (spell1 > spell2 > spell3)
    -- Display the first one found
    for spellSlot = 1, 3 do
        local spellKey = "spell" .. spellSlot
        local spellID = DH(slotIdx, spellKey) or 0

        if spellID ~= 0 then
            -- Scan for this spell cast by player (HELPFUL|PLAYER filter)
            local auraSlot = 1

            while auraSlot <= 40 do
                local ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, unit, auraSlot, "HELPFUL|PLAYER")
                if not ok or not auraData then break end

                local matchOk, isMatch = pcall(function() return auraData.spellId == spellID end)
                if matchOk and isMatch then
                    -- Found it! Display this icon
                    local texOk = pcall(function() ic.icon:SetTexture(auraData.icon) end)
                    if texOk then
                        -- Stack count
                        pcall(function()
                            if auraData.applications and auraData.applications > 1 then
                                ic.count:SetText(auraData.applications)
                            else
                                ic.count:SetText("")
                            end
                        end)

                        -- Cooldown spiral with timer
                        pcall(function()
                            if ic.cooldown and auraData.expirationTime and auraData.duration then
                                if C_StringUtil and C_StringUtil.TruncateWhenZero
                                   and C_StringUtil.TruncateWhenZero(auraData.duration) then
                                    ic.cooldown:SetCooldownFromExpirationTime(
                                        auraData.expirationTime, auraData.duration)
                                    ic.cooldown:SetReverse(true)
                                    ic.cooldown:Show()
                                else
                                    ic.cooldown:Hide()
                                end
                            end
                        end)

                        ic:Show()
                        return  -- Found and displayed, done
                    end
                end

                auraSlot = auraSlot + 1
            end
        end
    end

    -- None of the 3 spells were found on unit, hide icon
    ic:Hide()
end

local function UpdateHotSlots(frame, unit)
    for s = 1, 4 do UpdateHotSlot(frame, unit, s) end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Threat border: paints the 4 border edges + outer overlay based on
-- UnitThreatSituation.  Uses WoW colour convention:
--   level 2 = near-pull  → orange border
--   level 3 = have aggro → red border
--   else                 → reset to configured border colour
-- ─────────────────────────────────────────────────────────────────────────────
local function UpdateThreatBorder(frame)
    if not D("threatBorder") or (frame._threatLvl or 0) < 3 then
        local bc = D("borderColor")
        frame.border.top:SetColorTexture(bc.r, bc.g, bc.b, bc.a)
        frame.border.bottom:SetColorTexture(bc.r, bc.g, bc.b, bc.a)
        frame.border.left:SetColorTexture(bc.r, bc.g, bc.b, bc.a)
        frame.border.right:SetColorTexture(bc.r, bc.g, bc.b, bc.a)
    else
        -- Red — unit has aggro
        frame.border.top:SetColorTexture(1, 0.05, 0.05, 1)
        frame.border.bottom:SetColorTexture(1, 0.05, 0.05, 1)
        frame.border.left:SetColorTexture(1, 0.05, 0.05, 1)
        frame.border.right:SetColorTexture(1, 0.05, 0.05, 1)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Debuff-type border colouring
-- Scans HARMFUL auras independently of the configured slots.
-- Priority: debuff type the player CAN dispel > any typed debuff > reset to default
-- ─────────────────────────────────────────────────────────────────────────────
local function UpdateDebuffBorder(frame, unit)
    local canDispel       = GetPlayerDispelTypes()
    local dispellableType = nil   -- type the player can remove
    local anyType         = nil   -- any typed debuff, fallback

    for auraSlot = 1, 40 do
        local ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, unit, auraSlot, "HARMFUL")
        if not ok or not auraData then break end

        pcall(function()
            local dtype = auraData.dispelName
            if dtype then
                if canDispel[dtype] and not dispellableType then
                    dispellableType = dtype
                end
                if not anyType then
                    anyType = dtype
                end
            end
        end)

        if dispellableType and anyType then break end
    end

    local debuffType = dispellableType or anyType

    -- Only paint the border if threat is not active (threat takes priority and owns the border)
    if not (D("threatBorder") and (frame._threatLvl or 0) >= 3) then
        if debuffType then
            local r, g, b = GetDebuffTypeColor(debuffType)
            if r then
                frame.border.top:SetColorTexture(r, g, b, 1)
                frame.border.bottom:SetColorTexture(r, g, b, 1)
                frame.border.left:SetColorTexture(r, g, b, 1)
                frame.border.right:SetColorTexture(r, g, b, 1)
            end
        else
            local bc = D("borderColor")
            frame.border.top:SetColorTexture(bc.r, bc.g, bc.b, bc.a)
            frame.border.bottom:SetColorTexture(bc.r, bc.g, bc.b, bc.a)
            frame.border.left:SetColorTexture(bc.r, bc.g, bc.b, bc.a)
            frame.border.right:SetColorTexture(bc.r, bc.g, bc.b, bc.a)
        end
    end

    -- Show the dispel-highlight overlay only for types the player can actually remove
    if dispellableType then
        local r, g, b = GetDebuffTypeColor(dispellableType)
        if r then
            frame.dispelHighlight:SetColorTexture(r, g, b, 0.15)
            frame.dispelHighlight:Show()
        end
    else
        frame.dispelHighlight:Hide()
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Full frame update
-- ─────────────────────────────────────────────────────────────────────────────
local function UpdateRaidFrame(frame, unit)
    if not unit or not UnitExists(unit) then
        if frame.unit then
            UnregisterUnitWatch(frame)
            frame:SetAttribute("unit", nil)
            frame.unit = nil
        end
        frame:Hide()
        return
    end

    if frame.unit ~= unit then
        frame.unit = unit
        frame:SetAttribute("unit", unit)
        RegisterUnitWatch(frame)
    end

    frame:Show()

    -- Name
    if D("showNames") then
        frame.nameText:SetText(UnitName(unit) or "")
        frame.nameText:Show()
    else
        frame.nameText:Hide()
    end

    -- Health bar
    local hOk, h, m
    hOk = pcall(function()
        h = UnitHealth(unit)
        m = UnitHealthMax(unit)
    end)
    if hOk and h and m then
        frame.healthBar:SetMinMaxValues(0, m)
        frame.healthBar:SetValue(h)
        local pOk, pct = pcall(function() return (h / m) * 100 end)
        frame.healthText:SetText(pOk and string.format("%.0f%%", pct) or "")
        frame._healthInit = true
    elseif not frame._healthInit then
        frame.healthBar:SetMinMaxValues(0, 100)
        frame.healthBar:SetValue(100)
        frame.healthText:SetText("")
        frame._healthInit = true
    end

    -- Health bar colour
    if D("showClassColors") then
        local cOk, cls = pcall(function() return select(2, UnitClass(unit)) end)
        if cOk and cls and RAID_CLASS_COLORS then
            local c = RAID_CLASS_COLORS[cls]
            if c then frame.healthBar:SetStatusBarColor(c.r, c.g, c.b) end
        end
    else
        frame.healthBar:SetStatusBarColor(0, 1, 0)
    end

    -- Role icon
    if D("showRoleIcon") then
        local rOk, role = pcall(GetUnitRole, unit)
        if rOk then
            if role == "TANK" then
                frame.roleIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
                frame.roleIcon:SetTexCoord(0, 19/64, 22/64, 41/64)
                frame.roleIcon:Show()
            elseif role == "HEALER" then
                frame.roleIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
                frame.roleIcon:SetTexCoord(20/64, 39/64, 1/64, 20/64)
                frame.roleIcon:Show()
            elseif role == "DAMAGER" then
                frame.roleIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
                frame.roleIcon:SetTexCoord(20/64, 39/64, 22/64, 41/64)
                frame.roleIcon:Show()
            else
                frame.roleIcon:Hide()
            end
        else
            frame.roleIcon:Hide()
        end
    else
        frame.roleIcon:Hide()
    end

    -- All 5 aura slots (standard config)
    -- If "My Frame" is enabled and this is the player's own unit, use mySlots instead
    local isPlayerFrame = pcall(function()
        return UnitIsUnit(unit, "player")
    end) and UnitIsUnit(unit, "player")

    if D("myFrameEnabled") and isPlayerFrame then
        -- Hide standard slot icons
        for s = 1, 5 do
            local icons = frame.slotIcons and frame.slotIcons[s]
            if icons then
                for i = 1, MAX_SLOT_ICONS do if icons[i] then icons[i]:Hide() end end
            end
        end
        -- Apply my-frame slots
        for s = 1, 5 do UpdateMyAuraSlot(frame, unit, s) end
    else
        -- Standard slots
        for s = 1, 5 do UpdateAuraSlot(frame, unit, s) end
        -- Hide my-frame slot icons
        for s = 1, 5 do
            local icons = frame.mySlotIcons and frame.mySlotIcons[s]
            if icons then
                for i = 1, MAX_SLOT_ICONS do if icons[i] then icons[i]:Hide() end end
            end
        end
    end

    -- Debuff border colouring
    UpdateDebuffBorder(frame, unit)

    -- Threat border (applied after debuff so threat takes visual priority)
    UpdateThreatBorder(frame)

    -- HoT Frames (independent of my-frame setting)
    UpdateHotSlots(frame, unit)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Container & layout
-- ─────────────────────────────────────────────────────────────────────────────
local function EnsureContainer()
    if containerFrame then return end
    containerFrame = CreateFrame("Frame", "JarsRaidContainer", UIParent)
    containerFrame:SetSize(400, 300)

    -- Restore saved position or use default (anchored TOPLEFT so growth goes right/down only)
    local px = JarsRaidDB.posX ~= nil and JarsRaidDB.posX or D("posX")
    local py = JarsRaidDB.posY ~= nil and JarsRaidDB.posY or D("posY")
    local anchor = JarsRaidDB.posAnchor or "CENTER"
    containerFrame:SetPoint(anchor, UIParent, anchor, px, py)

    containerFrame:SetMovable(true)
    containerFrame:SetClampedToScreen(true)
    containerFrame:EnableMouse(true)
    containerFrame:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" and not D("locked") then self:StartMoving() end
    end)
    containerFrame:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        -- Re-anchor to TOPLEFT so resizing grows right/down only
        local left   = self:GetLeft()
        local top    = self:GetTop()
        local parent = UIParent
        local scale  = self:GetEffectiveScale() / parent:GetEffectiveScale()
        local x = left * scale
        local y = (top - parent:GetHeight()) * scale
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        JarsRaidDB.posX = x
        JarsRaidDB.posY = y
        JarsRaidDB.posAnchor = "TOPLEFT"
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Boss frames
-- ─────────────────────────────────────────────────────────────────────────────
local function EnsureBossContainer()
    if bossContainer then return end
    bossContainer = CreateFrame("Frame", "JarsRaidBossContainer", UIParent)
    bossContainer:SetSize(90, 32)
    bossContainer:SetPoint("CENTER", UIParent, "CENTER", -200, 100)
end

-- Positions bossContainer relative to containerFrame based on bossAttach setting.
-- Called after containerFrame has been sized.
local function RepositionBossContainer()
    if not bossContainer or not containerFrame then return end
    local attach  = D("bossAttach") or "LEFT"
    local bfw     = D("bossFrameWidth")  or D("frameWidth")
    local bfh     = D("bossFrameHeight") or D("frameHeight")
    local pad     = D("padding")
    local count   = math.min(D("bossCount") or 5, 5)
    local bossH   = count * (bfh + pad) - pad

    bossContainer:ClearAllPoints()
    if attach == "LEFT" then
        -- Boss frames to the left, top-aligned with containerFrame
        bossContainer:SetSize(bfw, bossH)
        bossContainer:SetPoint("TOPRIGHT", containerFrame, "TOPLEFT", -pad, 0)
    else  -- "TOP"
        -- Boss frames stacked vertically above containerFrame
        bossContainer:SetSize(bfw, bossH)
        bossContainer:SetPoint("BOTTOMLEFT", containerFrame, "TOPLEFT", 0, pad)
    end
end

local function LayoutBossFrames()
    if not D("bossEnabled") then
        -- Hide all boss frames
        if bossContainer then bossContainer:Hide() end
        for i = 1, 5 do
            if bossFrames[i] then UpdateRaidFrame(bossFrames[i], nil) end
        end
        return
    end

    EnsureContainer()
    EnsureBossContainer()
    bossContainer:Show()

    local bfw  = D("bossFrameWidth")  or D("frameWidth")
    local bfh  = D("bossFrameHeight") or D("frameHeight")
    local pad  = D("padding")
    local max  = math.min(D("bossCount") or 5, 5)

    RepositionBossContainer()

    for i = 1, 5 do
        local unit = "boss" .. i
        if not bossFrames[i] then
            bossFrames[i] = CreateRaidFrame(bossContainer)
            PositionAllSlots(bossFrames[i])
            PositionAllMySlots(bossFrames[i])
        end
        bossFrames[i]:ClearAllPoints()
        bossFrames[i]:SetSize(bfw, bfh)
        bossFrames[i]:SetPoint("TOPLEFT", bossContainer, "TOPLEFT",
            0, -(i - 1) * (bfh + pad))

        if i <= max and UnitExists(unit) then
            UpdateRaidFrame(bossFrames[i], unit)
        else
            UpdateRaidFrame(bossFrames[i], nil)
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Test mode: generate fake raid members for layout preview
-- ─────────────────────────────────────────────────────────────────────────────
local TEST_CLASSES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK",
    "DRUID", "DEMONHUNTER", "EVOKER",
}
local TEST_NAMES = {
    "Arthas", "Jaina", "Thrall", "Sylvanas", "Velen",
    "Tyrande", "Malfurion", "Anduin", "Garrosh", "Saurfang",
    "Khadgar", "Illidan", "Gul'dan", "Yrel", "Alleria",
    "Turalyon", "Lor'themar", "Thalyssra", "Baine", "Calia",
    "Magni", "Moira", "Falstad", "Muradin", "Gelbin",
    "Mekkatorque", "Voss", "Gazlowe", "Ji", "Aysa",
    "Wrathion", "Ebyssian", "Nozdormu", "Alexstrasza", "Kalecgos",
    "Chromie", "Brann", "Rokhan", "Taelia", "Darion",
}
local TEST_ROLES = { "TANK", "HEALER", "DAMAGER", "DAMAGER", "DAMAGER" }

local function GenerateTestMembers(count)
    local members = {}
    local shuffledNames = {}
    for i, n in ipairs(TEST_NAMES) do shuffledNames[i] = n end
    -- Simple shuffle
    for i = #shuffledNames, 2, -1 do
        local j = math.random(1, i)
        shuffledNames[i], shuffledNames[j] = shuffledNames[j], shuffledNames[i]
    end

    for i = 1, count do
        local cls  = TEST_CLASSES[math.random(1, #TEST_CLASSES)]
        local role = TEST_ROLES[math.random(1, #TEST_ROLES)]
        -- Force first 2 to be tanks, next 2-4 to be healers for realism
        if i <= 2 then role = "TANK"
        elseif i <= 4 or (count >= 20 and i <= 6) then role = "HEALER"
        end
        table.insert(members, {
            unit   = nil,  -- no real unit
            name   = shuffledNames[((i - 1) % #shuffledNames) + 1],
            class  = cls,
            role   = role,
            group  = math.ceil(i / 5),
            health = math.random(20, 100),  -- random HP %
        })
    end

    -- Apply the same sorting as real raid
    local sortBy = D("sortBy")
    local byName = D("sortByName")
    table.sort(members, function(a, b)
        if sortBy == "ROLE" and a.role ~= b.role then
            return (rolePriority[a.role] or 99) < (rolePriority[b.role] or 99)
        elseif sortBy == "CLASS" and a.class ~= b.class then
            return a.class < b.class
        elseif sortBy == "GROUP" and a.group ~= b.group then
            return a.group < b.group
        end
        if byName then return a.name < b.name end
        return false
    end)
    return members
end

local function UpdateTestFrame(frame, member)
    if not member then
        frame:Hide()
        return
    end

    -- Detach from any real unit
    if frame.unit then
        pcall(UnregisterUnitWatch, frame)
        frame:SetAttribute("unit", nil)
        frame.unit = nil
    end

    frame:Show()
    frame:SetAlpha(1)

    -- Name
    if D("showNames") then
        frame.nameText:SetText(member.name)
        frame.nameText:Show()
    else
        frame.nameText:Hide()
    end

    -- Health bar
    frame.healthBar:SetMinMaxValues(0, 100)
    frame.healthBar:SetValue(member.health)
    frame.healthText:SetText(member.health .. "%")

    -- Class colour
    if D("showClassColors") and RAID_CLASS_COLORS then
        local c = RAID_CLASS_COLORS[member.class]
        if c then frame.healthBar:SetStatusBarColor(c.r, c.g, c.b) end
    else
        frame.healthBar:SetStatusBarColor(0, 1, 0)
    end

    -- Role icon
    if D("showRoleIcon") then
        if member.role == "TANK" then
            frame.roleIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
            frame.roleIcon:SetTexCoord(0, 19/64, 22/64, 41/64)
            frame.roleIcon:Show()
        elseif member.role == "HEALER" then
            frame.roleIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
            frame.roleIcon:SetTexCoord(20/64, 39/64, 1/64, 20/64)
            frame.roleIcon:Show()
        elseif member.role == "DAMAGER" then
            frame.roleIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
            frame.roleIcon:SetTexCoord(20/64, 39/64, 22/64, 41/64)
            frame.roleIcon:Show()
        else
            frame.roleIcon:Hide()
        end
    else
        frame.roleIcon:Hide()
    end

    -- Reset borders to default
    local bc = D("borderColor")
    frame.border.top:SetColorTexture(bc.r, bc.g, bc.b, bc.a)
    frame.border.bottom:SetColorTexture(bc.r, bc.g, bc.b, bc.a)
    frame.border.left:SetColorTexture(bc.r, bc.g, bc.b, bc.a)
    frame.border.right:SetColorTexture(bc.r, bc.g, bc.b, bc.a)
    frame.dispelHighlight:Hide()

    -- Hide all aura/hot icons
    for s = 1, 5 do
        local icons = frame.slotIcons and frame.slotIcons[s]
        if icons then for ic = 1, MAX_SLOT_ICONS do if icons[ic] then icons[ic]:Hide() end end end
        icons = frame.mySlotIcons and frame.mySlotIcons[s]
        if icons then for ic = 1, MAX_SLOT_ICONS do if icons[ic] then icons[ic]:Hide() end end end
    end
    for s = 1, 4 do
        local icons = frame.hotSlotIcons and frame.hotSlotIcons[s]
        if icons and icons[1] then icons[1]:Hide() end
    end
end

local LayoutRaidFrames  -- forward declaration

local function StartTestMode(count)
    testMode = true
    testMembers = GenerateTestMembers(count)
    LayoutRaidFrames()
end

local function StopTestMode()
    testMode = false
    testMembers = nil
    LayoutRaidFrames()
end

LayoutRaidFrames = function()
    EnsureContainer()

    local members
    if testMode and testMembers then
        members = testMembers
    else
        members = SortRaidMembers()
    end
    local n        = #members
    local cols     = D("columns")         -- per-row (H) or per-column (V)
    local fw       = D("frameWidth")
    local fh       = D("frameHeight")
    local pad      = D("padding")
    local layoutDir = D("layoutDirection") or "HORIZONTAL"

    for i, m in ipairs(members) do
        if not raidFrames[i] then
            raidFrames[i] = CreateRaidFrame(containerFrame)
            PositionAllSlots(raidFrames[i])
            PositionAllMySlots(raidFrames[i])
        end

        -- Always reposition HoT slots (spacing may have changed)
        PositionHotSlots(raidFrames[i])

        local col, row
        if layoutDir == "VERTICAL" then
            col = math.floor((i - 1) / cols)
            row = (i - 1) % cols
        else
            col = (i - 1) % cols
            row = math.floor((i - 1) / cols)
        end

        raidFrames[i]:ClearAllPoints()
        raidFrames[i]:SetPoint("TOPLEFT", containerFrame, "TOPLEFT",
             col * (fw + pad),
            -row * (fh + pad))
        raidFrames[i]:SetSize(fw, fh)

        if testMode then
            UpdateTestFrame(raidFrames[i], m)
        else
            UpdateRaidFrame(raidFrames[i], m.unit)
        end
    end

    -- Hide surplus frames
    for i = n + 1, #raidFrames do
        if raidFrames[i] then
            if testMode then
                raidFrames[i]:Hide()
            else
                UpdateRaidFrame(raidFrames[i], nil)
            end
        end
    end

    -- Resize container to fit exactly
    local usedCols, usedRows
    if layoutDir == "VERTICAL" then
        usedCols = math.max(1, math.ceil(n / math.max(1, cols)))
        usedRows = math.min(cols, math.max(1, n))
    else
        usedCols = math.min(cols, math.max(1, n))
        usedRows = math.max(1, math.ceil(n / math.max(1, cols)))
    end
    containerFrame:SetSize(
        usedCols * (fw + pad) - pad,
        usedRows * (fh + pad) - pad)

    -- Re-anchor boss frames now that container size is known
    LayoutBossFrames()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Blizzard frame visibility
-- ─────────────────────────────────────────────────────────────────────────────
local function UpdateBlizzardFrameVisibility()
    local hide = D("hideBlizzardFrames")
    local alpha = hide and 0 or 1
    local mouse = not hide

    for _, name in ipairs({ "CompactRaidFrameManager", "CompactPartyFrame", "CompactRaidFrameContainer" }) do
        local f = _G[name]
        if f then
            f:SetAlpha(alpha)
            f:EnableMouse(mouse)
        end
    end

    if hide then
        SetCVar("useCompactPartyFrames", "0")
    else
        SetCVar("useCompactPartyFrames", "1")
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Event handling
-- ─────────────────────────────────────────────────────────────────────────────
local function InitDB()
    for k, v in pairs(DEFAULTS) do
        if k == "slots" then
            if not JarsRaidDB.slots then JarsRaidDB.slots = {} end
            for si = 1, 5 do
                if not JarsRaidDB.slots[si] then JarsRaidDB.slots[si] = {} end
                for sk, sv in pairs(DEFAULTS.slots[si]) do
                    if JarsRaidDB.slots[si][sk] == nil then
                        JarsRaidDB.slots[si][sk] = sv
                    end
                end
            end
        elseif k == "mySlots" then
            if not JarsRaidDB.mySlots then JarsRaidDB.mySlots = {} end
            for si = 1, 5 do
                if not JarsRaidDB.mySlots[si] then JarsRaidDB.mySlots[si] = {} end
                for sk, sv in pairs(DEFAULTS.mySlots[si]) do
                    if JarsRaidDB.mySlots[si][sk] == nil then
                        JarsRaidDB.mySlots[si][sk] = sv
                    end
                end
            end
        elseif k == "hotFrames" then
            -- Per-character HoT frames storage
            if not JarsRaidDB.characterHotFrames then JarsRaidDB.characterHotFrames = {} end
            local charKey = GetCharacterKey()
            if not JarsRaidDB.characterHotFrames[charKey] then JarsRaidDB.characterHotFrames[charKey] = {} end
            for si = 1, 4 do
                if not JarsRaidDB.characterHotFrames[charKey][si] then JarsRaidDB.characterHotFrames[charKey][si] = {} end
                for sk, sv in pairs(DEFAULTS.hotFrames[si]) do
                    if JarsRaidDB.characterHotFrames[charKey][si][sk] == nil then
                        JarsRaidDB.characterHotFrames[charKey][si][sk] = sv
                    end
                end
            end
        else
            if JarsRaidDB[k] == nil then JarsRaidDB[k] = v end
        end
    end
    -- Initialize non-table defaults (hotFramesPadding, position)
    if JarsRaidDB.hotFramesPadding == nil then
        JarsRaidDB.hotFramesPadding = DEFAULTS.hotFramesPadding
    end
    if JarsRaidDB.posX == nil then
        JarsRaidDB.posX = DEFAULTS.posX
    end
    if JarsRaidDB.posY == nil then
        JarsRaidDB.posY = DEFAULTS.posY
    end
end

local function OnUnitAura(unit)
    -- Raid frames
    for _, f in ipairs(raidFrames) do
        if f.unit == unit then
            local isPlayer = pcall(function() return UnitIsUnit(unit, "player") end)
                and UnitIsUnit(unit, "player")
            if D("myFrameEnabled") and isPlayer then
                -- Hide standard, update my-frame slots
                for s = 1, 5 do
                    local icons = f.slotIcons and f.slotIcons[s]
                    if icons then for i = 1, MAX_SLOT_ICONS do if icons[i] then icons[i]:Hide() end end end
                end
                for s = 1, 5 do UpdateMyAuraSlot(f, unit, s) end
            else
                for s = 1, 5 do UpdateAuraSlot(f, unit, s) end
            end
            UpdateDebuffBorder(f, unit)
            UpdateHotSlots(f, unit)
            break
        end
    end
    -- Boss frames
    for _, f in ipairs(bossFrames) do
        if f.unit == unit then
            for s = 1, 5 do UpdateAuraSlot(f, unit, s) end
            UpdateDebuffBorder(f, unit)
            UpdateHotSlots(f, unit)
            break
        end
    end
end

local function OnUnitHealth(unit)
    local function UpdateHealth(f)
        local hOk, h, m
        hOk = pcall(function()
            h = UnitHealth(unit)
            m = UnitHealthMax(unit)
        end)
        if hOk and h and m then
            f.healthBar:SetMinMaxValues(0, m)
            f.healthBar:SetValue(h)
            local pOk, pct = pcall(function() return (h / m) * 100 end)
            f.healthText:SetText(pOk and string.format("%.0f%%", pct) or "")
        end
    end
    for _, f in ipairs(raidFrames) do
        if f.unit == unit then UpdateHealth(f); break end
    end
    for _, f in ipairs(bossFrames) do
        if f.unit == unit then UpdateHealth(f); break end
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("UNIT_HEALTH")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("ENCOUNTER_START")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        InitDB()
        playerClass = select(2, UnitClass("player"))
        EnsureContainer()
        UpdateBlizzardFrameVisibility()
        LayoutRaidFrames()

    elseif event == "PLAYER_ENTERING_WORLD" then
        LayoutRaidFrames()

    elseif event == "GROUP_ROSTER_UPDATE" or event == "RAID_ROSTER_UPDATE" then
        if testMode then StopTestMode() end
        LayoutRaidFrames()

    elseif event == "UNIT_HEALTH" then
        if arg1 then OnUnitHealth(arg1) end

    elseif event == "UNIT_AURA" then
        if arg1 then OnUnitAura(arg1) end

    elseif event == "UNIT_THREAT_LIST_UPDATE" then
        -- Read threat level once per event, cache it, then repaint
        for _, f in ipairs(raidFrames) do
            if f.unit and f:IsShown() then
                f._threatLvl = UnitThreatSituation(f.unit) or 0
                UpdateThreatBorder(f)
            end
        end
        for _, f in ipairs(bossFrames) do
            if f.unit and f:IsShown() then
                f._threatLvl = UnitThreatSituation(f.unit) or 0
                UpdateThreatBorder(f)
            end
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended — clear threat cache and reset borders
        for _, f in ipairs(raidFrames) do
            if f:IsShown() then
                f._threatLvl = 0
                UpdateThreatBorder(f)
            end
        end
        for _, f in ipairs(bossFrames) do
            if f:IsShown() then
                f._threatLvl = 0
                UpdateThreatBorder(f)
            end
        end

    elseif event == "ENCOUNTER_START" or event == "ENCOUNTER_END"
        or event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        LayoutBossFrames()
    end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Range detection: periodic alpha fade for out-of-range frames
-- Uses SetAlphaFromBoolean to handle TWW secret boolean values from UnitInRange
-- ─────────────────────────────────────────────────────────────────────────────
local rangeTimer = 0
eventFrame:SetScript("OnUpdate", function(self, elapsed)
    rangeTimer = rangeTimer + elapsed
    if rangeTimer < 0.2 then return end
    rangeTimer = 0

    local enabled = D("showRangeAlpha")
    local outAlpha = D("rangeAlpha") / 100

    for _, f in ipairs(raidFrames) do
        if f.unit and f:IsShown() then
            if not enabled then
                f:SetAlpha(1)
            elseif UnitIsUnit(f.unit, "player") then
                f:SetAlpha(1)
            elseif f.SetAlphaFromBoolean then
                local inRange = UnitInRange(f.unit)
                f:SetAlphaFromBoolean(inRange, 1, outAlpha)
            else
                f:SetAlpha(1)
            end
        end
    end

    for _, f in ipairs(bossFrames) do
        if f.unit and f:IsShown() then
            if not enabled then
                f:SetAlpha(1)
            elseif f.SetAlphaFromBoolean then
                local inRange = UnitInRange(f.unit)
                f:SetAlphaFromBoolean(inRange, 1, outAlpha)
            else
                f:SetAlpha(1)
            end
        end
    end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Config UI helpers
-- ─────────────────────────────────────────────────────────────────────────────
local function MakePanel(parent, w, h)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    f:SetBackdropColor(UI.bg[1], UI.bg[2], UI.bg[3], UI.bg[4])
    f:SetBackdropBorderColor(UI.border[1], UI.border[2], UI.border[3], UI.border[4])
    return f
end

local function MakeButton(parent, w, h, text, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w, h)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(UI.btnNormal[1], UI.btnNormal[2], UI.btnNormal[3], 1)
    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.label:SetAllPoints()
    btn.label:SetText(text)
    btn.label:SetTextColor(UI.text[1], UI.text[2], UI.text[3])
    btn:SetScript("OnEnter",    function(s) s.bg:SetColorTexture(UI.btnHover[1], UI.btnHover[2], UI.btnHover[3], 1) end)
    btn:SetScript("OnLeave",    function(s) s.bg:SetColorTexture(UI.btnNormal[1], UI.btnNormal[2], UI.btnNormal[3], 1) end)
    btn:SetScript("OnMouseDown",function(s) s.bg:SetColorTexture(UI.btnPress[1], UI.btnPress[2], UI.btnPress[3], 1) end)
    btn:SetScript("OnMouseUp",  function(s) s.bg:SetColorTexture(UI.btnNormal[1], UI.btnNormal[2], UI.btnNormal[3], 1) end)
    if onClick then btn:SetScript("OnClick", onClick) end
    return btn
end

local function MakeLabel(parent, text, sz)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetFont("Fonts\\FRIZQT__.TTF", sz or 13, "")
    fs:SetTextColor(UI.text[1], UI.text[2], UI.text[3])
    fs:SetText(text)
    return fs
end

local function MakeCheckbox(parent, labelText, getVal, setVal)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    if cb.text then
        cb.text:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
        cb.text:SetTextColor(UI.text[1], UI.text[2], UI.text[3])
        cb.text:SetText(labelText)
    end
    cb:SetChecked(getVal())
    cb:SetScript("OnClick", function(self) setVal(self:GetChecked()) end)
    return cb
end

local function MakeEditBox(parent, w, h)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(w, h or 18)
    eb:SetAutoFocus(false)
    if GameFontNormalSmall then eb:SetFontObject(GameFontNormalSmall) end
    return eb
end

-- Slider with a header label and a live value readout to its right
local function MakeSlider(parent, labelText, minV, maxV, step, getVal, setVal, w)
    w = w or 180
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(w, 38)

    local lbl = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    lbl:SetTextColor(UI.text[1], UI.text[2], UI.text[3])
    lbl:SetText(labelText)
    lbl:SetPoint("TOPLEFT", 0, 0)

    local sl = CreateFrame("Slider", nil, c, "OptionsSliderTemplate")
    sl:SetSize(w - 44, 14)
    sl:SetPoint("TOPLEFT", 0, -16)
    sl:SetMinMaxValues(minV, maxV)
    sl:SetValueStep(step)
    sl:SetObeyStepOnDrag(true)
    sl:SetValue(getVal())
    if sl.Low  then sl.Low:SetText(tostring(minV))  end
    if sl.High then sl.High:SetText(tostring(maxV)) end
    if sl.Text then sl.Text:SetText("") end

    local valLbl = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valLbl:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    valLbl:SetTextColor(UI.accent[1], UI.accent[2], UI.accent[3])
    valLbl:SetText(tostring(getVal()))
    valLbl:SetPoint("LEFT", sl, "RIGHT", 4, 0)

    sl:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val / step + 0.5) * step
        valLbl:SetText(tostring(val))
        setVal(val)
    end)

    return c
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Config panel construction
-- ─────────────────────────────────────────────────────────────────────────────
local POSITIONS_LIST    = { "CENTER", "TOP_LEFT", "TOP_RIGHT", "BOTTOM_LEFT", "BOTTOM_RIGHT" }
local LAYOUT_DIR_LIST   = { "HORIZONTAL", "VERTICAL" }
local NAME_ANCHOR_LIST  = { "CENTER", "TOP_LEFT", "TOP_RIGHT", "BOTTOM_LEFT", "BOTTOM_RIGHT" }
local NAME_OUTLINE_LIST = { "NONE", "OUTLINE", "THICKOUTLINE" }
local FILTER_PRESETS  = {
    "HELPFUL",
    "HARMFUL",
    "HELPFUL|RAID",
    "HELPFUL|PLAYER",
    "HELPFUL|RAID|PLAYER",
    "HARMFUL|RAID",
    "HELPFUL|NOT_SELF",
    "HARMFUL|NOT_SELF",
}

local function BuildConfigFrame()
    if configFrame then configFrame:Show(); return end

    local W, H = 560, 590
    configFrame = MakePanel(UIParent, W, H)
    -- Restore saved position or default to CENTER
    local cp = JarsRaidDB.configPos
    if cp then
        configFrame:SetPoint(cp.point, UIParent, cp.relPoint, cp.x, cp.y)
    else
        configFrame:SetPoint("CENTER")
    end
    configFrame:SetMovable(true)
    configFrame:SetClampedToScreen(true)
    configFrame:EnableMouse(true)
    configFrame:SetFrameStrata("DIALOG")
    configFrame:SetFrameLevel(100)
    configFrame:RegisterForDrag("LeftButton")
    configFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    configFrame:SetScript("OnDragStop",  function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        JarsRaidDB.configPos = { point = point, relPoint = relPoint, x = x, y = y }
    end)

    -- Header bar
    local hdr = configFrame:CreateTexture(nil, "BACKGROUND")
    hdr:SetPoint("TOPLEFT"); hdr:SetPoint("TOPRIGHT"); hdr:SetHeight(28)
    hdr:SetColorTexture(UI.header[1], UI.header[2], UI.header[3], 1)

    local titleLbl = MakeLabel(configFrame, "JarsRaid  —  Config", 15)
    titleLbl:SetPoint("TOPLEFT", 10, -8)
    titleLbl:SetTextColor(UI.accent[1], UI.accent[2], UI.accent[3])

    MakeButton(configFrame, 60, 20, "Close", function() configFrame:Hide() end)
    :SetPoint("TOPRIGHT", -6, -4)

    -- Tabs
    local TAB_NAMES  = { "General", "Aura Slots", "Boss", "My Frame", "HoT Frames" }
    local tabs       = {}
    local tabPanels  = {}
    local activeTab  = 0

    local function ShowTab(idx)
        activeTab = idx
        for i = 1, #TAB_NAMES do
            tabPanels[i]:SetShown(i == idx)
            if i == idx then
                tabs[i].bg:SetColorTexture(UI.accent[1], UI.accent[2], UI.accent[3], 0.25)
                tabs[i].label:SetTextColor(UI.accent[1], UI.accent[2], UI.accent[3])
            else
                tabs[i].bg:SetColorTexture(UI.btnNormal[1], UI.btnNormal[2], UI.btnNormal[3], 1)
                tabs[i].label:SetTextColor(UI.text[1], UI.text[2], UI.text[3])
            end
        end
    end

    for i, name in ipairs(TAB_NAMES) do
        local tab = MakeButton(configFrame, 108, 22, name, function() ShowTab(i) end)
        tab:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 8 + (i - 1) * 112, -30)
        tabs[i] = tab

        local panel = CreateFrame("Frame", nil, configFrame)
        panel:SetPoint("TOPLEFT",     configFrame, "TOPLEFT",     8,  -56)
        panel:SetPoint("BOTTOMRIGHT", configFrame, "BOTTOMRIGHT", -8,   8)
        panel:Hide()
        tabPanels[i] = panel
    end

    -- ── General tab ──────────────────────────────────────────────────────────
    -- Left column (x=10, w=240): sliders + layout toggle
    -- Right column (x=295): Sort By label, 4 sort buttons, then checkboxes stacked
    local gen = tabPanels[1]
    local gy  = -8   -- left column cursor
    local ry  = -8   -- right column cursor
    local SL_W = 240
    local RC_X = 295

    local function AddSlider(lbl, minV, maxV, step, getF, setF)
        local s = MakeSlider(gen, lbl, minV, maxV, step, getF, setF, SL_W)
        s:SetPoint("TOPLEFT", gen, "TOPLEFT", 10, gy)
        gy = gy - 44
        return s
    end

    AddSlider("Frame Width",  50, 200, 1,
        function() return D("frameWidth") end,
        function(v) JarsRaidDB.frameWidth = v; LayoutRaidFrames() end)

    AddSlider("Frame Height", 16, 80, 1,
        function() return D("frameHeight") end,
        function(v) JarsRaidDB.frameHeight = v; LayoutRaidFrames() end)

    AddSlider("Columns / Rows per group", 1, 10, 1,
        function() return D("columns") end,
        function(v) JarsRaidDB.columns = v; LayoutRaidFrames() end)

    -- Layout direction toggle (compact, no hint)
    local ldirLbl = MakeLabel(gen, "Layout:", 13)
    ldirLbl:SetPoint("TOPLEFT", gen, "TOPLEFT", 10, gy)
    local ldirVal = MakeLabel(gen, D("layoutDirection") or "HORIZONTAL", 13)
    ldirVal:SetPoint("TOPLEFT", gen, "TOPLEFT", 80, gy)
    ldirVal:SetTextColor(UI.accent[1], UI.accent[2], UI.accent[3])
    local ldirBtn = MakeButton(gen, 26, 20, ">", nil)
    ldirBtn:SetPoint("LEFT", ldirVal, "RIGHT", 8, 0)
    ldirBtn:SetScript("OnClick", function()
        local newDir = CycleNext(LAYOUT_DIR_LIST, D("layoutDirection") or "HORIZONTAL")
        JarsRaidDB.layoutDirection = newDir
        ldirVal:SetText(newDir)
        LayoutRaidFrames()
    end)
    gy = gy - 28

    AddSlider("Padding", 0, 20, 1,
        function() return D("padding") end,
        function(v) JarsRaidDB.padding = v; LayoutRaidFrames() end)

    AddSlider("Font Size", 6, 18, 1,
        function() return D("fontSize") end,
        function(v) JarsRaidDB.fontSize = v; LayoutRaidFrames() end)

    -- Name Position
    local namePosLbl = MakeLabel(gen, "Name Pos:", 13)
    namePosLbl:SetPoint("TOPLEFT", gen, "TOPLEFT", 10, gy)
    local namePosVal = MakeLabel(gen, D("nameAnchor") or "CENTER", 13)
    namePosVal:SetPoint("TOPLEFT", gen, "TOPLEFT", 90, gy)
    namePosVal:SetTextColor(UI.accent[1], UI.accent[2], UI.accent[3])
    local namePosBtn = MakeButton(gen, 26, 20, ">", nil)
    namePosBtn:SetPoint("LEFT", namePosVal, "RIGHT", 8, 0)
    namePosBtn:SetScript("OnClick", function()
        local newA = CycleNext(NAME_ANCHOR_LIST, D("nameAnchor") or "CENTER")
        JarsRaidDB.nameAnchor = newA
        namePosVal:SetText(newA)
        LayoutRaidFrames()
    end)
    gy = gy - 28

    AddSlider("Name Font Size", 6, 18, 1,
        function() return D("nameFontSize") end,
        function(v) JarsRaidDB.nameFontSize = v; LayoutRaidFrames() end)

    AddSlider("Range Fade %", 0, 100, 5,
        function() return D("rangeAlpha") end,
        function(v) JarsRaidDB.rangeAlpha = v end)

    -- Name Outline
    local nameOlLbl = MakeLabel(gen, "Name Outline:", 13)
    nameOlLbl:SetPoint("TOPLEFT", gen, "TOPLEFT", 10, gy)
    local nameOlVal = MakeLabel(gen, D("nameOutline") or "NONE", 13)
    nameOlVal:SetPoint("TOPLEFT", gen, "TOPLEFT", 110, gy)
    nameOlVal:SetTextColor(UI.accent[1], UI.accent[2], UI.accent[3])
    local nameOlBtn = MakeButton(gen, 26, 20, ">", nil)
    nameOlBtn:SetPoint("LEFT", nameOlVal, "RIGHT", 8, 0)
    nameOlBtn:SetScript("OnClick", function()
        local newO = CycleNext(NAME_OUTLINE_LIST, D("nameOutline") or "NONE")
        JarsRaidDB.nameOutline = newO
        nameOlVal:SetText(newO)
        LayoutRaidFrames()
    end)
    gy = gy - 28

    -- Right column: Sort By label
    local sortLbl = MakeLabel(gen, "Sort By:", 13)
    sortLbl:SetPoint("TOPLEFT", gen, "TOPLEFT", RC_X, ry)
    ry = ry - 26

    -- Sort buttons stacked in right column
    local sortOptions = { "ROLE", "CLASS", "GROUP", "NAME" }
    for _, opt in ipairs(sortOptions) do
        local btn = MakeButton(gen, 100, 22, opt, function()
            JarsRaidDB.sortBy = opt; LayoutRaidFrames()
        end)
        btn:SetPoint("TOPLEFT", gen, "TOPLEFT", RC_X, ry)
        ry = ry - 28
    end

    -- Right column: Checkboxes stacked
    ry = ry - 6
    local checks = {
        { " Names",                function() return D("showNames") end,          function(v) JarsRaidDB.showNames = v; LayoutRaidFrames() end },
        { " Class Colours",        function() return D("showClassColors") end,    function(v) JarsRaidDB.showClassColors = v; LayoutRaidFrames() end },
        { " Role Icons",           function() return D("showRoleIcon") end,       function(v) JarsRaidDB.showRoleIcon = v; LayoutRaidFrames() end },
        { " Show In Party",        function() return D("useInParty") end,         function(v) JarsRaidDB.useInParty = v; LayoutRaidFrames() end },
        { " Lock Position",        function() return D("locked") end,             function(v) JarsRaidDB.locked = v end },
        { " Hide Blizzard Frames", function() return D("hideBlizzardFrames") end, function(v) JarsRaidDB.hideBlizzardFrames = v; UpdateBlizzardFrameVisibility() end },
        { " Threat Border",        function() return D("threatBorder")       end, function(v) JarsRaidDB.threatBorder = v; LayoutRaidFrames() end },
        { " Range Fade",           function() return D("showRangeAlpha")     end, function(v) JarsRaidDB.showRangeAlpha = v end },
    }
    for _, cd in ipairs(checks) do
        local cb = MakeCheckbox(gen, cd[1], cd[2], cd[3])
        cb:SetPoint("TOPLEFT", gen, "TOPLEFT", RC_X - 4, ry)
        ry = ry - 26
    end

    -- Test Mode buttons
    ry = ry - 10
    local testLbl = MakeLabel(gen, "Test Mode:", 13)
    testLbl:SetPoint("TOPLEFT", gen, "TOPLEFT", RC_X, ry)
    ry = ry - 24
    for _, cfg in ipairs({{10,"Test 10"},{20,"Test 20"},{40,"Test 40"}}) do
        local btn = MakeButton(gen, 100, 22, cfg[2], function()
            StartTestMode(cfg[1])
        end)
        btn:SetPoint("TOPLEFT", gen, "TOPLEFT", RC_X, ry)
        ry = ry - 28
    end
    local stopBtn = MakeButton(gen, 100, 22, "Stop Test", function()
        StopTestMode()
    end)
    stopBtn:SetPoint("TOPLEFT", gen, "TOPLEFT", RC_X, ry)
    ry = ry - 28

    -- ── Aura Slots tab ────────────────────────────────────────────────────────
    -- Uniform column positions for all rows:
    --   CX_LBL=10   label
    --   CX_VAL=94   value (accent)
    --   CX_PREV=260 < button
    --   CX_NEXT=288 > button
    --   Right section (Count / Icon Size) starts at CX_VAL+110
    local slotTab = tabPanels[2]
    local sy      = -6
    local FS      = 12    -- slot row font size
    local CX_LBL  = 10
    local CX_VAL  = 94
    local CX_PREV = 260
    local CX_NEXT = 288

    for s = 1, 5 do
        local _s = s

        -- ── Slot header strip ──────────────────────────────────────────────
        local strip = slotTab:CreateTexture(nil, "BACKGROUND")
        strip:SetPoint("TOPLEFT",  slotTab, "TOPLEFT",  4, sy)
        strip:SetPoint("TOPRIGHT", slotTab, "TOPRIGHT", -4, sy)
        strip:SetHeight(20)
        strip:SetColorTexture(UI.header[1], UI.header[2], UI.header[3], 1)

        local slLbl = MakeLabel(slotTab, "Slot " .. s, 13)
        slLbl:SetPoint("TOPLEFT", slotTab, "TOPLEFT", 10, sy - 2)
        slLbl:SetTextColor(UI.accent[1], UI.accent[2], UI.accent[3])

        local enCb = CreateFrame("CheckButton", nil, slotTab, "UICheckButtonTemplate")
        enCb:SetSize(20, 20)
        enCb:SetPoint("TOPRIGHT", slotTab, "TOPRIGHT", -8, sy)
        enCb:SetChecked(DS(s, "enabled"))
        if enCb.text then
            enCb.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
            enCb.text:SetTextColor(UI.textDim[1], UI.textDim[2], UI.textDim[3])
            enCb.text:SetText("on")
        end
        enCb:SetScript("OnClick", function(self)
            SetDS(_s, "enabled", self:GetChecked())
            LayoutRaidFrames()
        end)
        sy = sy - 22

        -- ── Row A: Position ────────────────────────────────────────────────
        local posLbl = MakeLabel(slotTab, "Position:", FS)
        posLbl:SetPoint("TOPLEFT", slotTab, "TOPLEFT", CX_LBL, sy)

        local posVal = MakeLabel(slotTab, DS(s, "position") or "BOTTOM_RIGHT", FS)
        posVal:SetPoint("TOPLEFT", slotTab, "TOPLEFT", CX_VAL, sy)
        posVal:SetTextColor(UI.accent[1], UI.accent[2], UI.accent[3])

        local posNext = MakeButton(slotTab, 26, 18, ">", nil)
        posNext:SetPoint("TOPLEFT", slotTab, "TOPLEFT", CX_NEXT, sy - 1)
        posNext:SetScript("OnClick", function()
            local newPos = CycleNext(POSITIONS_LIST, DS(_s, "position") or "BOTTOM_RIGHT")
            SetDS(_s, "position", newPos)
            posVal:SetText(newPos)
            for _, f in ipairs(raidFrames) do PositionSlot(f, _s) end
        end)
        sy = sy - 22

        -- ── Row B: Filter (< value >) ──────────────────────────────────────
        local filtLbl = MakeLabel(slotTab, "Filter:", FS)
        filtLbl:SetPoint("TOPLEFT", slotTab, "TOPLEFT", CX_LBL, sy)

        local filtVal = MakeLabel(slotTab, DS(s, "filter") or "HELPFUL", FS)
        filtVal:SetPoint("TOPLEFT", slotTab, "TOPLEFT", CX_VAL, sy)
        filtVal:SetTextColor(UI.accent[1], UI.accent[2], UI.accent[3])

        local function EnsureInPresets(val)
            if not val then return end
            for _, v in ipairs(FILTER_PRESETS) do if v == val then return end end
            table.insert(FILTER_PRESETS, val)
        end
        EnsureInPresets(DS(s, "filter"))

        local filtPrev = MakeButton(slotTab, 26, 18, "<", nil)
        filtPrev:SetPoint("TOPLEFT", slotTab, "TOPLEFT", CX_PREV, sy - 1)
        filtPrev:SetScript("OnClick", function()
            local newFilt = CyclePrev(FILTER_PRESETS, DS(_s, "filter") or "HELPFUL")
            SetDS(_s, "filter", newFilt)
            filtVal:SetText(newFilt)
            LayoutRaidFrames()
        end)

        local filtNext = MakeButton(slotTab, 26, 18, ">", nil)
        filtNext:SetPoint("TOPLEFT", slotTab, "TOPLEFT", CX_NEXT, sy - 1)
        filtNext:SetScript("OnClick", function()
            local newFilt = CycleNext(FILTER_PRESETS, DS(_s, "filter") or "HELPFUL")
            SetDS(_s, "filter", newFilt)
            filtVal:SetText(newFilt)
            LayoutRaidFrames()
        end)
        sy = sy - 22

        -- ── Row C: Count | Icon Size ────────────────────────────────────────
        local cntLbl = MakeLabel(slotTab, "Count:", FS)
        cntLbl:SetPoint("TOPLEFT", slotTab, "TOPLEFT", CX_LBL, sy)

        local cntEB = MakeEditBox(slotTab, 36, 18)
        cntEB:SetPoint("TOPLEFT", slotTab, "TOPLEFT", CX_VAL, sy - 1)
        cntEB:SetText(tostring(DS(s, "count") or 4))
        cntEB:SetScript("OnEnterPressed", function(self)
            local v = tonumber(self:GetText())
            if v then
                SetDS(_s, "count", math.max(0, math.min(MAX_SLOT_ICONS, math.floor(v))))
                self:ClearFocus()
                for _, f in ipairs(raidFrames) do PositionSlot(f, _s) end
                LayoutRaidFrames()
            end
        end)
        cntEB:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        local szLbl = MakeLabel(slotTab, "Icon Size:", FS)
        szLbl:SetPoint("TOPLEFT", slotTab, "TOPLEFT", CX_VAL + 55, sy)

        local szEB = MakeEditBox(slotTab, 36, 18)
        szEB:SetPoint("TOPLEFT", slotTab, "TOPLEFT", CX_VAL + 136, sy - 1)
        szEB:SetText(tostring(DS(s, "iconSize") or 14))
        szEB:SetScript("OnEnterPressed", function(self)
            local v = tonumber(self:GetText())
            if v then
                SetDS(_s, "iconSize", math.max(6, math.min(40, math.floor(v))))
                self:ClearFocus()
                for _, f in ipairs(raidFrames) do PositionSlot(f, _s) end
                LayoutRaidFrames()
            end
        end)
        szEB:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        sy = sy - 28  -- gap between slots
    end

    -- ── Boss tab ─────────────────────────────────────────────────────────────
    local bossTab = tabPanels[3]
    local by      = -10

    -- Enable checkbox
    local bossEnCb = MakeCheckbox(bossTab, " Enable Boss Frames",
        function() return D("bossEnabled") end,
        function(v) JarsRaidDB.bossEnabled = v; LayoutBossFrames() end)
    bossEnCb:SetPoint("TOPLEFT", bossTab, "TOPLEFT", 6, by)
    by = by - 30

    -- Attach side
    local ATTACH_LIST = { "LEFT", "TOP" }
    local attachLbl = MakeLabel(bossTab, "Attach:", 13)
    attachLbl:SetPoint("TOPLEFT", bossTab, "TOPLEFT", 10, by)
    local attachVal = MakeLabel(bossTab, D("bossAttach") or "LEFT", 13)
    attachVal:SetPoint("TOPLEFT", bossTab, "TOPLEFT", 80, by)
    attachVal:SetTextColor(UI.accent[1], UI.accent[2], UI.accent[3])
    local attachBtn = MakeButton(bossTab, 26, 20, ">", nil)
    attachBtn:SetPoint("LEFT", attachVal, "RIGHT", 8, 0)
    attachBtn:SetScript("OnClick", function()
        local newA = CycleNext(ATTACH_LIST, D("bossAttach") or "LEFT")
        JarsRaidDB.bossAttach = newA
        attachVal:SetText(newA)
        LayoutBossFrames()
    end)
    by = by - 30

    -- Hint text
    local attachHint = bossTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    attachHint:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    attachHint:SetTextColor(UI.textDim[1], UI.textDim[2], UI.textDim[3])
    attachHint:SetText("LEFT → boss column to the left of raid frames\nTOP → boss column above raid frames")
    attachHint:SetPoint("TOPLEFT", bossTab, "TOPLEFT", 10, by)
    attachHint:SetJustifyH("LEFT")
    by = by - 36

    local function BossSlider(lbl, minV, maxV, step, getF, setF)
        local s = MakeSlider(bossTab, lbl, minV, maxV, step, getF, setF, 260)
        s:SetPoint("TOPLEFT", bossTab, "TOPLEFT", 10, by)
        by = by - 44
        return s
    end

    BossSlider("Boss Count (1-5)", 1, 5, 1,
        function() return D("bossCount") end,
        function(v) JarsRaidDB.bossCount = v; LayoutBossFrames() end)

    BossSlider("Boss Frame Width", 40, 200, 1,
        function() return D("bossFrameWidth") or D("frameWidth") end,
        function(v) JarsRaidDB.bossFrameWidth = v; LayoutBossFrames() end)

    BossSlider("Boss Frame Height", 16, 80, 1,
        function() return D("bossFrameHeight") or D("frameHeight") end,
        function(v) JarsRaidDB.bossFrameHeight = v; LayoutBossFrames() end)

    -- ── My Frame tab ───────────────────────────────────────────────────────────
    -- Independent aura config for the player's own raid frame only.
    -- (Reading auras on "player" uses the same unrestricted C_UnitAuras API.)
    local myTab = tabPanels[4]
    local mty   = -8

    -- Enable checkbox
    local myEnCb = MakeCheckbox(myTab, " Override my own frame's auras",
        function() return D("myFrameEnabled") end,
        function(v)
            JarsRaidDB.myFrameEnabled = v
            LayoutRaidFrames()
        end)
    myEnCb:SetPoint("TOPLEFT", myTab, "TOPLEFT", 6, mty)
    mty = mty - 30

    -- Same slot layout as Aura Slots tab but uses DM/SetDM
    local FS_M  = 12
    local MCX_LBL  = 10
    local MCX_VAL  = 94
    local MCX_PREV = 260
    local MCX_NEXT = 288

    for s = 1, 5 do
        local _s = s

        -- Header strip
        local mstrip = myTab:CreateTexture(nil, "BACKGROUND")
        mstrip:SetPoint("TOPLEFT",  myTab, "TOPLEFT",  4, mty)
        mstrip:SetPoint("TOPRIGHT", myTab, "TOPRIGHT", -4, mty)
        mstrip:SetHeight(20)
        mstrip:SetColorTexture(UI.header[1], UI.header[2], UI.header[3], 1)

        local mSlLbl = MakeLabel(myTab, "Slot " .. s, 13)
        mSlLbl:SetPoint("TOPLEFT", myTab, "TOPLEFT", 10, mty - 2)
        mSlLbl:SetTextColor(UI.accent[1], UI.accent[2], UI.accent[3])

        local mEnCb = CreateFrame("CheckButton", nil, myTab, "UICheckButtonTemplate")
        mEnCb:SetSize(20, 20)
        mEnCb:SetPoint("TOPRIGHT", myTab, "TOPRIGHT", -8, mty)
        mEnCb:SetChecked(DM(s, "enabled"))
        if mEnCb.text then
            mEnCb.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
            mEnCb.text:SetTextColor(UI.textDim[1], UI.textDim[2], UI.textDim[3])
            mEnCb.text:SetText("on")
        end
        mEnCb:SetScript("OnClick", function(self)
            SetDM(_s, "enabled", self:GetChecked())
            LayoutRaidFrames()
        end)
        mty = mty - 22

        -- Row A: Position
        local mPosLbl = MakeLabel(myTab, "Position:", FS_M)
        mPosLbl:SetPoint("TOPLEFT", myTab, "TOPLEFT", MCX_LBL, mty)
        local mPosVal = MakeLabel(myTab, DM(s, "position") or "BOTTOM_RIGHT", FS_M)
        mPosVal:SetPoint("TOPLEFT", myTab, "TOPLEFT", MCX_VAL, mty)
        mPosVal:SetTextColor(UI.accent[1], UI.accent[2], UI.accent[3])
        local mPosNext = MakeButton(myTab, 26, 18, ">", nil)
        mPosNext:SetPoint("TOPLEFT", myTab, "TOPLEFT", MCX_NEXT, mty - 1)
        mPosNext:SetScript("OnClick", function()
            local newPos = CycleNext(POSITIONS_LIST, DM(_s, "position") or "BOTTOM_RIGHT")
            SetDM(_s, "position", newPos)
            mPosVal:SetText(newPos)
            for _, f in ipairs(raidFrames) do PositionMySlot(f, _s) end
        end)
        mty = mty - 22

        -- Row B: Filter
        local mFiltLbl = MakeLabel(myTab, "Filter:", FS_M)
        mFiltLbl:SetPoint("TOPLEFT", myTab, "TOPLEFT", MCX_LBL, mty)
        local mFiltVal = MakeLabel(myTab, DM(s, "filter") or "HELPFUL", FS_M)
        mFiltVal:SetPoint("TOPLEFT", myTab, "TOPLEFT", MCX_VAL, mty)
        mFiltVal:SetTextColor(UI.accent[1], UI.accent[2], UI.accent[3])

        local mFiltPrev = MakeButton(myTab, 26, 18, "<", nil)
        mFiltPrev:SetPoint("TOPLEFT", myTab, "TOPLEFT", MCX_PREV, mty - 1)
        mFiltPrev:SetScript("OnClick", function()
            local nf = CyclePrev(FILTER_PRESETS, DM(_s, "filter") or "HELPFUL")
            SetDM(_s, "filter", nf); mFiltVal:SetText(nf); LayoutRaidFrames()
        end)
        local mFiltNext = MakeButton(myTab, 26, 18, ">", nil)
        mFiltNext:SetPoint("TOPLEFT", myTab, "TOPLEFT", MCX_NEXT, mty - 1)
        mFiltNext:SetScript("OnClick", function()
            local nf = CycleNext(FILTER_PRESETS, DM(_s, "filter") or "HELPFUL")
            SetDM(_s, "filter", nf); mFiltVal:SetText(nf); LayoutRaidFrames()
        end)
        mty = mty - 22

        -- Row C: Count | Icon Size
        local mCntLbl = MakeLabel(myTab, "Count:", FS_M)
        mCntLbl:SetPoint("TOPLEFT", myTab, "TOPLEFT", MCX_LBL, mty)
        local mCntEB = MakeEditBox(myTab, 36, 18)
        mCntEB:SetPoint("TOPLEFT", myTab, "TOPLEFT", MCX_VAL, mty - 1)
        mCntEB:SetText(tostring(DM(s, "count") or 4))
        mCntEB:SetScript("OnEnterPressed", function(self)
            local v = tonumber(self:GetText())
            if v then
                SetDM(_s, "count", math.max(0, math.min(MAX_SLOT_ICONS, math.floor(v))))
                self:ClearFocus()
                for _, f in ipairs(raidFrames) do PositionMySlot(f, _s) end
                LayoutRaidFrames()
            end
        end)
        mCntEB:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        local mSzLbl = MakeLabel(myTab, "Icon Size:", FS_M)
        mSzLbl:SetPoint("TOPLEFT", myTab, "TOPLEFT", MCX_VAL + 55, mty)
        local mSzEB = MakeEditBox(myTab, 36, 18)
        mSzEB:SetPoint("TOPLEFT", myTab, "TOPLEFT", MCX_VAL + 136, mty - 1)
        mSzEB:SetText(tostring(DM(s, "iconSize") or 14))
        mSzEB:SetScript("OnEnterPressed", function(self)
            local v = tonumber(self:GetText())
            if v then
                SetDM(_s, "iconSize", math.max(6, math.min(40, math.floor(v))))
                self:ClearFocus()
                for _, f in ipairs(raidFrames) do PositionMySlot(f, _s) end
                LayoutRaidFrames()
            end
        end)
        mSzEB:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        mty = mty - 28
    end

    -- ── HoT Frames tab ──────────────────────────────────────────────────────────
    local hotTab = tabPanels[5]
    local hy = -6

    -- Character indicator (per-character config)
    local charLbl = MakeLabel(hotTab, "Character: " .. GetCharacterKey(), 11)
    charLbl:SetPoint("TOPLEFT", hotTab, "TOPLEFT", 10, hy)
    charLbl:SetTextColor(UI.textDim[1], UI.textDim[2], UI.textDim[3])
    hy = hy - 20

    local HOT_SLOT_LABELS = { "Slot 1 (Far-Left)", "Slot 2 (Left-Center)",
                               "Slot 3 (Right-Center)", "Slot 4 (Far-Right)" }

    for s = 1, 4 do
        local _s = s

        -- Slot header bar
        local strip = hotTab:CreateTexture(nil, "BACKGROUND")
        strip:SetPoint("TOPLEFT",  hotTab, "TOPLEFT",  4, hy)
        strip:SetPoint("TOPRIGHT", hotTab, "TOPRIGHT", -4, hy)
        strip:SetHeight(20)
        strip:SetColorTexture(UI.header[1], UI.header[2], UI.header[3], 1)

        local slLbl = MakeLabel(hotTab, HOT_SLOT_LABELS[s], 13)
        slLbl:SetPoint("TOPLEFT", hotTab, "TOPLEFT", 10, hy - 2)
        slLbl:SetTextColor(UI.accent[1], UI.accent[2], UI.accent[3])

        local enCb = CreateFrame("CheckButton", nil, hotTab, "UICheckButtonTemplate")
        enCb:SetSize(20, 20)
        enCb:SetPoint("TOPRIGHT", hotTab, "TOPRIGHT", -8, hy)
        enCb:SetChecked(DH(s, "enabled"))
        if enCb.text then
            enCb.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
            enCb.text:SetTextColor(UI.textDim[1], UI.textDim[2], UI.textDim[3])
            enCb.text:SetText("on")
        end
        enCb:SetScript("OnClick", function(self)
            SetDH(_s, "enabled", self:GetChecked())
            LayoutRaidFrames()
        end)
        hy = hy - 22

        -- Spell ID row
        -- Up to 3 spell IDs per slot
        for spellSlot = 1, 3 do
            local spellKey = "spell" .. spellSlot

            local spellLbl = MakeLabel(hotTab, "Spell " .. spellSlot .. ":", 12)
            spellLbl:SetPoint("TOPLEFT", hotTab, "TOPLEFT", 10, hy)

            local spellEB = MakeEditBox(hotTab, 70, 18)
            spellEB:SetPoint("TOPLEFT", hotTab, "TOPLEFT", 94, hy - 1)
            spellEB:SetText(tostring(DH(s, spellKey) or 0))

            -- Red warning for non-whitelisted spells
            local warnLbl = MakeLabel(hotTab, "", 10)
            warnLbl:SetPoint("TOPLEFT", hotTab, "TOPLEFT", 172, hy - 1)
            warnLbl:SetTextColor(1, 0, 0)  -- Red

            local function UpdateWarning()
                local spellID = tonumber(spellEB:GetText()) or 0
                if spellID ~= 0 and not IsSpellWhitelisted(spellID) then
                    warnLbl:SetText("(!)")
                else
                    warnLbl:SetText("")
                end
            end

            spellEB:SetScript("OnEnterPressed", function(self)
                local v = tonumber(self:GetText())
                if v then
                    SetDH(_s, spellKey, math.max(0, math.floor(v)))
                    self:ClearFocus()
                    UpdateWarning()
                    LayoutRaidFrames()
                end
            end)
            spellEB:SetScript("OnEscapePressed", function(self)
                self:ClearFocus()
                UpdateWarning()
            end)
            spellEB:SetScript("OnTextChanged", function()
                UpdateWarning()
            end)

            hy = hy - 20
        end

        -- Icon Size row
        local szLbl = MakeLabel(hotTab, "Icon Size:", 12)
        szLbl:SetPoint("TOPLEFT", hotTab, "TOPLEFT", 10, hy)

        local szEB = MakeEditBox(hotTab, 50, 18)
        szEB:SetPoint("TOPLEFT", hotTab, "TOPLEFT", 94, hy - 1)
        szEB:SetText(tostring(DH(s, "iconSize") or 14))
        szEB:SetScript("OnEnterPressed", function(self)
            local v = tonumber(self:GetText())
            if v then
                SetDH(_s, "iconSize", math.max(6, math.min(40, math.floor(v))))
                self:ClearFocus()
                LayoutRaidFrames()
            end
        end)
        szEB:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        hy = hy - 28  -- gap between slots
    end

    -- Padding/spacing slider
    hy = hy - 10
    local padSlider = MakeSlider(hotTab, "Slot Spacing:", 0, 50, 1,
        function() return GetHotFramesPadding() end,
        function(v) SetHotFramesPadding(v); LayoutRaidFrames() end,
        240)
    padSlider:SetPoint("TOPLEFT", hotTab, "TOPLEFT", 10, hy)

    -- Activate the first tab
    ShowTab(1)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Slash commands
-- ─────────────────────────────────────────────────────────────────────────────
SLASH_JARSRAID1 = "/jr"
SLASH_JARSRAID2 = "/jarsraid"
SlashCmdList["JARSRAID"] = function()
    if configFrame and configFrame:IsShown() then
        configFrame:Hide()
    else
        BuildConfigFrame()
        if configFrame then configFrame:Show() end
    end
end

-- Global entry point for external launchers (e.g. JarsAddonConfig)
function JarsRaid_OpenConfig()
    if configFrame and configFrame:IsShown() then
        configFrame:Hide()
    else
        BuildConfigFrame()
        if configFrame then configFrame:Show() end
    end
end
