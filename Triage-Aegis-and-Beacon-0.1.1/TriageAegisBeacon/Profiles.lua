local _, addon = ...
local Spell = addon.Spell

addon.healModes = { "single", "area" }
addon.healModeLabels = { single = "Single target", area = "Area healing" }
addon.healSlots = {
    { key = "shift", label = "Shift + left-click", short = "Shift + left", prefix = "shift-", suffix = "1" },
    { key = "right", label = "Right-click", short = "Right-click", prefix = "", suffix = "2" },
    { key = "ctrl", label = "Ctrl + left-click", short = "Ctrl + left", prefix = "ctrl-", suffix = "1" },
}
addon.healClicks = {
    single = addon.healSlots,
    area = {
        { prefix = "shift-", suffix = "2", label = "Shift + right-click", short = "Shift + right" },
        { prefix = "alt-", suffix = "1", label = "Alt + left-click", short = "Alt + left" },
        { prefix = "ctrl-", suffix = "2", label = "Ctrl + right-click", short = "Ctrl + right" },
    },
}
addon.iconKeys = { "single1", "single2", "single3", "area1", "area2", "area3", "extra1", "extra2" }
addon.extraKeys = { "extra1", "extra2" }
addon.mouseButtonCount = 31

local modifierLabels = {
    [""] = "", ["alt-"] = "Alt", ["ctrl-"] = "Ctrl", ["shift-"] = "Shift",
    ["alt-ctrl-"] = "Alt + Ctrl", ["alt-shift-"] = "Alt + Shift",
    ["ctrl-shift-"] = "Ctrl + Shift", ["alt-ctrl-shift-"] = "Alt + Ctrl + Shift",
}
local buttonLabels = { "Left-click", "Right-click", "Middle-click" }
local buttonNumbers = { LeftButton = 1, RightButton = 2, MiddleButton = 3 }
local profileClickSlots = {
    ["1"] = { mode = "mouse", field = "left" },
    ["3"] = { mode = "mouse", field = "middle" },
    ["alt-2"] = { mode = "emergency", field = "spell" },
}
addon.targetClick = "/target"
addon.disabledClick = "None"

for _, mode in ipairs(addon.healModes) do
    for index, click in ipairs(addon.healClicks[mode]) do
        profileClickSlots[click.prefix .. click.suffix] = { mode = mode, field = addon.healSlots[index].key }
    end
end

function addon.ParseHealthClick(key)
    if type(key) ~= "string" then return end
    local prefix, suffix = key:match("^(.-)([1-9]%d?)$")
    local button = tonumber(suffix)
    if button and modifierLabels[prefix] and button <= addon.mouseButtonCount then return prefix, button end
end

function addon.ExtraHealthClick(key)
    return not profileClickSlots[key] and addon.ParseHealthClick(key) ~= nil
end

function addon.HealthClickLabel(prefix, button)
    local label = buttonLabels[button] or ("Button " .. button)
    if prefix == "" then return label end
    return modifierLabels[prefix] .. " + " .. (buttonLabels[button] and label:lower() or label)
end

function addon.ReadHealthClick(button)
    if type(button) ~= "string" then return end
    local number = buttonNumbers[button] or tonumber(button:match("^Button([1-9]%d?)$"))
    if not number or number > addon.mouseButtonCount then return end
    local prefix = (IsAltKeyDown() and "alt-" or "") .. (IsControlKeyDown() and "ctrl-" or "")
        .. (IsShiftKeyDown() and "shift-" or "")
    return prefix, number
end

-- Prefer familiar rotational spells, then defensive and utility choices.
-- The spellbook determines which entries apply to the character and client.
local candidates = {
    DRUID = {
        single = { 8936, 774, 18562, 33763, 5185, 50464, 102351, 2782 },
        area = { 48438, 145205, 740, 197721 },
    },
    EVOKER = {
        single = { 361469, 366155, 360995, 364343, 357170, 360823 },
        area = { 355936, 355916, 367226, 363534, 370960, 359816, 373861 },
    },
    MONK = {
        single = { 116670, 124682, 115151, 115175, 116849, 115450 },
        area = { 399491, 115310, 388615, 191837, 322118, 115313, 123986 },
    },
    PALADIN = {
        single = { 20473, 19750, 635, 85673, 633, 6940, 1022, 4987, 1152 },
        area = { 375576, 85222, 114165, 200025, 200652, 31821 },
    },
    PRIEST = {
        single = { 2061, 2050, 2054, 2060, 139, 47540, 17, 527 },
        area = { 34861, 204883, 194509, 596, 33076, 64843, 120517, 15237 },
    },
    SHAMAN = {
        single = { 61295, 8004, 77472, 331, 974, 77130 },
        area = { 1064, 73920, 5394, 108280, 207778, 98008 },
    },
    DEATHKNIGHT = { single = { 49998, 61999, 48707 }, area = { 51052 } },
    DEMONHUNTER = { single = { 198589, 196555, 203720 }, area = { 196718, 207684 } },
    HUNTER = { single = { 136, 109304, 34477, 53271, 53480 }, area = { 264667, 109248 } },
    MAGE = { single = { 475, 11958, 11426, 235313, 235450 }, area = { 414660, 31661, 122 } },
    ROGUE = { single = { 185311, 57934, 31224, 5277 }, area = { 114018, 212182 } },
    WARLOCK = { single = { 20707, 755, 108416, 104773 }, area = { 29893, 30283 } },
    WARRIOR = { single = { 3411, 202168, 23920, 871 }, area = { 97462, 426490, 1160 } },
}
local specializations = {
    [66] = { single = { 85673, 19750, 633 }, area = { 375576 } }, -- Protection
    [70] = { single = { 19750, 85673, 633 }, area = { 375576 } }, -- Retribution
    [104] = { single = { 22842, 8936 }, area = { 197721 } }, -- Guardian
    [250] = { single = { 49998, 48792 } }, -- Blood
    [256] = { single = { 47540, 17, 2061 }, area = { 194509, 33076, 120517, 15237 } }, -- Discipline
    [258] = { single = { 17, 186263, 19236 } }, -- Shadow
    [263] = { single = { 8004, 974, 108271 } }, -- Enhancement
    [268] = { single = { 322507, 116670, 115203 } }, -- Brewmaster
    [581] = { single = { 203720, 204021, 187827 } }, -- Vengeance
    [73] = { single = { 3411, 871, 12975 } }, -- Protection
    [1473] = { single = { 360995, 361469, 357170 } }, -- Augmentation
}
local foreverPresets = {
    DRUID = { single = { 8936, 774, 408247, 5185 }, area = { 1238213, 1238214, 1238215, 740 } },
    PALADIN = { single = { 20473, 19750, 635, 633 }, area = { 1310911, 1311590, 1311595 } },
    PRIEST = { single = { 2061, 2060, 139, 17 }, area = { 596, 401859 } },
    SHAMAN = { single = { 8004, 331, 16190 }, area = { 1064, 5394 } },
}
local emergencySpells = {
    DRUID = { 18562, 102342, 8936 },
    EVOKER = { 360995, 357170, 361469 },
    MONK = { 116849, 124682, 116670 },
    PALADIN = { 633, 20473, 19750 },
    PRIEST = { 47788, 33206, 47540, 2061 },
    SHAMAN = { 61295, 8004, 331 },
}
local racialHeals = { 28880, 59542, 59543, 59544, 59545, 59547, 59548, 121093 }
local available
local saved, effective, automatic
local activeSpec
local presetModes = { "single", "area", "mouse", "emergency", "extra", "icons", "clicks" }

local function Specialization()
    local getIndex = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
    local index = getIndex and getIndex()
    return index and index > 0 and getInfo and getInfo(index)
end

function addon.ValidSpellIdentifier(value)
    return (type(value) == "number" and value >= 1 and value <= 2147483647 and value % 1 == 0)
        or (type(value) == "string" and value:find("%S") ~= nil)
end

local function ActiveSpellInfo(spell)
    if not addon.ValidSpellIdentifier(spell) then
        return
    end
    local info = addon.SpellInfo(spell)
    if info and addon.CanAssignSpell(info) then
        return info
    end
end

local function ActiveClick(value)
    return value == addon.targetClick or value == addon.disabledClick or ActiveSpellInfo(value) ~= nil
end

function addon.IsRangeReference(spell)
    local info = ActiveSpellInfo(spell)
    return info and info.minRange == 0 and (info.maxRange or 0) > 0 and Spell.IsSpellHelpful(info.spellID)
        and addon.UtilityStyle(spell) ~= "resurrect"
end

local function AppendKnown(ids, list, seen)
    for _, id in ipairs(ids or {}) do
        local spellID = addon.ActiveSpellID(id)
        local name = Spell.GetSpellName(spellID)
        if name and not seen[name] and (available[name] or addon.KnowsSpell(spellID))
            and not Spell.IsSpellPassive(spellID) then
            list[#list + 1] = name
            seen[name] = true
        end
    end
end

local function AutoSpells(class, spec, mode, forever)
    local list, seen, result = {}, {}, {}
    local preferred = forever and foreverPresets[class] or specializations[spec]
    local common = candidates[class]
    AppendKnown(preferred and preferred[mode], list, seen)
    AppendKnown(common and common[mode], list, seen)
    if mode == "single" then
        AppendKnown(racialHeals, list, seen)
    end
    for index, slot in ipairs(addon.healSlots) do
        result[slot.key] = list[index]
    end
    return result
end

local function MigrateProfile()
    if addon.db.healingProfilesMigrated then
        return
    end
    local migrated = {}
    for _, slot in ipairs(addon.healSlots) do
        local value = addon.db.spells[slot.key]
        if addon.ValidSpellIdentifier(value) then
            migrated[slot.key] = value
        end
    end
    if next(migrated) and type(saved.single) ~= "table" then
        saved.single = migrated
    end
    addon.db.healingProfilesMigrated = true
end

function addon.RefreshProfiles()
    activeSpec = Specialization()
    local key = activeSpec and tostring(activeSpec) or "base"
    local forever = addon.IsForever()
    if forever or addon.IsClassic() then
        local group = addon.ActiveSpecGroup()
        if type(group) == "number" and group > 1 then key = key .. ":" .. group end
    end
    local store = addon.db.healingProfiles
    store[key] = type(store[key]) == "table" and store[key] or {}
    saved = store[key]
    MigrateProfile()

    local _, class = UnitClass("player")
    available = addon.ReadSpellbook()
    addon.RefreshUtility(class, available, forever)
    effective, automatic = {}, {}
    for _, mode in ipairs(addon.healModes) do
        automatic[mode] = AutoSpells(class, activeSpec, mode, forever)
        local manual = saved[mode]
        if type(manual) == "table" then
            effective[mode] = {}
            for _, slot in ipairs(addon.healSlots) do
                local spell = manual[slot.key]
                if ActiveClick(spell) then
                    effective[mode][slot.key] = spell
                end
            end
        else
            effective[mode] = automatic[mode]
        end
    end
    automatic.mouse = { middle = addon.preferredDispel }
    local recommended = {}
    AppendKnown(emergencySpells[class], recommended, {})
    automatic.emergency = { spell = recommended[1] }
    if type(saved.emergency) == "table" then
        local spell = saved.emergency.spell
        effective.emergency = { spell = ActiveClick(spell) and spell or nil }
    else
        effective.emergency = automatic.emergency
    end
    if type(saved.mouse) == "table" then
        effective.mouse = {}
        for _, key in ipairs({ "left", "middle" }) do
            local spell = saved.mouse[key]
            if ActiveClick(spell) then effective.mouse[key] = spell end
        end
    else
        effective.mouse = automatic.mouse
    end
    automatic.extra = addon.SuggestedUtilitySpells()
    if type(saved.extra) == "table" then
        effective.extra = {}
        for _, key in ipairs(addon.extraKeys) do
            if ActiveSpellInfo(saved.extra[key]) then effective.extra[key] = saved.extra[key] end
        end
    else
        effective.extra = automatic.extra
    end
    automatic.icons = {}
    effective.icons = type(saved.icons) == "table" and saved.icons or automatic.icons
    automatic.clicks, effective.clicks = {}, {}
    if type(saved.clicks) == "table" then
        local knownClicks = {}
        for key, spell in pairs(saved.clicks) do
            if addon.ExtraHealthClick(key) and addon.ValidSpellIdentifier(spell) then
                if knownClicks[spell] == nil then knownClicks[spell] = ActiveClick(spell) end
                if knownClicks[spell] then effective.clicks[key] = spell end
            end
        end
    end
    addon.primaryHeal = nil
    for _, slot in ipairs(addon.healSlots) do
        local spell = effective.single[slot.key]
        if spell and addon.IsRangeReference(spell) then
            addon.primaryHeal = spell
            break
        end
    end
end

function addon.BuildProfiles()
    addon.db.healingProfiles = type(addon.db.healingProfiles) == "table" and addon.db.healingProfiles or {}
    if not addon.healModeLabels[addon.db.healMode] then
        addon.db.healMode = "single"
    end
    addon.RefreshProfiles()
end

function addon.ProfileSpells(mode)
    return effective[mode]
end

function addon.ProfileInputs(mode)
    return type(saved[mode]) == "table" and saved[mode] or automatic[mode]
end

function addon.HealthClickInput(key)
    local slot = profileClickSlots[key]
    if slot then return addon.ProfileInputs(slot.mode)[slot.field] end
    return addon.ProfileInputs("clicks")[key]
end

function addon.HealthClickSpells()
    local spells = {}
    for key, spell in pairs(effective.clicks) do spells[key] = spell end
    for key, slot in pairs(profileClickSlots) do spells[key] = effective[slot.mode][slot.field] end
    return spells
end

function addon.SavedHealthClicks()
    local spells = {}
    if type(saved.clicks) == "table" then
        for key, spell in pairs(saved.clicks) do
            if addon.ExtraHealthClick(key) and addon.ValidSpellIdentifier(spell) then spells[key] = spell end
        end
    end
    for key, slot in pairs(profileClickSlots) do
        local group = saved[slot.mode]
        local spell = type(group) == "table" and group[slot.field]
        if addon.ValidSpellIdentifier(spell) then spells[key] = spell end
    end
    return spells
end

function addon.HealthClickChanges(edits)
    local changes = {}
    for key, spell in pairs(edits) do
        local slot = profileClickSlots[key]
        local mode, field = slot and slot.mode or "clicks", slot and slot.field or key
        local group = changes[mode]
        if not group then
            group = {}
            for field, value in pairs(addon.ProfileInputs(mode)) do group[field] = value end
            changes[mode] = group
        end
        group[field] = spell or nil
    end
    return changes
end

function addon.SetProfileOverrides(changes)
    for mode, override in pairs(changes) do
        saved[mode] = override or nil
    end
    if not InCombatLockdown() then addon.RefreshProfiles() end
end

function addon.SaveHealingPreset(key)
    if type(saved.presets) ~= "table" then saved.presets = {} end
    local snapshot = {}
    for _, mode in ipairs(presetModes) do
        snapshot[mode] = {}
        for field, value in pairs(addon.ProfileInputs(mode)) do snapshot[mode][field] = value end
    end
    saved.presets[key] = snapshot
end

function addon.HealingPreset(key)
    local preset = type(saved.presets) == "table" and saved.presets[key]
    if type(preset) ~= "table" then return end
    local copy = {}
    for _, mode in ipairs(presetModes) do
        if type(preset[mode]) == "table" then
            copy[mode] = {}
            for field, value in pairs(preset[mode]) do copy[mode][field] = value end
        end
    end
    return copy
end

function addon.SpellText(spell)
    if not spell then
        return
    end
    local info = addon.SpellInfo(spell)
    local name = info and info.name
    if name and type(spell) == "number" then
        local subtext = Spell.GetSpellSubtext(info.spellID)
        if subtext and subtext:find("%d") then
            return name .. "(" .. subtext .. ")"
        end
    end
    return name
end

function addon.HealthBarSpell(spell)
    local info = addon.SpellInfo(spell)
    if not info then return spell end
    local activeID = info.spellID
    if addon.IsForever() then return type(spell) == "number" and activeID or info.name end
    if addon.IsRankedClassic() then return addon.SpellText(spell) or info.name end
    if type(spell) == "string" and spell == info.name then return spell end

    -- Retail can use the same cast as a typed name when the live spell lookup agrees.
    -- Keep the ID when the name could resolve to a different spell.
    local name = info.name
    local namedInfo = name and Spell.GetSpellInfo(name)
    local bookID = name and available[name]
    if namedInfo and addon.ActiveSpellID(namedInfo.spellID) == activeID
        and (not bookID or addon.ActiveSpellID(bookID) == activeID) then
        return name
    end
    return activeID
end

function addon.NeedsBeaconTarget(spell)
    if not spell then return false end
    local info = addon.SpellInfo(spell)
    return info and (info.spellID == 156910 or info.spellID == 53563)
end

function addon.SpellStyle(spell)
    if not spell then return end
    local utility = addon.UtilityStyle(spell)
    if utility then return utility end
    local info = addon.SpellInfo(spell)
    if not info then return end
    local id = info.spellID
    if (id == 375576 or id == 304971) and (activeSpec == 66 or activeSpec == 70) then return "enemy" end
    local helpful = Spell.IsSpellHelpful(id)
    local harmful = Spell.IsSpellHarmful(id)
    if id == 114165 or (helpful and harmful) then return "dual" end
    if harmful then return "enemy" end
    if Spell.IsSelfBuff and (info.maxRange or 0) == 0 and Spell.IsSelfBuff(id) then
        return addon.IsKnownPetSpell(id) and not addon.KnowsSpell(id) and "standalone" or "self"
    end
    if not helpful then return "standalone" end
    return addon.NeedsBeaconTarget(spell) and "ally" or "friendly"
end

function addon.SpellMacro(spell)
    local name = addon.SpellText(spell)
    if not name then return end
    local style = addon.SpellStyle(spell)
    if style == "enemy" then
        return "/cast [@mouseover,harm,nodead][harm,nodead] " .. name
    elseif style == "self" then
        return "/cast [@player] " .. name
    elseif style == "pet" then
        return "/cast [@pet,exists,nodead] " .. name
    elseif style == "resurrect" then
        return "/cast [@mouseover,help,dead][@target,help,dead] " .. name
    elseif style == "standalone" then
        return "/cast " .. name
    elseif style == "dual" then
        return "/cast [@mouseover,help,nodead][@mouseover,harm,nodead][help,nodead][harm,nodead][@player] " .. name
    end
    local targets = "[@mouseover,help,nodead][@target,help,nodead]"
    if style ~= "ally" then targets = targets .. "[@player]" end
    return "/cast " .. targets .. " " .. name
end

function addon.ConfigureSpellKey(button, spell)
    local macro = addon.SpellMacro(spell)
    if button:GetAttribute("macrotext") ~= macro then
        button:SetAttribute("*type1", macro and "macro" or nil)
        button:SetAttribute("macrotext", macro)
    end
end
