local _, addon = ...

-- Classic exposes some of the spell functions globally or by spellbook slot.
-- Keep those differences inside Triage's API so other addons see the original globals.
local Spell = {}
addon.Spell = Spell
local slots = {}

function addon.ClearSpellSlots()
    wipe(slots)
end

function addon.NoteSpellSlot(id, index, bank, rank, pet)
    local previous = slots[id]
    if not previous or (previous.pet and not pet) then
        slots[id] = { index = index, bank = bank, rank = rank, pet = pet }
    end
end

function addon.InterfaceVersion()
    return select(4, GetBuildInfo()) or 0
end

function addon.IsForever()
    local interface = addon.InterfaceVersion()
    return interface >= 16000 and interface < 17000
end

function addon.IsClassic()
    local interface = addon.InterfaceVersion()
    return interface >= 10000 and interface < 60000 and not addon.IsForever()
end

function addon.IsRankedClassic()
    return addon.IsClassic() and addon.InterfaceVersion() < 40000
end

function addon.ActiveSpecGroup()
    local getGroup = (C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup)
        or GetActiveSpecGroup or GetActiveTalentGroup
    return getGroup and getGroup() or 1
end

function addon.TryRegisterEvent(frame, event)
    if C_EventUtils and C_EventUtils.IsEventValid then
        if not C_EventUtils.IsEventValid(event) then return false end
        frame:RegisterEvent(event)
        return true
    end
    return pcall(frame.RegisterEvent, frame, event)
end

function addon.TryRegisterPlayerEvent(frame, event)
    if frame.RegisterUnitEvent and pcall(frame.RegisterUnitEvent, frame, event, "player") then return true end
    return addon.TryRegisterEvent(frame, event)
end

function addon.HasWorldMarkers()
    return not addon.IsClassic() or PlaceRaidMarker ~= nil
        or (C_PartyInfo and C_PartyInfo.PlaceRaidMarker ~= nil)
        or SLASH_WORLD_MARKER1 ~= nil
end

function addon.HasNativePing()
    return not addon.IsClassic() or (C_Ping and C_Ping.SendMacroPing ~= nil)
end

function Spell.GetSpellInfo(spell)
    if C_Spell and C_Spell.GetSpellInfo then
        return C_Spell.GetSpellInfo(spell)
    end
    if not GetSpellInfo then return end
    local name, _, icon, castTime, minRange, maxRange, id, originalIcon = GetSpellInfo(spell)
    if not name then return end
    id = id or (type(spell) == "number" and spell)
    if not id then return end
    return {
        name = name, iconID = icon, originalIconID = originalIcon, castTime = castTime,
        minRange = minRange, maxRange = maxRange, spellID = id,
    }
end

function Spell.GetSpellName(spell)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spell) end
    local info = Spell.GetSpellInfo(spell)
    return info and info.name
end

function Spell.GetSpellSubtext(id)
    local slot = slots[id]
    if slot and slot.rank and slot.rank ~= "" then return slot.rank end
    if C_Spell and C_Spell.GetSpellSubtext then return C_Spell.GetSpellSubtext(id) end
    if GetSpellSubtext then return GetSpellSubtext(id) end
    if GetSpellInfo then return select(2, GetSpellInfo(id)) end
end

function Spell.GetSpellDescription(id)
    if C_Spell and C_Spell.GetSpellDescription then return C_Spell.GetSpellDescription(id) end
    if GetSpellDescription then return GetSpellDescription(id) end
end

local function BySlot(predicate, id)
    local slot = slots[id]
    if predicate and slot then return predicate(slot.index, slot.bank) end
end

function Spell.IsSpellPassive(id)
    if C_Spell and C_Spell.IsSpellPassive then return C_Spell.IsSpellPassive(id) end
    return BySlot(IsPassiveSpell, id)
end

function Spell.IsSpellHelpful(id)
    if C_Spell and C_Spell.IsSpellHelpful then return C_Spell.IsSpellHelpful(id) end
    return BySlot(IsHelpfulSpell, id)
end

function Spell.IsSpellHarmful(id)
    if C_Spell and C_Spell.IsSpellHarmful then return C_Spell.IsSpellHarmful(id) end
    return BySlot(IsHarmfulSpell, id)
end

function Spell.IsSpellInRange(id, unit)
    local value
    if C_Spell and C_Spell.IsSpellInRange then
        value = C_Spell.IsSpellInRange(id, unit)
    elseif IsSpellInRange then
        local slot = slots[id]
        if slot then
            value = IsSpellInRange(slot.index, slot.bank, unit)
        else
            local name = Spell.GetSpellName(id)
            if name then value = IsSpellInRange(name, unit) end
        end
    end
    if issecretvalue and issecretvalue(value) then return value end
    if value == 1 or value == 0 then return value == 1 end
    return value
end

function Spell.GetOverrideSpell(id)
    if C_Spell and C_Spell.GetOverrideSpell then return C_Spell.GetOverrideSpell(id) end
    if FindSpellOverrideByID then return FindSpellOverrideByID(id) end
end

function Spell.GetBaseSpell(id)
    if C_Spell and C_Spell.GetBaseSpell then return C_Spell.GetBaseSpell(id) end
    if FindBaseSpellByID then return FindBaseSpellByID(id) end
end

function Spell.IsSelfBuff(id)
    return C_Spell and C_Spell.IsSelfBuff and C_Spell.IsSelfBuff(id)
end
