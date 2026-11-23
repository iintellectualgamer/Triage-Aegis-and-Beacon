local _, addon = ...
local Spell = addon.Spell

-- The current spellbook, overrides, and pet bank determine the visible tiles.
local retailDispels = {
    PALADIN = { 4987, 213644, 1152, 475 },
    DRUID = { 88423, 2782 },
    MAGE = { 475 },
    SHAMAN = { 77130, 51886, 383013 },
    PRIEST = { 527, 213634, 32375 },
    MONK = { 115450, 218164 },
    EVOKER = { 360823, 365585, 374251 },
    HUNTER = { 19801, 212640 },
    WARLOCK = { 89808, 132411, 19505, 119905 },
    DEMONHUNTER = { 205604, 278326 },
    ROGUE = { 31224 },
}
local foreverDispels = {
    PALADIN = { 4987, 1152, 475 },
    DRUID = { 2782, 2893, 8946 },
    MAGE = { 475 },
    SHAMAN = { 526, 2870, 8166, 8170 },
    PRIEST = { 988, 527, 552, 528, 32375 },
    WARLOCK = { 19736, 19734, 19731, 19505 },
}
local support = {
    DEATHKNIGHT = { 61999, 51052, 48707 },
    DEMONHUNTER = { 196718, 198589, 196555 },
    DRUID = { 20484, 102342, 29166, 132158 },
    EVOKER = { 357170, 370665, 374227, 363916 },
    HUNTER = { 53271, 34477, 136, 109304 },
    MAGE = { 414660, 11958, 45438 },
    MONK = { 116841, 116849, 122783, 115203 },
    PALADIN = { 1044, 156910, 53563, 1022, 6940, 633 },
    PRIEST = { 10060, 33206, 47788, 6346, 19236 },
    ROGUE = { 57934, 114018, 185311, 5277 },
    SHAMAN = { 192077, 108271, 98008, 16190 },
    WARLOCK = { 20707, 755, 108416, 29893 },
    WARRIOR = { 3411, 97462, 426490, 23920 },
}
local petUtilities = {
    [89808] = true, [119905] = true, [19505] = true,
    [19731] = true, [19734] = true, [19736] = true,
}
local spellStyles = {
    [1044] = "freedom", [116841] = "freedom", [53271] = "freedom",
    [136] = "pet", [755] = "pet",
    [19801] = "enemy", [278326] = "enemy", [119905] = "enemy",
    [61999] = "resurrect", [20484] = "resurrect", [391054] = "resurrect",
    [2006] = "resurrect", [7328] = "resurrect", [5394] = "standalone",
    [2008] = "resurrect", [115178] = "resurrect", [361227] = "resurrect",
    [383013] = "standalone", [8166] = "standalone", [8170] = "standalone",
    [32375] = "standalone", [205604] = "standalone", [114018] = "standalone",
    [145205] = "standalone", [73920] = "standalone", [62618] = "standalone",
    [51052] = "standalone", [98008] = "standalone", [30283] = "standalone",
    [207684] = "standalone", [109248] = "standalone", [196718] = "standalone",
    [97462] = "standalone", [426490] = "standalone", [1160] = "standalone",
    [740] = "standalone", [64843] = "standalone", [85222] = "standalone",
    [355936] = "standalone", [115310] = "standalone", [388615] = "standalone",
    [29893] = "standalone", [414660] = "standalone", [192077] = "standalone",
    [108280] = "standalone", [207778] = "standalone", [264667] = "standalone",
    [31224] = "self", [20594] = "self", [265221] = "self", [1299026] = "self",
    [258920] = "self", [1241937] = "self", [185311] = "self", [109304] = "self",
    [198589] = "self", [196555] = "self", [203720] = "self", [187827] = "self",
    [48707] = "self", [48792] = "self", [49998] = "enemy",
    [22842] = "self", [19236] = "self", [5277] = "self", [23920] = "self", [871] = "self",
    [108416] = "self", [104773] = "self", [108271] = "self", [12975] = "self",
    [204021] = "enemy", [322507] = "self", [115203] = "self", [122783] = "self",
    [11958] = "self", [45438] = "self", [11426] = "self", [235313] = "self", [235450] = "self",
    [16190] = "standalone", [363916] = "self",
}
local learnedUtilityStyle = {}
local suggested = {}

local function KnownTalent(id)
    return addon.KnowsSpell(id) or (IsPlayerSpell and IsPlayerSpell(id))
end

function addon.RefreshUtility(class, profileSpellbook, forever)
    local dispels = forever and foreverDispels or retailDispels
    local shown, petNames = {}, {}
    wipe(learnedUtilityStyle)
    wipe(suggested)
    addon.preferredDispel = nil

    local function Consider(base, isDispel)
        local active = addon.ActiveSpellID(base)
        local info = Spell.GetSpellInfo(active)
        if not info then return end
        local id = active
        local pet = petUtilities[base] and addon.IsKnownPetSpell(active)
        if pet then
            if petNames[info.name] then return end
            petNames[info.name] = true
        elseif not addon.KnowsSpell(id) then
            id = profileSpellbook[info.name]
        end
        if not id or shown[id] or Spell.IsSpellPassive(id) then return end
        -- Use the highest learned rank for ranked spells and show each distinct spell once.
        local ranked = (forever or addon.IsRankedClassic()) and Spell.GetSpellSubtext(id)
        if ranked and ranked:find("%d") and not pet then id = profileSpellbook[info.name] or id end
        if shown[id] then return end
        info = Spell.GetSpellInfo(id) or info
        local style = spellStyles[active] or spellStyles[base]
        shown[id], learnedUtilityStyle[id] = true, style
        if #suggested < #addon.extraKeys then tinsert(suggested, id) end
        if isDispel and not style and not addon.preferredDispel then addon.preferredDispel = id end
    end

    for _, id in ipairs(dispels[class] or {}) do Consider(id, true) end
    if class == "DEMONHUNTER" and not forever
        and (KnownTalent(1266617) or KnownTalent(1266496) or KnownTalent(1266316)) then
        Consider(258920, true)
        Consider(1241937, true)
    end
    Consider(20594, true) -- Stoneform
    Consider(forever and 1299026 or 265221, true) -- Shatter Curse or Fireblood
    for _, id in ipairs(support[class] or {}) do Consider(id) end
end

function addon.UtilityStyle(spell)
    local info = addon.SpellInfo(spell)
    if not info then return end
    local id = info.spellID
    return learnedUtilityStyle[id] or spellStyles[id] or spellStyles[addon.ActiveSpellID(id)]
        or (Spell.GetBaseSpell and spellStyles[Spell.GetBaseSpell(id)])
end

function addon.SuggestedUtilitySpells()
    return { extra1 = suggested[1], extra2 = suggested[2] }
end

function addon.BuildUtilityTray(panel, gutter, width)
    local tray = { panel = panel }
    tray.title = addon.Label(panel, "Extra spells", nil, addon.inset, 0, addon.color.dim)
    for index in ipairs(addon.extraKeys) do
        local button = addon.Button(panel, nil, width, 32, "SecureActionButtonTemplate")
        button.left = addon.inset + gutter + (index - 1) * (width + 5)
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetPoint("LEFT", button, "LEFT", 4, 0)
        button.icon:SetSize(19, 19)
        button.name = addon.Label(button, "", nil, 27, -10)
        button.name:SetWidth(width - 32)
        button.name:SetWordWrap(false)
        button.name:SetJustifyH("LEFT")
        button.triageHealingTooltip = true
        button:SetScript("OnEnter", function(self)
            local info = self.spellInfo
            if not info or not addon.ShowHealingTooltips() then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(info.spellID)
            else GameTooltip:SetText(info.name) end
            GameTooltip:AddLine("Cast with left, right, or middle-click.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        tray[index] = button
    end
    return tray
end

function addon.UpdateUtilityTray(tray, offset)
    local spells, hidden = addon.ProfileSpells("extra"), addon.ProfileSpells("icons")
    local shown = false
    for index, key in ipairs(addon.extraKeys) do
        local button, spell = tray[index], spells[key]
        local info = addon.SpellInfo(spell)
        local visible = info ~= nil and hidden[key] ~= true
        button.spellInfo = info
        addon.ConfigureSpellKey(button, spell)
        button:SetAttribute("*type2", info and "macro" or nil)
        button:SetAttribute("*type3", info and "macro" or nil)
        if visible then
            button.name:SetText(addon.SpellText(spell))
            button.icon:SetTexture(info.iconID)
            if button.offset ~= offset then
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", tray.panel, "TOPLEFT", button.left, -offset)
                button.offset = offset
            end
            shown = true
        end
        button:SetShown(visible)
    end
    if shown then
        tray.title:ClearAllPoints()
        tray.title:SetPoint("TOPLEFT", tray.panel, "TOPLEFT", addon.inset, -offset - 10)
    end
    tray.title:SetShown(shown)
    return shown and offset + 37 or offset
end
