local _, addon = ...
local Spell = addon.Spell

local names, known, petSpells, unavailable, overrides, book = {}, {}, {}, {}, {}, {}
local catalog
local banks = Enum and Enum.SpellBookSpellBank
local kinds = Enum and Enum.SpellBookItemType
local function ModernSpellbook()
    return banks and kinds and C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines
        and C_SpellBook.GetSpellBookSkillLineInfo
        and (C_SpellBook.GetSpellBookItemType or C_SpellBook.GetSpellBookItemInfo)
end

local function ModernSlot(index, bank)
    local item = C_SpellBook.GetSpellBookItemInfo and C_SpellBook.GetSpellBookItemInfo(index, bank)
    if item then return item.itemType, item.actionID, item.spellID, item end
    if C_SpellBook.GetSpellBookItemType then return C_SpellBook.GetSpellBookItemType(index, bank) end
end

local function LegacySlot(index, bank)
    if GetSpellBookItemInfo then return GetSpellBookItemInfo(index, bank) end
    -- Older clients expose the same spell ID through the spell link.
    local link = GetSpellLink and GetSpellLink(index, bank)
    local id = link and tonumber(link:match("spell:(%d+)"))
    if id then return "SPELL", id end
end

local function SpellID(id)
    return type(id) == "number" and id > 0 and id or nil
end

function addon.ActiveSpellID(id)
    if not SpellID(id) then return id end
    local active = Spell.GetOverrideSpell(id)
    return (SpellID(active) and active ~= id and active) or overrides[id] or id
end

local function NativeKnown(id, bank)
    if not ModernSpellbook() then return false end
    if C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id, bank) then return true end
    if bank == banks.Pet then
        return not C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellInSpellBook
            and C_SpellBook.IsSpellInSpellBook(id, bank)
    end
    if C_SpellBook.FindSpellBookSlotForSpell and bank == banks.Player then
        local slot, foundBank = C_SpellBook.FindSpellBookSlotForSpell(id, false, true, false, false)
        return slot ~= nil and foundBank == bank
    end
    if C_SpellBook.IsSpellInSpellBook and C_SpellBook.IsSpellInSpellBook(id, bank) then return true end
    return C_SpellBook.IsSpellKnownOrInSpellBook and C_SpellBook.IsSpellKnownOrInSpellBook(id, bank, true)
end

function addon.KnowsSpell(id)
    return SpellID(id) and (known[id] or (not unavailable[id] and banks and NativeKnown(id, banks.Player)))
end

function addon.IsKnownPetSpell(id)
    return SpellID(id) and (petSpells[id] or (banks and banks.Pet ~= nil and NativeKnown(id, banks.Pet)))
end

local function Rank(id)
    local text = Spell.GetSpellSubtext(id)
    return text and tonumber(text:match("%d+"))
end

local function PreferName(name, id)
    local previous = names[name]
    if previous and known[previous] and not known[id] then return end
    local previousRank = previous and Rank(previous)
    local rank = previous and Rank(id)
    if not previousRank or not rank or rank >= previousRank or (known[id] and petSpells[previous]) then
        names[name] = id
    end
end

local function Record(id, source, blocked, displayName)
    id = SpellID(id)
    if not id then return end
    if blocked then unavailable[id] = true
    elseif source == "Pet" then petSpells[id] = true
    else known[id] = true end
    local name = Spell.GetSpellName(id) or displayName
    if not name or name == "" then return end
    local passive = Spell.IsSpellPassive(id)
    local state = blocked or (passive and "Passive" or "Assignable")
    local previous = book[id]
    if not previous or (source ~= "Pet" and not blocked) or not (known[id] or petSpells[id]) then
        book[id] = { id = id, name = name, source = source, state = state }
    end
    if state == "Assignable" then PreferName(name, id) end
end

local function ReadFlyout(actionID, source)
    if not (GetFlyoutInfo and GetFlyoutSlotInfo and SpellID(actionID)) then return end
    local _, _, slots, learned = GetFlyoutInfo(actionID)
    for slot = 1, slots or 0 do
        local base, active, isKnown, name = GetFlyoutSlotInfo(actionID, slot)
        if learned and isKnown then
            active = SpellID(active) or SpellID(base)
            if SpellID(base) and active and active ~= base then overrides[base] = active end
            Record(active, source, nil, name)
        else
            Record(base, source, "Unlearned", name)
        end
    end
end

local function ScanLegacy(index, bank, offSpec)
    local kind, id = LegacySlot(index, bank)
    local pet = bank == "pet"
    local source = pet and "Pet" or "Spellbook"
    if kind == "FLYOUT" then
        if not offSpec then ReadFlyout(id, source) end
        return
    end
    if not SpellID(id) or (kind ~= "SPELL" and kind ~= "FUTURESPELL"
        and not (pet and kind == "PETACTION")) then return end

    local displayName, rank
    if GetSpellBookItemName then displayName, rank = GetSpellBookItemName(index, bank)
    elseif GetSpellName then displayName, rank = GetSpellName(index, bank) end
    local blocked = offSpec and "Other spec" or (kind == "FUTURESPELL" and "Unlearned" or nil)
    if not blocked then addon.NoteSpellSlot(id, index, bank, rank, pet) end
    Record(id, source, blocked, displayName)
end

function addon.SpellAtCursorSlot(index, bank)
    if type(index) ~= "number" or index <= 0 then return end
    if ModernSpellbook() then
        if bank == "spell" then bank = banks.Player
        elseif bank == "pet" then bank = banks.Pet end
        if bank ~= nil and (bank == banks.Player or bank == banks.Pet) then
            local kind, actionID, spellID = ModernSlot(index, bank)
            if kind == kinds.Spell or (bank == banks.Pet and kinds.PetAction and kind == kinds.PetAction) then
                return SpellID(spellID) or SpellID(actionID)
            end
        end
    elseif bank == "spell" or bank == "pet" then
        local kind, id = LegacySlot(index, bank)
        if kind == "SPELL" or (bank == "pet" and kind == "PETACTION") then return SpellID(id) end
    end
end

function addon.ReadSpellbook()
    addon.ClearSpellSlots()
    wipe(names)
    wipe(known)
    wipe(petSpells)
    wipe(unavailable)
    wipe(overrides)
    wipe(book)
    catalog = nil

    if not ModernSpellbook() then
        if GetNumSpellTabs and GetSpellTabInfo then
            for tab = 1, GetNumSpellTabs() do
                local _, _, offset, count, _, offSpec = GetSpellTabInfo(tab)
                if offset and count then
                    for index = offset + 1, offset + count do
                        ScanLegacy(index, "spell", type(offSpec) == "number" and offSpec > 0)
                    end
                end
            end
        end
        local count = HasPetSpells and HasPetSpells()
        if type(count) == "number" then
            for index = 1, count do ScanLegacy(index, "pet") end
        end
        return names
    end

    local function Scan(index, bank)
        local kind, actionID, spellID, item = ModernSlot(index, bank)
        if not kind then return end
        local petBank = bank == banks.Pet
        local source = petBank and "Pet" or "Spellbook"
        if kinds.Flyout and kind == kinds.Flyout then
            if not (item and item.isOffSpec) then ReadFlyout(actionID, source) end
            return
        end
        if kinds.FutureSpell and kind == kinds.FutureSpell then
            Record(SpellID(spellID) or actionID, source, "Unlearned", item and item.name)
            return
        end
        local id = SpellID(spellID)
        if kind == kinds.Spell then id = id or SpellID(actionID)
        elseif not (petBank and kinds.PetAction and kind == kinds.PetAction) then return end
        if not id then return end
        if item and item.isOffSpec then
            Record(id, source, "Other spec", item.name)
        elseif NativeKnown(id, bank) or (kind == kinds.Spell and SpellID(actionID) and NativeKnown(actionID, bank)) then
            if kind == kinds.Spell and SpellID(actionID) and actionID ~= id then overrides[actionID] = id end
            Record(id, source, nil, item and item.name)
        end
    end

    for lineIndex = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(lineIndex)
        if line and line.itemIndexOffset and line.numSpellBookItems then
            for index = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                Scan(index, banks.Player)
            end
        end
    end
    if C_SpellBook.HasPetSpells and banks.Pet ~= nil then
        for index = 1, C_SpellBook.HasPetSpells() or 0 do Scan(index, banks.Pet) end
    end
    return names
end

function addon.SpellInfo(spell)
    if not spell or spell == addon.targetClick or spell == addon.disabledClick then return end
    if type(spell) == "string" and spell:match("^%d+$") then spell = tonumber(spell) end
    if type(spell) == "number" and (spell < 1 or spell > 2147483647 or spell % 1 ~= 0) then return end
    local info = Spell.GetSpellInfo(names[spell] or spell)
    if info then
        local active = addon.ActiveSpellID(info.spellID)
        if active ~= info.spellID and (addon.KnowsSpell(active) or addon.IsKnownPetSpell(active)) then
            return Spell.GetSpellInfo(active) or info
        end
    end
    return info
end

function addon.CanAssignSpell(info)
    local id = addon.ActiveSpellID(info.spellID)
    return not Spell.IsSpellPassive(id) and (addon.KnowsSpell(id) or addon.IsKnownPetSpell(id))
end

local function ActiveConfig()
    return C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
end

local function LegacyTrees()
    local legacy = Constants and Constants.LegacyConsts
    return legacy and { legacy.LEGACY_TREE_PROFESSIONS_ID, legacy.LEGACY_TREE_ADVENTURE_ID,
        legacy.LEGACY_TREE_PROGRESSION_ID }
end

function addon.IsTalentConfig(configID)
    local active = ActiveConfig()
    if not active or not configID or active == configID then return true end
    local legacy = LegacyTrees()
    if legacy and C_Traits and C_Traits.GetConfigIDByTreeID then
        for _, tree in pairs(legacy) do
            if C_Traits.GetConfigIDByTreeID(tree) == configID then return true end
        end
    end
    return false
end

local function AddTalent(catalogRows, id, name, source)
    id = SpellID(id)
    name = name or (id and Spell.GetSpellName(id))
    if not name or name == "" then return end
    local info = id and Spell.GetSpellInfo(id)
    local active = id and addon.ActiveSpellID(id)
    local existing = id and catalogRows[id]
    local state
    if active ~= id and addon.KnowsSpell(active) then
        state = "Replaced"
    elseif not id then
        state = "Talent only"
    elseif Spell.IsSpellPassive(id) then
        state = "Passive"
    elseif info and addon.CanAssignSpell(info) then
        state = "Assignable"
        PreferName(info.name, id)
    else
        state = existing and existing.state == "Other spec" and existing.state or "Unlearned"
    end
    if not existing or existing.name == name then
        catalogRows[id or (source .. name)] = { id = id, name = name, source = source, state = state }
    else
        catalogRows[source .. name .. id] = { id = id, name = name, source = source, state = state }
    end
end

local function ReadTree(catalogRows, configID, treeID, source, heroTrees)
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
        local node = C_Traits.GetNodeInfo(configID, nodeID)
        local hero = node and node.subTreeID and heroTrees[node.subTreeID]
        if node and (node.isVisible ~= false or hero) then
            for _, entryID in ipairs(node.entryIDs or {}) do
                local entry = C_Traits.GetEntryInfo(configID, entryID)
                local definition = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
                if definition then
                    AddTalent(catalogRows, definition.spellID, definition.overrideName,
                        node.subTreeID and "Hero talent" or source)
                end
            end
        end
    end
end

local function ReadClassicTalents(catalogRows)
    if not GetTalentInfo then return end
    local group = addon.ActiveSpecGroup()
    if addon.IsClassic() and addon.InterfaceVersion() >= 50000 then
        for tier = 1, MAX_TALENT_TIERS or 6 do
            for column = 1, NUM_TALENT_COLUMNS or 3 do
                local _, name, _, _, _, spellID = GetTalentInfo(tier, column, group)
                if type(name) == "string" then AddTalent(catalogRows, SpellID(spellID) or names[name], name, "Talent") end
            end
        end
    elseif GetNumTalentTabs and GetNumTalents then
        for tab = 1, GetNumTalentTabs() do
            for index = 1, GetNumTalents(tab) do
                local name = GetTalentInfo(tab, index, false, false, group)
                if type(name) == "string" then
                    local link = GetTalentLink and GetTalentLink(tab, index, false, false, group)
                    local id = (link and tonumber(link:match("spell:(%d+)"))) or names[name]
                    AddTalent(catalogRows, id, name, "Talent")
                end
            end
        end
    end
end

local function ReadTalents(catalogRows)
    if not (C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo
        and C_Traits.GetEntryInfo and C_Traits.GetDefinitionInfo) then
        ReadClassicTalents(catalogRows)
        return
    end
    local function ReadConfig(id)
        local config = id and C_Traits.GetConfigInfo(id)
        if not config then return end
        local heroTrees = {}
        local getHero = C_ClassTalents and C_ClassTalents.GetHeroTalentSpecsForClassSpec
        for _, tree in ipairs(getHero and getHero(id) or {}) do heroTrees[tree] = true end
        for _, treeID in ipairs(config.treeIDs or {}) do ReadTree(catalogRows, id, treeID, "Talent", heroTrees) end
    end
    local active = ActiveConfig()
    if active then
        ReadConfig(active)
    elseif addon.IsForever() and Enum.TraitConfigType and Enum.TraitConfigType.CamelotCombat and C_Traits.GetConfigsByType then
        for _, id in ipairs(C_Traits.GetConfigsByType(Enum.TraitConfigType.CamelotCombat) or {}) do ReadConfig(id) end
    end
    if C_Traits.GetConfigIDByTreeID then
        for _, treeID in pairs(LegacyTrees() or {}) do
            local id = C_Traits.GetConfigIDByTreeID(treeID)
            if id then ReadTree(catalogRows, id, treeID, "Legacy talent", {}) end
        end
    end
end

local function ReadPvPTalents(catalogRows)
    local spec = C_SpecializationInfo
    if not (spec and spec.GetPvpTalentSlotInfo) then return end
    local seen = {}
    local function AddPvP(talentID)
        if not talentID or seen[talentID] then return end
        seen[talentID] = true
        local info = spec.GetPvpTalentInfo and spec.GetPvpTalentInfo(talentID)
        if info then
            AddTalent(catalogRows, info.spellID, info.name, "PvP talent")
        elseif GetPvpTalentInfoByID then
            local _, name, _, _, _, id = GetPvpTalentInfoByID(talentID)
            AddTalent(catalogRows, id, name, "PvP talent")
        end
    end
    for index = 1, 3 do
        local slot = spec.GetPvpTalentSlotInfo(index)
        if slot then
            AddPvP(slot.selectedTalentID)
            for _, talentID in ipairs(slot.availableTalentIDs or {}) do AddPvP(talentID) end
        end
    end
end

function addon.AbilityEntries()
    if catalog then return catalog end
    local merged = {}
    for key, entry in pairs(book) do merged[key] = entry end
    ReadTalents(merged)
    ReadPvPTalents(merged)
    local sorted = {}
    for _, entry in pairs(merged) do sorted[#sorted + 1] = entry end
    table.sort(sorted, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        if a.state ~= b.state then return a.state == "Assignable" or (b.state ~= "Assignable" and a.state < b.state) end
        return (a.id or 0) < (b.id or 0)
    end)
    catalog = sorted
    return catalog
end

function addon.LearnedSpellNames()
    addon.AbilityEntries()
    local sorted = {}
    for name in pairs(names) do sorted[#sorted + 1] = name end
    table.sort(sorted)
    return sorted
end
