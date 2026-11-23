local _, addon = ...
local Spell = addon.Spell

-- Spellbook IDs across supported clients. Passive effects and unavailable
-- talent choices are filtered against the current character's spellbook.
local spells = {
    DRUID = {
        single = { 8936, 774, 18562, 33763, 5185, 50464, 102351, 474754, 108238, 22842 },
        area = { 48438, 145205, 740, 197721, 102693, 391528, 1238213, 408120 },
        support = { 102342, 132158, 17116, 33891, 124974, 88423, 2782, 2893, 8946, 20484, 50769, 212040 },
    },
    EVOKER = {
        single = { 361469, 366155, 360995, 364343, 357170 },
        area = { 355936, 355916, 367226, 363534, 370960, 359816, 373861, 370537, 377509 },
        support = { 360823, 374251, 365585, 370553, 374227, 361227, 361178 },
    },
    MONK = {
        single = { 116670, 124682, 115151, 115175, 116849, 116694, 322101, 115072, 122281, 124081, 205234 },
        area = { 399491, 115310, 388615, 191837, 322118, 325197, 115313, 123986, 115098, 116847,
            388193, 443028, 1248992 },
        support = { 115450, 116680, 197908, 115294, 209584, 115178, 212051 },
    },
    PALADIN = {
        single = { 20473, 19750, 635, 85673, 114163, 633, 183998, 392928, 1310911, 20165 },
        area = { 375576, 304971, 85222, 114165, 200025, 200652, 114158, 432459, 432472, 432496,
            1289892, 1289728 },
        support = { 53563, 156910, 6940, 1022, 4987, 1152, 31821, 31884, 216331, 20216, 31842,
            414170, 7328, 212056 },
    },
    PRIEST = {
        single = { 2061, 2050, 2054, 2060, 139, 47540, 17, 186263, 373481, 200829,
            47788, 33206, 19236, 13908, 2944, 1277370, 402174 },
        area = { 34861, 204883, 194509, 596, 33076, 64843, 120517, 15237, 132157, 110744,
            122121, 265202, 724, 62618, 421453, 401859 },
        support = { 527, 213634, 528, 552, 32375, 47536, 109964, 322105, 246287, 200183,
            428924, 14751, 15286, 2006, 212036 },
    },
    SHAMAN = {
        single = { 61295, 8004, 77472, 331, 974, 73685, 188070, 408505 },
        area = { 1064, 73920, 5394, 108280, 207778, 98008, 157153, 197995, 114052,
            198838, 207399, 108281, 444995, 415236 },
        support = { 77130, 51886, 383013, 526, 2870, 8166, 8170, 378081, 16188, 443454,
            16190, 51730, 73680, 2008, 212048 },
    },
    -- Season of Discovery Mage healing runes.
    MAGE = {
        single = { 401417, 401734, 436516, 436517, 437543 },
        area = { 412510 },
    },
}

local healerSpecs = { [65] = true, [105] = true, [256] = true, [257] = true,
    [264] = true, [270] = true, [1468] = true }
local racialHeals = { 28880, 59542, 59543, 59544, 59545, 59547, 59548, 121093, 291944, 20577, 312411, 436344 }
local styles = {
    [20473] = "dual", [47540] = "dual", [361469] = "dual", [312411] = "dual", [436344] = "dual",
    [200025] = "ally", [53563] = "ally", [156910] = "ally", [1310911] = "ally",
    [1277370] = "ally", [1277371] = "ally", [1277372] = "ally", [1277373] = "ally",
    [1277374] = "ally", [1277375] = "ally", [1277376] = "ally", [1277377] = "ally", [1277378] = "ally",
    [15237] = "standalone", [132157] = "standalone",
    [110744] = "standalone", [122121] = "standalone", [120517] = "standalone",
    [145205] = "standalone", [102693] = "standalone", [391528] = "standalone",
    [355936] = "standalone", [370960] = "standalone", [359816] = "standalone",
    [373861] = "standalone", [363534] = "standalone", [370537] = "standalone",
    [322118] = "standalone", [325197] = "standalone", [115313] = "standalone",
    [123986] = "standalone", [116847] = "standalone", [388193] = "standalone",
    [443028] = "standalone", [1248992] = "standalone", [114158] = "standalone",
    [200652] = "standalone", [200183] = "standalone", [265202] = "standalone", [724] = "standalone",
    [421453] = "standalone", [114052] = "standalone", [157153] = "standalone", [197995] = "standalone",
    [198838] = "standalone", [207399] = "standalone", [444995] = "standalone",
    [20577] = "standalone", [125439] = "standalone", [291944] = "self",
    [212040] = "standalone", [361178] = "standalone", [212051] = "standalone",
    [212056] = "standalone", [212036] = "standalone", [212048] = "standalone",
    [50769] = "resurrect",
}

function addon.HealingSpellStyle(id)
    -- This ID is Circle of Healing (a unit cast) in older editions.
    if id == 34861 and not addon.IsClassic() and not addon.IsForever() then return "standalone" end
    return styles[id] or styles[Spell.GetBaseSpell(id)]
end

-- Use the live description to pick up explicit healing spells outside the
-- catalog. Match the effect at the start, keeping indirect/passive effects out.
local directHeal = {
    enUS = { "^heals? ", "^instantly heals? ", "^restores? [^%.]+ health", "^absorbs? [^%.]+ damage" },
    deDE = { "^heilt ", "^heilt sofort " },
    esES = { "^sana ", "^cura ", "^restaura [^%.]+ salud" },
    frFR = { "^soigne ", "^rend [^%.]+ points? de vie" },
    itIT = { "^cura ", "^rigenera [^%.]+ salute" },
    ptBR = { "^cura ", "^restaura [^%.]+ vida" },
    ruRU = { "^Исцеляет ", "^Восполняет [^%.]+ здоровья" },
    koKR = { "^[^.]+생명력을 [^.]+회복" },
    zhCN = { "^治疗", "^为[^。]+恢复[^。]+生命值" },
    zhTW = { "^治療", "^為[^。]+恢復[^。]+生命力" },
}
directHeal.enGB = directHeal.enUS
directHeal.esMX = directHeal.esES

local pendingDescriptions = {}

function addon.HealingDescriptionLoaded(id)
    if pendingDescriptions[id] ~= true then return false end
    pendingDescriptions[id] = false
    return true
end

local function HasHealingEffect(id)
    if not Spell.IsSpellHelpful(id) then return false end
    local patterns = directHeal[GetLocale and GetLocale() or "enUS"]
    if not patterns then return false end
    local description = Spell.GetSpellDescription(id)
    if issecretvalue and issecretvalue(description) then return false end
    if not description or description == "" then
        if pendingDescriptions[id] == nil and C_Spell and C_Spell.RequestLoadSpellData then
            pendingDescriptions[id] = true
            C_Spell.RequestLoadSpellData(id)
        end
        return false
    end
    description = description:lower()
    for _, pattern in ipairs(patterns) do
        if description:find(pattern) then return true end
    end
    return false
end

function addon.KnownHealingSpells(class, spec, available, preferred, common, forever)
    local catalog = spells[class]
    if not catalog or (spec and not forever and not addon.IsClassic() and not healerSpecs[spec]) then return end
    local results = { single = {}, area = {}, support = {} }
    local seen = {}

    local function Add(id, mode, fromBook)
        id = addon.ActiveSpellID(id)
        local name = Spell.GetSpellName(id)
        if not name or seen[name] then return end
        if forever or addon.IsRankedClassic() or not addon.KnowsSpell(id) then
            id = addon.ActiveSpellID(available[name] or id)
        end
        if addon.KnowsSpell(id) and not Spell.IsSpellPassive(id) and (not fromBook or HasHealingEffect(id)) then
            results[mode][#results[mode] + 1] = id
            seen[name] = true
        end
    end

    for _, mode in ipairs({ "single", "area", "support" }) do
        for _, id in ipairs(preferred and preferred[mode] or {}) do Add(id, mode) end
        for _, id in ipairs(class ~= "MAGE" and common and common[mode] or {}) do Add(id, mode) end
    end
    for _, mode in ipairs({ "single", "area", "support" }) do
        for _, id in ipairs(catalog[mode] or {}) do Add(id, mode) end
    end
    -- Other Mage builds keep their existing suggestions.
    if class == "MAGE" and not next(seen) then return end
    for _, id in ipairs(racialHeals) do Add(id, "support") end
    local ordered = {}
    for _, id in pairs(available) do ordered[#ordered + 1] = id end
    table.sort(ordered)
    for _, id in ipairs(ordered) do Add(id, "support", true) end
    return results
end
