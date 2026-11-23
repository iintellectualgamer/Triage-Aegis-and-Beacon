local _, addon = ...
local Spell = addon.Spell


local slots = addon.healSlots
local clicks = addon.healClicks
local roleLabels = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS", NONE = "Unassigned" }
local rows, keys, trays, clickKeys = {}, {}, {}, {}
local shortcutOwner, changingShortcuts
local shortcutButtons, shortcutLabels, shortcutOverrides = {}, {}, {}
local refreshTrayLabels
local options, syncSpellFields, goToHealthClick, refreshMouseSettings, partySection, partyHint, petSection, raidSection, raidHint
local raidLabels = {}
local pendingBindings = false
local pendingBindingNote = "New bindings take effect after combat."
local pendingBindingMessages = {}
local rowStart = 125
local partyTank, raidSelf, raidTank, pendingPriority
local isSecret = issecretvalue or function() return false end
local healingEvents, cleanseEnabled, cleanseQueued
local cleanseRows = {}
local healthRows, healthQueued = {}, false
local activeClicks = {}
local targetCasts = {}
local targetAction = { type = "target" }
local disabledAction = { disabled = true }
local bindingAttributes = { "type", "spell", "macrotext" }
local criticalHealth = 0.30
local criticalCurve
if UnitHealthPercent and C_CurveUtil and C_CurveUtil.CreateColorCurve
    and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step and CreateColor then
    criticalCurve = C_CurveUtil.CreateColorCurve()
    criticalCurve:SetType(Enum.LuaCurveType.Step)
    criticalCurve:AddPoint(0, CreateColor(1, 1, 1, 0))
    criticalCurve:AddPoint(0.001, CreateColor(1, 1, 1, 1))
    criticalCurve:AddPoint(criticalHealth, CreateColor(1, 1, 1, 0))
end
local raidLabelWidth, raidGap, raidRowHeight = 50, 4, 35
local raidCellWidth = (addon.raidWidth - 2 * addon.inset - raidLabelWidth
    - (addon.raidGroupSize - 1) * raidGap) / addon.raidGroupSize
local partyHintText = "Use Settings to configure spell icons and health-bar clicks."
local primaryButtons = { 1, 3, 2 }
local primaryButtonPositions = {}
for position, button in ipairs(primaryButtons) do primaryButtonPositions[button] = position end
local outlineAnchors = {
    { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
    { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" },
}

local function OrderedUnits(prefix, count, first, second)
    local order = {}
    if first then tinsert(order, first) end
    if second and second ~= first then tinsert(order, second) end
    for index = 1, count do
        local unit = prefix .. index
        if unit ~= first and unit ~= second then tinsert(order, unit) end
    end
    return order
end

local function KeyName(mode, index)
    return "CLICK TriageBeaconKey" .. (mode == "single" and "Single" or "Area") .. index .. ":LeftButton"
end

local function BindingCommand(button)
    return "CLICK " .. button:GetName() .. ":LeftButton"
end

local function BoundHealingKey(command)
    if not GetBindingKey then return end
    local first, second = GetBindingKey(command)
    if not GetBindingAction then return first or second end
    if first and GetBindingAction(first, true) == command then return first end
    if second and GetBindingAction(second, true) == command then return second end
end

local function FreeHealingKey(key)
    local regular, active = GetBindingAction(key), GetBindingAction(key, true)
    local previous = shortcutOverrides[key]
    return (not regular or regular == "") and (not active or active == ""
        or (previous and active == BindingCommand(previous)))
end

local function RefreshHealingShortcuts()
    if not (GetBindingAction and SetOverrideBindingClick and ClearOverrideBindings) or changingShortcuts then return end
    if InCombatLockdown() then pendingBindings = true; return end

    wipe(shortcutLabels)
    local existing, wanted, free = {}, {}, {}
    local loadout = addon.HealingLoadout()
    for _, mode in ipairs(addon.healModes) do
        local spells = addon.ProfileSpells(mode)
        for index, slot in ipairs(slots) do
            local info = addon.SpellInfo(spells[slot.key])
            if info then
                local button = keys[mode][index]
                local key = BoundHealingKey(KeyName(mode, index))
                if key then shortcutLabels[info.spellID] = key end
                existing[info.spellID] = existing[info.spellID] or button
            end
        end
    end

    local emergency = addon.SpellInfo(addon.ProfileSpells("emergency").spell)
    local emergencyKey = emergency and BoundHealingKey(BindingCommand(keys.emergency))
    if #loadout > 0 and addon.db.healingShortcutKeys ~= false then
        if emergency and not emergencyKey then
            for _, key in ipairs({ "ALT-E", "ALT-SHIFT-E", "CTRL-SHIFT-E" }) do
                if FreeHealingKey(key) then emergencyKey = key; break end
            end
        end
        for _, prefix in ipairs({ "ALT-", "ALT-SHIFT-", "CTRL-SHIFT-", "ALT-CTRL-", "ALT-CTRL-SHIFT-" }) do
            for digit = 1, 10 do
                local key = prefix .. (digit % 10)
                if FreeHealingKey(key) then free[#free + 1] = key end
            end
        end
        local nextKey = 1
        if emergency and not emergencyKey and free[nextKey] then
            emergencyKey = free[nextKey]
            nextKey = nextKey + 1
        end
        if emergencyKey and GetBindingAction(emergencyKey) ~= BindingCommand(keys.emergency) then
            wanted[emergencyKey] = keys.emergency
        end
        if emergencyKey then shortcutLabels[emergency.spellID] = emergencyKey end
        for index, entry in ipairs(loadout) do
            local id, key = entry.id, free[nextKey]
            if not shortcutLabels[id] and key then
                local button = existing[id]
                if not button then
                    button = shortcutButtons[index]
                    if not button then
                        button = addon.CreateBindingButton("Heal" .. index, "Healing shortcut " .. index)
                        shortcutButtons[index] = button
                    end
                    addon.ConfigureSpellKey(button, id)
                end
                wanted[key], shortcutLabels[id] = button, key
                nextKey = nextKey + 1
            end
        end
    elseif emergencyKey then
        shortcutLabels[emergency.spellID] = emergencyKey
    end

    local changed = false
    for key, previous in pairs(shortcutOverrides) do
        if wanted[key] ~= previous then changed = true; break end
    end
    for key, button in pairs(wanted) do
        if shortcutOverrides[key] ~= button or GetBindingAction(key, true) ~= BindingCommand(button) then
            changed = true; break
        end
    end
    if changed then
        changingShortcuts = true
        shortcutOwner = shortcutOwner or CreateFrame("Frame")
        ClearOverrideBindings(shortcutOwner)
        for key, button in pairs(wanted) do SetOverrideBindingClick(shortcutOwner, false, key, button:GetName(), "LeftButton") end
        shortcutOverrides = wanted
        changingShortcuts = nil
    end
end

function addon.HealingShortcut(spell)
    local info = addon.SpellInfo(spell)
    return info and shortcutLabels[info.spellID]
end

function addon.AssignedHealingKey(spell, click)
    if not spell or spell == addon.disabledClick then return end
    local key = clickKeys[click]
    return (key and BoundHealingKey(key)) or addon.HealingShortcut(spell)
end

function addon.OpenHealingGesture(key)
    addon.OpenSpellOptions()
    goToHealthClick(key)
end


local function ArrangeRaid()
    if not raidSection then return end
    local groups, occupied, layout, assigned, uncertain = {}, {}, {}, {}, {}
    for group = 1, addon.raidGroupLimit do groups[group] = {} end
    if IsInRaid() then
        addon.ForEachRaidMember(function(unit, index)
            occupied[unit] = true
            local _, _, group = GetRaidRosterInfo(index)
            local members = not isSecret(group) and groups[group]
            if members and #members < addon.raidGroupSize then tinsert(members, { unit = unit, index = index }) end
        end)
    end
    local function Priority(unit)
        if unit == raidSelf then return 1 end
        if unit == raidTank then return 2 end
        return 3
    end
    for group, members in ipairs(groups) do
        table.sort(members, function(a, b)
            local first, second = Priority(a.unit), Priority(b.unit)
            if first ~= second then return first < second end
            return a.index < b.index
        end)
        for column, entry in ipairs(members) do
            layout[(group - 1) * addon.raidGroupSize + column] = entry.unit
            assigned[entry.unit] = true
        end
    end

    -- Keep an anchor for each unit token so late joiners can still appear during combat.
    local free = 1
    local function PlaceUnassigned(unit)
        while layout[free] do free = free + 1 end
        layout[free] = unit
        assigned[unit] = true
        if occupied[unit] then uncertain[math.floor((free - 1) / addon.raidGroupSize) + 1] = true end
    end
    for index = 1, addon.raidMemberLimit do
        local unit = "raid" .. index
        if occupied[unit] and not assigned[unit] then PlaceUnassigned(unit) end
    end
    for index = 1, addon.raidMemberLimit do
        local unit = "raid" .. index
        if not assigned[unit] then PlaceUnassigned(unit) end
    end
    for index, unit in ipairs(layout) do
        local row = rows[unit]
        if row.raidSlot ~= index or row.raidStart ~= rowStart then
            local column = (index - 1) % addon.raidGroupSize
            local line = math.floor((index - 1) / addon.raidGroupSize)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", raidSection, "TOPLEFT",
                addon.inset + raidLabelWidth + column * (raidCellWidth + raidGap), -rowStart - line * raidRowHeight)
            row.raidSlot, row.raidStart = index, rowStart
        end
    end
    for group, label in ipairs(raidLabels) do
        label:SetText(uncertain[group] and ("G" .. group .. " / ?") or ("Group " .. group))
        if label.raidStart ~= rowStart then
            label:ClearAllPoints()
            label:SetPoint("TOPLEFT", raidSection, "TOPLEFT", addon.inset, -rowStart - (group - 1) * raidRowHeight - 8)
            label.raidStart = rowStart
        end
    end
    local bottom = rowStart + addon.raidGroupLimit * raidRowHeight
    local height = bottom + 26 + addon.LegacyResourceHeight()
    if raidSection:GetHeight() ~= height then
        raidHint:ClearAllPoints()
        raidHint:SetPoint("TOPLEFT", raidSection, "TOPLEFT", addon.inset, -bottom - 4)
        raidSection:SetHeight(height)
    end
end

local function ReadPriority()
    local appearance = addon.db.appearance
    local tank, selfUnit
    if IsInRaid() then
        if not (appearance.pinSelf or appearance.pinTank) then return end
        addon.ForEachRaidMember(function(unit)
            local same = UnitIsUnit and UnitIsUnit(unit, "player")
            if appearance.pinSelf and not isSecret(same) and same then
                selfUnit = unit
            elseif appearance.pinTank and not tank and UnitGroupRolesAssigned then
                local role = UnitGroupRolesAssigned(unit)
                if not isSecret(role) and role == "TANK" then tank = unit end
            end
        end)
        return nil, selfUnit, tank
    end
    if appearance.pinTank and IsInGroup() and UnitGroupRolesAssigned then
        local count = GetNumSubgroupMembers and GetNumSubgroupMembers() or 4
        for index = 1, math.min(count, 4) do
            local unit = "party" .. index
            local role = UnitGroupRolesAssigned(unit)
            if not isSecret(role) and role == "TANK" then return unit end
        end
    end
end

function addon.RefreshHealingPriorities()
    if InCombatLockdown() then pendingPriority = true; return end
    pendingPriority = false
    local nextParty, nextSelf, nextTank = ReadPriority()
    if partyTank ~= nextParty then
        partyTank = nextParty
        addon.RefreshPartyAppearance()
    end
    raidSelf, raidTank = nextSelf, nextTank
    ArrangeRaid()
end

-- Share spell attributes across the rows. Each secure button keeps its own unit.
local function InheritClickBindings(frame)
    for _, attribute in ipairs(bindingAttributes) do
        frame:SetAttribute("useparent-" .. attribute, true)
    end
end

local function WriteClick(root, key, action)
    local prefix, button = addon.ParseHealthClick(key)
    for _, attribute in ipairs(bindingAttributes) do
        local name = prefix .. attribute .. button
        local value = action and action[attribute]
        if root:GetAttribute(name) ~= value then root:SetAttribute(name, value) end
    end
end

local function TargetCastMacro(unit, cast)
    local condition = "[@" .. unit .. ",help," .. cast.life .. "]"
    return "/cast " .. condition .. " " .. cast.name .. "\n/target " .. condition
end

local function LivingFriendly(unit)
    local exists = UnitExists(unit)
    if isSecret(exists) or not exists then return false end
    local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
    if isSecret(dead) or dead then return false end
    local connected = UnitIsConnected and UnitIsConnected(unit)
    if isSecret(connected) or connected == false then return false end
    local assist = UnitCanAssist and UnitCanAssist("player", unit)
    return not isSecret(assist) and assist == true
end

local function PrepareEmergencyCast(button)
    if InCombatLockdown() then return end
    local spell = button.spell
    local info = addon.SpellInfo(spell)
    local style = addon.SpellStyle(spell)
    if not info or (info.minRange or 0) > 0 or (info.maxRange or 0) <= 0
        or not addon.CanEmergencyTargetAlly(style) or addon.db.emergencyAutoTarget == false
        or LivingFriendly("mouseover") then
        addon.ConfigureSpellKey(button, spell, true)
        return
    end

    local lowest, chosen = 1, nil
    local function Consider(unit)
        if not LivingFriendly(unit) then return end
        local amount, maximum = UnitHealth(unit), UnitHealthMax(unit)
        if isSecret(amount) or isSecret(maximum) or type(amount) ~= "number" or type(maximum) ~= "number"
            or amount <= 0 or maximum <= 0 then return end
        local fraction = amount / maximum
        if fraction >= lowest then return end
        local self = unit == "player" or (UnitIsUnit and UnitIsUnit("player", unit))
        if isSecret(self) then return end
        if self then
            if style == "ally" then return end
        else
            local inRange = Spell.IsSpellInRange(info.spellID, unit)
            if isSecret(inRange) or inRange ~= true then return end
        end
        lowest, chosen = fraction, unit
    end

    if IsInRaid() or (LE_PARTY_CATEGORY_INSTANCE and IsInRaid(LE_PARTY_CATEGORY_INSTANCE)) then
        addon.ForEachRaidMember(Consider)
    else
        Consider("player")
        if IsInGroup() then
            for index = 1, 4 do Consider("party" .. index) end
        end
    end
    -- WoW ignores this unit condition in combat, including across lockdown transitions.
    addon.ConfigureSpellKey(button, spell, true, chosen)
end

local function ReadTargetCast(spell, style)
    if style ~= "friendly" and style ~= "ally" and style ~= "freedom" and style ~= "resurrect" and style ~= "dual" then return end
    local info = addon.SpellInfo(spell)
    if not info or (info.maxRange or 0) <= 0 then return end
    if style ~= "resurrect" and style ~= "dual" and not Spell.IsSpellHelpful(info.spellID) then return end
    local name = addon.SpellText(spell)
    if not name or name:find("[%c;%[%]]") then return end
    if type(spell) == "number" and name == info.name then
        local named, learned = Spell.GetSpellInfo(name), addon.SpellInfo(name)
        local exact = addon.ActiveSpellID(info.spellID)
        if not named or not learned or addon.ActiveSpellID(named.spellID) ~= exact
            or addon.ActiveSpellID(learned.spellID) ~= exact then return end
    end
    local cast = { name = name, life = style == "resurrect" and "dead" or "nodead" }
    if #TargetCastMacro("raid40", cast) <= 255 then return cast end
end

local function ApplyTargetCasts(wanted)
    -- Unit tokens stay fixed. Rebuild their macros only when an assignment changes.
    for attribute in pairs(targetCasts) do
        if not wanted[attribute] then
            for _, row in pairs(rows) do row:SetAttribute(attribute, nil) end
        end
    end
    for attribute, cast in pairs(wanted) do
        local previous = targetCasts[attribute]
        if not previous or cast.name ~= previous.name or cast.life ~= previous.life then
            for unit, row in pairs(rows) do row:SetAttribute(attribute, TargetCastMacro(unit, cast)) end
        end
    end
    targetCasts = wanted
end

local function BindHealthClicks()
    local actions = {}
    local spellActions, wanted = { [addon.targetClick] = targetAction, [addon.disabledClick] = disabledAction }, {}
    for key, spell in pairs(addon.HealthClickActions()) do
        if not spellActions[spell] then
            local castSpell = addon.HealthBarSpell(spell)
            local style = addon.SpellStyle(castSpell)
            local useMacro = style == "enemy" or style == "self" or style == "standalone" or style == "pet"
            local macro = useMacro and addon.SpellMacro(castSpell) or nil
            local targetCast = addon.db.targetOnHeal == true and ReadTargetCast(castSpell, style)
            spellActions[spell] = {
                type = (macro or targetCast) and "macro" or "spell", spell = castSpell, macrotext = macro,
                targetCast = targetCast,
            }
        end
        local action = spellActions[spell]
        actions[key] = action
        if action.targetCast then
            local prefix, button = addon.ParseHealthClick(key)
            wanted[prefix .. "macrotext" .. button] = action.targetCast
        end
    end
    ApplyTargetCasts(wanted)
    local root = addon.panel.body
    for key in pairs(activeClicks) do
        if not actions[key] then WriteClick(root, key) end
    end
    for key, action in pairs(actions) do WriteClick(root, key, action) end
    activeClicks = actions
end

local tileHeight, tileGap, trayGutter = 41, 5, 73

local function ShortGesture(key)
    local prefix, button = addon.ParseHealthClick(key)
    if not prefix then return end
    return (addon.HealthClickLabel(prefix, button):gsub("%-click$", prefix == "" and "-click" or ""))
end

local function UpdateTileDetails(button)
    local key = addon.AssignedHealingKey(button.spell, button.click)
    local shortKey = key and key:gsub("ALT%-", "A-"):gsub("CTRL%-", "C-"):gsub("SHIFT%-", "S-")
    local id = button.spellID
    if not button.emergency then
        button.hint:SetText(ShortGesture(button.click) or (key and "Keyboard" or "Tile only"))
    end
    if id and shortKey then
        button.detail:SetText(id .. " / " .. shortKey)
    else
        button.detail:SetText(id and ("ID " .. id) or shortKey or "")
    end
end

refreshTrayLabels = function()
    for _, tray in ipairs(trays) do
        for _, group in ipairs(tray.groups) do
            for _, button in ipairs(group.buttons) do
                if button:IsShown() then UpdateTileDetails(button) end
            end
        end
    end
end

local function SetTileAction(button, spell, click, visible)
    local info = addon.SpellInfo(spell)
    local targeting = spell == addon.targetClick
    button.spell, button.spellID, button.click = spell, info and info.spellID, click
    addon.ConfigureSpellKey(button, info and spell or nil, button.emergency)
    if not button.emergency then
        local cast = info and "macro" or nil
        button:SetAttribute("*type2", cast)
        button:SetAttribute("*type3", cast)
    end
    local show = (targeting or info ~= nil) and visible
    button:SetShown(show)
    if button.emergency then addon.RefreshEmergencyTiming(button) end
    if show then
        button.text:SetText(targeting and "Target (/target)" or addon.SpellText(spell) or info.name)
        button.icon:SetTexture(targeting and addon.targetIcon or info.iconID)
        UpdateTileDetails(button)
    end
    return show
end

local function PlaceTiles(tray, tiles, offset)
    for first = 1, #tiles, 3 do
        local count = math.min(3, #tiles - first + 1)
        local width = (tray.width - trayGutter - (count - 1) * tileGap) / count
        for column = 1, count do
            local button = tiles[first + column - 1]
            local left = addon.inset + trayGutter + (column - 1) * (width + tileGap)
            if button.left ~= left or button.offset ~= offset then
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", tray.panel, "TOPLEFT", left, -offset)
                button.left, button.offset = left, offset
            end
            if button.tileWidth ~= width then
                button:SetWidth(width)
                for _, label in ipairs(button.lines) do label:SetWidth(width - 30) end
                button.tileWidth = width
            end
        end
        offset = offset + tileHeight + tileGap
    end
    return offset
end

local function UpdateSpellTray(tray, actions, gestures)
    local hidden, extras = addon.ProfileSpells("icons"), addon.ProfileSpells("extra")
    local offset = 37
    for _, group in ipairs(tray.groups) do
        local visible = {}
        for _, button in ipairs(group.buttons) do
            local click, spell = button.gesture
            if click then
                spell = actions[click]
            else
                spell = extras[button.iconKey]
                local info = addon.SpellInfo(spell)
                click = info and gestures[info.spellID]
            end
            if SetTileAction(button, spell, click, button.emergency or not addon.SpellIconHidden(hidden, button.iconKey)) then
                visible[#visible + 1] = button
            end
        end
        group.heading:SetShown(#visible > 0)
        if #visible > 0 then
            group.heading:ClearAllPoints()
            group.heading:SetPoint("TOPLEFT", tray.panel, "TOPLEFT", addon.inset, -offset - 12)
            offset = PlaceTiles(tray, visible, offset)
        end
    end
    return offset + 11
end

local function RefreshHoveredClickTooltip()
    local owner = GameTooltip.GetOwner and GameTooltip:GetOwner()
    if owner and owner.ShowClickTooltip and GameTooltip:IsShown() then owner:ShowClickTooltip() end
end

local function ApplyBindings()
    if InCombatLockdown() then
        pendingBindings = true
        return false
    end
    pendingBindings = false
    BindHealthClicks()
    for _, mode in ipairs(addon.healModes) do
        local spells = addon.ProfileSpells(mode)
        for index, slot in ipairs(slots) do
            addon.ConfigureSpellKey(keys[mode][index], spells[slot.key])
        end
    end
    keys.emergency.spell = addon.ProfileSpells("emergency").spell
    addon.ConfigureSpellKey(keys.emergency, keys.emergency.spell, true)
    RefreshHealingShortcuts()
    local actions, gestures = addon.HealthClickActions(), {}
    for _, entry in ipairs(addon.HealthClickEntries(actions)) do
        local info = addon.SpellInfo(entry.spell)
        if info and not gestures[info.spellID] then gestures[info.spellID] = entry.click end
    end
    local needed = rowStart
    for _, tray in ipairs(trays) do needed = UpdateSpellTray(tray, actions, gestures) end
    if rowStart ~= needed then
        rowStart = needed
        addon.RefreshPartyAppearance()
        ArrangeRaid()
        if addon.panel.activeLayout then addon.ResizePanel() end
    end
    if addon.RefreshPracticeBindings then addon.RefreshPracticeBindings() end
    if addon.RefreshHealingLoadout then addon.RefreshHealingLoadout() end
    RefreshHoveredClickTooltip()
    if next(pendingBindingMessages) then
        local message = "Saved spell settings are active."
        for status, queuedMessage in pairs(pendingBindingMessages) do
            if status:GetText() == queuedMessage then status:SetText(message) end
        end
        wipe(pendingBindingMessages)
        addon.Print(message)
    end
    return true
end

function addon.SaveSpellSets(changes)
    addon.SetProfileOverrides(changes)
    local applied = ApplyBindings()
    if applied and addon.UpdateRangeReference then addon.UpdateRangeReference() end
    return applied
end

function addon.RefreshHealingAutomation()
    local applied = addon.SaveSpellSets({})
    if applied and syncSpellFields and options:IsVisible() then syncSpellFields({}) end
    if applied and refreshMouseSettings then refreshMouseSettings() end
    if applied and addon.RefreshSpellIconSettings then addon.RefreshSpellIconSettings() end
    return applied
end

function addon.ReadSpell(input)
    local name = input:match("^%s*(.-)%s*$")
    if name == "" then
        return nil
    end

    local identifier = name
    local idText = name:match("^(%d+)$") or name:match("^.+%s+%((%d+)%)$")
    if idText then
        identifier = tonumber(idText)
        if not addon.ValidSpellIdentifier(identifier) then
            return nil, "Enter a valid spell ID."
        end
    end

    local info = addon.SpellInfo(identifier)
    if not info then
        return nil, "Enter a spell name from your spellbook or a valid spell ID."
    end
    if Spell.IsSpellPassive(info.spellID) then
        return nil, "Choose a spell you can cast."
    end
    if not addon.CanAssignSpell(info) then
        return nil, "Choose a spell available in your current build."
    end

    if type(identifier) == "number" then
        return identifier
    end
    return info.name
end

function addon.ReadClickAction(input)
    local choice = input:match("^%s*(.-)%s*$"):lower()
    if choice == "target" or choice == "/target" then return addon.targetClick end
    if choice == "none" or choice == "no action" then return addon.disabledClick end
    return addon.ReadSpell(input)
end



local function FieldText(spell)
    return addon.SpellDisplay(spell) or ""
end

function addon.ConfirmBindingSave(status, message, applied)
    if applied == false then
        message = message .. " " .. pendingBindingNote
        pendingBindingMessages[status] = message
    elseif applied == nil then
        message = pendingBindingMessages[status] or message
    end
    addon.ConfirmSettingsSave(status, message)
end

local function ShowSaveResult(applied, message)
    options.errorText:SetTextColor(unpack(addon.color.accent))
    addon.ConfirmBindingSave(options.errorText, message, applied)
end

local function CursorSpell()
    if not GetCursorInfo then return end
    local kind, index, bank, spellID, baseID = GetCursorInfo()
    if kind == "spell" then
        spellID = spellID or addon.SpellAtCursorSlot(index, bank)
        if spellID and baseID and addon.ActiveSpellID(baseID) == spellID then spellID = baseID end
        return true, spellID
    elseif kind == "action" and GetActionInfo and type(index) == "number" and index > 0 then
        local actionType, id = GetActionInfo(index)
        return true, actionType == "spell" and id or nil
    elseif kind == "petaction" then
        return true, bank == "spell" and spellID or nil
    end
end

local function AddSpellField(page, y, save, acceptsClickActions)
    local picker = addon.Button(page, "Pick", 48, 23)
    picker:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, y)
    local edit = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    edit:SetSize(271, 23)
    edit:SetPoint("RIGHT", picker, "LEFT", -7, 0)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(100)
    edit:SetScript("OnEnterPressed", save)
    edit:SetScript("OnEscapePressed", addon.CloseSettings)
    local function Browse()
        addon.OpenAbilityPicker(page, function(id)
            if not addon.ReadSpell(tostring(id)) then return false end
            edit:SetText(FieldText(id))
            return true
        end)
    end
    local function Drop()
        local handled, spell = CursorSpell()
        if not handled then return false end
        if spell and addon.ReadSpell(tostring(spell)) then
            edit:SetText(FieldText(spell))
            edit:ClearFocus()
            page.errorText:SetText("Spell copied. Return or cancel the dragged icon, then save.")
        else
            page.errorText:SetText("Choose a spell your character can cast.")
        end
        return true
    end
    edit:SetScript("OnReceiveDrag", Drop)
    edit:HookScript("OnMouseUp", function(_, button) if button == "LeftButton" then Drop() end end)
    picker:SetScript("OnReceiveDrag", Drop)
    picker:SetScript("OnClick", function(owner)
        if Drop() then return end
        if not (MenuUtil and MenuUtil.CreateContextMenu) then Browse(); return end
        MenuUtil.CreateContextMenu(owner, function(_, root)
            root:CreateTitle(acceptsClickActions and "Click actions and spells" or "Learned spells")
            root:SetScrollMode(265)
            root:CreateButton("Browse spells and talents", Browse)
            if acceptsClickActions then
                root:CreateButton("Target player", function() edit:SetText(addon.targetClick); edit:ClearFocus() end)
                root:CreateButton("No action", function() edit:SetText(addon.disabledClick); edit:ClearFocus() end)
            end
            for _, name in ipairs(addon.LearnedSpellNames()) do
                root:CreateButton(FieldText(name), function() edit:SetText(FieldText(name)); edit:ClearFocus() end)
            end
        end)
    end)
    addon.Tooltip(picker, acceptsClickActions and "Choose a click action" or "Choose a spell",
        "Pick a learned spell, or drop a spell from your spellbook or action bar here or on the field.")
    return edit, picker
end

local function BuildSavedClickList(page, openClick)
    local list = CreateFrame("Frame", nil, page, "BackdropTemplate")
    list:SetPoint("TOPLEFT", page, "TOPLEFT", -8, 9)
    list:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 8, -3)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:EnableMouse(true)
    addon.StylePanel(list)
    addon.Label(list, "Saved clicks", "GameFontHighlightLarge", 14, -12, addon.color.accent)
    addon.Label(list, "Choose a row to edit that click in your current profile.", nil, 14, -40, addon.color.dim)
    addon.Label(list, "Click", nil, 20, -66, addon.color.accent)
    addon.Label(list, "Saved assignment", nil, 182, -66, addon.color.accent)
    addon.Label(list, "Status", nil, 358, -66, addon.color.accent)
    local close = addon.Button(list, "Close", 55, 22)
    close:SetPoint("TOPRIGHT", list, "TOPRIGHT", -13, -9)
    close:SetScript("OnClick", function() list:Hide() end)
    local rows, entries, first = {}, {}, 1
    for index = 1, 10 do
        local row = addon.Button(list, nil, 432, 23)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 13, -83 - (index - 1) * 25)
        row.gesture = addon.Label(row, "", nil, 7, -6)
        row.assignment = addon.Label(row, "", nil, 169, -6)
        row.state = addon.Label(row, "", nil, 345, -6, addon.color.dim)
        row.gesture:SetWidth(156)
        row.gesture:SetJustifyH("LEFT")
        row.gesture:SetWordWrap(false)
        row.assignment:SetWidth(168)
        row.assignment:SetJustifyH("LEFT")
        row.assignment:SetWordWrap(false)
        row:SetScript("OnClick", function(self)
            if not self.entry then return end
            list:Hide()
            openClick(self.entry.key)
        end)
        addon.Tooltip(row, "Saved assignment", function()
            return row.entry and (row.entry.gesture .. "\n" .. row.entry.assignment) or ""
        end)
        rows[index] = row
    end
    local prev = addon.Button(list, "Previous", 80, 22)
    prev:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 13, 9)
    local following = addon.Button(list, "Next", 80, 22)
    following:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -13, 9)
    local count = addon.Label(list, "", nil, 0, 0, addon.color.dim)
    count:ClearAllPoints()
    count:SetPoint("BOTTOM", list, "BOTTOM", 0, 15)
    local function Draw()
        for index, row in ipairs(rows) do
            local entry = entries[first + index - 1]
            row.entry = entry
            row:SetShown(entry ~= nil)
            if entry then
                row.gesture:SetText(entry.gesture)
                row.assignment:SetText(entry.assignment)
                row.state:SetText(entry.state)
            end
        end
        local last = math.min(first + #rows - 1, #entries)
        count:SetText(last == 0 and "No click assignments saved yet." or ("%d–%d of %d"):format(first, last, #entries))
        prev:SetEnabled(first > 1)
        following:SetEnabled(last < #entries)
    end
    prev:SetScript("OnClick", function() first = first - #rows; Draw() end)
    following:SetScript("OnClick", function() first = first + #rows; Draw() end)
    list.Refresh = function(reset)
        wipe(entries)
        local active = addon.HealthClickSpells()
        for key, spell in pairs(addon.SavedHealthClicks()) do
            local prefix, button = addon.ParseHealthClick(key)
            local assignment = addon.SpellDisplay(spell)
            local state = spell == addon.disabledClick and "Disabled" or "Active"
            if active[key] ~= spell then state = pendingBindings and "After combat" or "Unavailable" end
            entries[#entries + 1] = {
                key = key, position = primaryButtonPositions[button] or button,
                gesture = addon.HealthClickLabel(prefix, button), assignment = assignment, state = state,
            }
        end
        table.sort(entries, function(a, b)
            if a.position == b.position then return a.key < b.key end
            return a.position < b.position
        end)
        if reset or first > #entries then first = 1 end
        Draw()
    end
    list:SetScript("OnHide", function() GameTooltip:Hide() end)
    list:Hide()
    return list
end

function addon.BuildSpellSettings(frame)
    options = frame
    local fields, draft = {}, {}
    local modifiers = {
        { label = "Alt", key = "alt-" }, { label = "Ctrl", key = "ctrl-" }, { label = "Shift", key = "shift-" },
    }
    local pageSize, first = 5, 1
    addon.Label(frame, "Custom spells", "GameFontHighlightLarge", 0, 0, addon.color.accent)
    addon.Label(frame, "Enter a spell name, ID, /target, or None. You can also drag a spell here.", nil, 0, -28, addon.color.dim)
    addon.Label(frame, "Modifiers", nil, 0, -59, addon.color.dim)
    local previous = addon.Button(frame, "<", 27, 24)
    previous:SetPoint("TOPLEFT", frame, "TOPLEFT", 249, -52)
    addon.Tooltip(previous, "Previous mouse buttons", "Show the previous group of mouse buttons.")
    local range = addon.Label(frame, "", "GameFontHighlight", 282, -58)
    range:SetWidth(128)
    range:SetJustifyH("CENTER")
    local following = addon.Button(frame, ">", 27, 24)
    following:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -52)
    addon.Tooltip(following, "More mouse buttons", "Show the next group of mouse buttons, through Button 31.")

    local function RememberFields()
        for _, row in ipairs(fields) do
            if row.key then
                local text = row.edit:GetText()
                draft[row.key] = text ~= row.saved and text or nil
            end
            row.edit:ClearFocus()
        end
    end

    local function DrawFields()
        local prefix = ""
        local active = addon.HealthClickSpells()
        local inactive = false
        for _, modifier in ipairs(modifiers) do
            addon.SelectTab(modifier.tab, modifier.active == true)
            if modifier.active then prefix = prefix .. modifier.key end
        end
        local last = math.min(first + pageSize - 1, addon.mouseButtonCount)
        range:SetText(first == last and ("Button " .. first) or ("Buttons " .. first .. "-" .. last))
        previous:SetEnabled(first > 1)
        following:SetEnabled(last < addon.mouseButtonCount)
        for index, row in ipairs(fields) do
            local position = first + index - 1
            local number = primaryButtons[position] or position
            local shown = position <= last
            row.key = shown and (prefix .. number) or nil
            row.label:SetShown(shown)
            row.edit:SetShown(shown)
            row.pick:SetShown(shown)
            if shown then
                row.saved = FieldText(addon.HealthClickInput(row.key))
                inactive = inactive or (row.saved ~= "" and not active[row.key])
                row.label:SetText(addon.HealthClickLabel("", number))
                row.edit:SetText(draft[row.key] or row.saved)
            end
        end
        frame.bindingHint:SetText(inactive and "Some saved spells are unavailable in this build. Check Pick > Browse spells and talents."
            or "Blank Left-click and Alt + middle-click select. Use None to disable.")
    end

    local function GoToClick(key)
        local prefix, button = addon.ParseHealthClick(key)
        local position = primaryButtonPositions[button] or button
        first = math.floor((position - 1) / pageSize) * pageSize + 1
        for _, modifier in ipairs(modifiers) do
            modifier.active = prefix:find(modifier.key, 1, true) ~= nil
        end
        DrawFields()
        return fields[position - first + 1].edit
    end
    goToHealthClick = function(key)
        RememberFields()
        GoToClick(key):SetFocus()
    end

    local savedList
    local savedButton = addon.Button(frame, "Saved clicks", 100, 23)
    savedButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 1)
    savedButton:SetScript("OnClick", function()
        RememberFields()
        if not savedList then savedList = BuildSavedClickList(frame, function(key) GoToClick(key):SetFocus() end) end
        savedList.Refresh(true)
        savedList:Show()
    end)

    local function Save()
        RememberFields()
        local edits = {}
        for key, text in pairs(draft) do
            local spell, reason = addon.ReadClickAction(text)
            if reason then
                local prefix, button = addon.ParseHealthClick(key)
                local field = GoToClick(key)
                frame.errorText:SetTextColor(1, 0.56, 0.54, 1)
                frame.errorText:SetText(addon.HealthClickLabel(prefix, button) .. ". " .. reason)
                field:SetFocus()
                return
            end
            edits[key] = spell or false
        end
        if next(edits) then
            local applied = addon.SaveSpellSets(addon.HealthClickChanges(edits))
            wipe(draft)
            DrawFields()
            if refreshMouseSettings then refreshMouseSettings() end
            ShowSaveResult(applied, "Assigned spells saved.")
        else
            ShowSaveResult(nil, pendingBindings and pendingBindingNote or "Assigned spells are up to date.")
        end
    end

    for index, modifier in ipairs(modifiers) do
        local tab = addon.Tab(frame, modifier.label, 46, 24)
        tab:SetPoint("TOPLEFT", frame, "TOPLEFT", 71 + (index - 1) * 51, -52)
        tab:SetScript("OnClick", function()
            RememberFields()
            modifier.active = not modifier.active
            DrawFields()
        end)
        modifier.tab = tab
    end
    previous:SetScript("OnClick", function()
        RememberFields()
        if first > 1 then first = first - pageSize end
        DrawFields()
    end)
    following:SetScript("OnClick", function()
        RememberFields()
        if first + pageSize <= addon.mouseButtonCount then first = first + pageSize end
        DrawFields()
    end)
    for index = 1, pageSize do
        local y = -95 - (index - 1) * 35
        local label = addon.Label(frame, "", nil, 0, y - 6, addon.color.accent)
        local edit, pick = AddSpellField(frame, y, Save, true)
        fields[index] = { label = label, edit = edit, pick = pick }
    end

    frame.bindingHint = addon.Label(frame, "", nil, 0, -272, addon.color.dim)
    frame.bindingHint:SetWidth(444)
    frame.bindingHint:SetJustifyH("LEFT")
    frame.bindingHint:SetWordWrap(true)
    frame.errorText = addon.Label(frame, "", nil, 0, -299, addon.color.accent)
    frame.errorText:SetWidth(444)
    frame.errorText:SetJustifyH("LEFT")
    frame.errorText:SetWordWrap(true)
    for index, mode in ipairs(addon.healModes) do
        local auto = addon.Button(frame, index == 1 and "Auto-fill single" or "Auto-fill area", 106, 27)
        auto:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", (index - 1) * 112, 0)
        local group = clicks[mode]
        addon.Tooltip(auto, addon.healModeLabels[mode],
            "Restore suggested spells for " .. group[1].label .. ", " .. group[2].label .. ", and " .. group[3].label .. ".")
        auto:SetScript("OnClick", function()
            RememberFields()
            for _, click in ipairs(clicks[mode]) do draft[click.prefix .. click.suffix] = nil end
            local suggested = addon.db.healingClickDefaults == false and addon.HealingClickSuggestions(mode)
            local applied = addon.SaveSpellSets({ [mode] = suggested or false })
            DrawFields()
            if refreshMouseSettings then refreshMouseSettings() end
            ShowSaveResult(applied, addon.healModeLabels[mode] .. " auto-filled from the spellbook.")
        end)
    end
    local save = addon.Button(frame, "Save spells", 98, 27)
    save:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
    save:SetScript("OnClick", Save)
    frame:SetScript("OnHide", function()
        RememberFields()
        if savedList then savedList:Hide() end
    end)
    syncSpellFields = function(changed)
        RememberFields()
        for key in pairs(changed) do draft[key] = nil end
        DrawFields()
        if savedList and savedList:IsVisible() then savedList.Refresh() end
    end
    return function()
        wipe(draft)
        first = 1
        for _, modifier in ipairs(modifiers) do modifier.active = false end
        DrawFields()
        options.errorText:SetText(pendingBindingMessages[options.errorText] or (pendingBindings and pendingBindingNote or ""))
    end
end

function addon.BuildMouseSettings(page)
    page.fields = {}
    addon.Label(page, "Mouse buttons", "GameFontHighlightLarge", 0, 0, addon.color.accent)
    addon.Label(page, "Choose a spell, /target, or None for a health-bar click.", nil, 0, -27, addon.color.dim)
    local order = { "left", "middle", "right", "emergency" }
    local clickKeys = { left = "1", right = "2", middle = "3", emergency = "alt-2" }
    local labels = { left = "Left-click", right = "Right-click", middle = "Middle-click", emergency = "Alt + right-click" }
    local function Refresh()
        for _, key in ipairs(order) do
            page.fields[key]:SetText(FieldText(addon.HealthClickInput(clickKeys[key])))
        end
        page.targetOnHeal:SetChecked(addon.db.targetOnHeal == true)
        page.errorText:SetText("")
    end
    local function Save()
        local edits = {}
        for _, key in ipairs(order) do
            local field = page.fields[key]
            local input, clickKey = field:GetText(), clickKeys[key]
            if input ~= FieldText(addon.HealthClickInput(clickKey)) then
                local spell, reason = addon.ReadClickAction(input)
                if reason then
                    page.errorText:SetText(labels[key] .. ". " .. reason)
                    field:SetFocus()
                    return
                end
                edits[clickKey] = spell or false
            end
        end
        for _, field in pairs(page.fields) do field:ClearFocus() end
        local applied = next(edits) and addon.SaveSpellSets(addon.HealthClickChanges(edits))
        if syncSpellFields then syncSpellFields(edits) end
        Refresh()
        local message = applied == nil and "Mouse bindings are up to date." or "Mouse bindings saved."
        addon.ConfirmBindingSave(page.errorText, message, applied)
    end

    for index, key in ipairs(order) do
        local y = -60 - (index - 1) * 36
        addon.Label(page, labels[key], nil, 0, y - 6, addon.color.accent)
        page.fields[key] = AddSpellField(page, y, Save, true)
    end
    local targetOnHeal = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    targetOnHeal:SetSize(22, 22)
    targetOnHeal:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -197)
    page.targetOnHeal = targetOnHeal
    addon.Label(page, "Target player on healing clicks", nil, 27, -202)
    addon.Tooltip(targetOnHeal, "Target player on healing clicks",
        "Keep the clicked unit selected after attempting a supported friendly cast. Changes in combat apply when combat ends.")
    targetOnHeal:SetScript("OnClick", function(self)
        local enabled = self:GetChecked() == true
        addon.db.targetOnHeal = enabled
        local applied = addon.SaveSpellSets({})
        local message = "Mouse targeting saved."
        if applied then
            message = message .. (enabled and " Healing clicks select the player you heal."
                or " Healing clicks keep your current target.")
        end
        addon.ConfirmBindingSave(page.errorText, message, applied)
    end)
    addon.Label(page, "Use None to turn off the default Left-click selection.", nil, 0, -226, addon.color.dim)
    local all = addon.Button(page, "All click combinations", 144, 22)
    all:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -247)
    all:SetScript("OnClick", addon.OpenSpellOptions)
    page.errorText = addon.Label(page, "", nil, 0, -280, addon.color.accent)
    page.errorText:SetWidth(444)
    page.errorText:SetWordWrap(true)
    page.errorText:SetJustifyH("LEFT")
    local defaults = addon.Button(page, "Restore mouse defaults", 158, 27)
    defaults:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT")
    defaults:SetScript("OnClick", function()
        addon.db.targetOnHeal = true
        local applied = addon.SaveSpellSets({ mouse = false, emergency = false })
        Refresh()
        if syncSpellFields then syncSpellFields({ ["1"] = true, ["3"] = true, ["alt-2"] = true }) end
        addon.ConfirmBindingSave(page.errorText, "Mouse defaults saved.", applied)
    end)
    local save = addon.Button(page, "Save mouse buttons", 145, 27)
    save:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT")
    save:SetScript("OnClick", Save)
    page:SetScript("OnHide", function()
        for _, field in pairs(page.fields) do field:ClearFocus() end
    end)
    refreshMouseSettings = Refresh
    return Refresh
end

function addon.BuildSpellIconSettings(page)
    page.fields, page.boxes = {}, {}
    addon.Label(page, "Spell icons", "GameFontHighlightLarge", 0, 0, addon.color.accent)
    addon.Label(page, "Show health-bar and extra tiles in Party, Raid, and Combined.", nil, 0, -28, addon.color.dim)
    local countButton = addon.Button(page, "", 115, 23)
    countButton:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -53)
    local function ShowCount()
        local count = 0
        for _, box in pairs(page.boxes) do
            if box:GetChecked() then count = count + 1 end
        end
        countButton.label:SetText(("%d of %d selected"):format(count, #addon.iconKeys))
        return count
    end
    local function SelectCount(count)
        for index, key in ipairs(addon.iconKeys) do page.boxes[key]:SetChecked(index <= count) end
        ShowCount()
    end
    countButton:SetScript("OnClick", function(owner)
        if not (MenuUtil and MenuUtil.CreateContextMenu) then
            SelectCount((ShowCount() + 1) % (#addon.iconKeys + 1))
            return
        end
        MenuUtil.CreateContextMenu(owner, function(_, root)
            root:CreateTitle("Show the first slots")
            root:CreateButton("0 - Hide all", function() SelectCount(0) end)
            for count = 1, #addon.iconKeys do
                root:CreateButton(tostring(count), function() SelectCount(count) end)
            end
        end)
    end)
    addon.Label(page, "Use the checkboxes to show or hide individual icons.", nil, 128, -59, addon.color.dim)
    local position = 0
    for _, group in ipairs(addon.spellIconGroups) do
        for index, icon in ipairs(group.icons) do
            local x, y = math.floor(position / 5) * 218, -85 - (position % 5) * 21
            local box = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
            box:SetSize(21, 21)
            box:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
            box:SetScript("OnClick", ShowCount)
            page.boxes[icon.key] = box
            local prefix, button = addon.ParseHealthClick(icon.click)
            addon.Label(page, prefix and addon.HealthClickLabel(prefix, button) or ("Extra spell " .. index), nil, x + 27, y - 6)
            position = position + 1
        end
    end
    addon.Label(page, "Use Assign spells to change what each health-bar click does.", nil, 0, -194, addon.color.dim)

    local displayedExtra = {}
    local function FillExtra(preserveDraft)
        local spells = addon.ProfileInputs("extra")
        for _, key in ipairs(addon.extraKeys) do
            local field, value = page.fields[key], FieldText(spells[key])
            if not preserveDraft or field:GetText() == displayedExtra[key] then field:SetText(value) end
            displayedExtra[key] = value
        end
    end
    local function Save()
        local old = addon.ProfileInputs("extra")
        local extra, hidden, changed = {}, {}, false
        for index, key in ipairs(addon.extraKeys) do
            local field = page.fields[key]
            local input = field:GetText()
            if input == FieldText(old[key]) then
                extra[key] = old[key]
            else
                local spell, reason = addon.ReadSpell(input)
                if reason then
                    page.errorText:SetText("Extra spell " .. index .. ". " .. reason)
                    field:SetFocus()
                    return
                end
                extra[key], changed = spell, changed or spell ~= old[key]
            end
            field:ClearFocus()
        end
        for _, key in ipairs(addon.iconKeys) do
            hidden[key] = not page.boxes[key]:GetChecked()
        end
        local changes = { icons = hidden }
        if changed then changes.extra = extra end
        local applied = addon.SaveSpellSets(changes)
        FillExtra()
        addon.ConfirmBindingSave(page.errorText, "Spell icons saved.", applied)
    end
    for index, key in ipairs(addon.extraKeys) do
        local y = -218 - (index - 1) * 30
        addon.Label(page, "Extra spell " .. index, nil, 0, y - 6, addon.color.accent)
        page.fields[key] = AddSpellField(page, y, Save)
    end
    page.errorText = addon.Label(page, "", nil, 0, -290, addon.color.accent)
    page.errorText:SetWidth(444)
    page.errorText:SetWordWrap(true)
    page.errorText:SetJustifyH("LEFT")
    local restore = addon.Button(page, "Restore suggested extras", 158, 27)
    restore:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT")
    restore:SetScript("OnClick", function()
        local applied = addon.SaveSpellSets({ extra = false })
        FillExtra()
        addon.ConfirmBindingSave(page.errorText, "Suggested spell icons saved.", applied)
    end)
    local save = addon.Button(page, "Save spell icons", 130, 27)
    save:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT")
    save:SetScript("OnClick", Save)
    page:SetScript("OnHide", function()
        for _, field in pairs(page.fields) do field:ClearFocus() end
    end)
    addon.RefreshSpellIconSettings = function(preserveDraft)
        if preserveDraft and page:IsVisible() then FillExtra(true); return end
        local hidden = addon.ProfileInputs("icons")
        for key, box in pairs(page.boxes) do box:SetChecked(not addon.SpellIconHidden(hidden, key)) end
        ShowCount()
        FillExtra()
        page.errorText:SetText("")
    end
    return addon.RefreshSpellIconSettings
end

local function ClickActionText(action, showID)
    if not action then return end
    if action.type == "target" then return showID and "Select player (/target)" or "Select player" end
    if action.disabled then return "No action" end
    local name = showID and addon.SpellDisplay(action.spell) or addon.SpellText(action.spell)
    return name and action.targetCast and (name .. " + target") or name
end

function addon.BuildPracticeSettings(page)
    addon.Label(page, "Practice healing clicks", "GameFontHighlightLarge", 0, 0, addon.color.accent)
    addon.Label(page, "Click the practice bar with any mouse button and modifiers.", nil, 0, -29, addon.color.dim)
    local practice = addon.Button(page, "Practice target", 424, 48)
    practice:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -53)
    practice:RegisterForClicks("AnyUp")
    local sample = addon.AddPracticeVitals(practice)
    local nextSample = addon.Button(page, "Sample cues", 104, 24)
    nextSample:SetPoint("TOPRIGHT", page, "TOPRIGHT", -18, 0)
    nextSample:SetScript("OnClick", function() sample(true) end)
    addon.Tooltip(nextSample, "Sample cues", "Cycle through example shields, healing absorbs, incoming heals, and critical health.")
    local gesture = addon.Label(page, "", nil, 0, -112, addon.color.dim)
    local result = addon.Label(page, "", "GameFontHighlight", 0, -129, addon.color.accent)
    result:SetWidth(424)
    result:SetJustifyH("LEFT")
    result:SetWordWrap(false)
    local lastPrefix, lastButton
    local captions, shown = {
        { "", "1", "Left-click" }, { "", "3", "Middle-click" }, { "", "2", "Right-click" },
        { "shift-", "1", "Shift + left-click" }, { "ctrl-", "1", "Ctrl + left-click" },
        { "shift-", "2", "Shift + right-click" }, { "alt-", "1", "Alt + left-click" },
        { "ctrl-", "2", "Ctrl + right-click" }, { "alt-", "2", "Alt + right-click" },
        { "alt-", "3", "Alt + middle-click" },
    }, {}
    local function Action(prefix, suffix)
        return ClickActionText(activeClicks[prefix .. suffix], true) or "Unassigned"
    end
    local function Refresh()
        for index, choice in ipairs(captions) do
            shown[index]:SetText(Action(choice[1], choice[2]))
        end
        if lastButton then result:SetText("Preview  " .. Action(lastPrefix, lastButton)) end
    end
    for index, choice in ipairs(captions) do
        local y = -158 - (index - 1) * 18
        addon.Label(page, choice[3], nil, 0, y, addon.color.dim)
        shown[index] = addon.Label(page, "", nil, 156, y, addon.color.text)
    end
    practice:SetScript("OnClick", function(_, button)
        local prefix, number = addon.ReadHealthClick(button)
        if number then
            lastPrefix, lastButton = prefix, number
            gesture:SetText(addon.HealthClickLabel(prefix, number))
            result:SetText("Preview  " .. Action(prefix, number))
        end
    end)
    addon.RefreshPracticeBindings = Refresh
    return function()
        lastPrefix, lastButton = nil, nil
        sample(false)
        Refresh()
        gesture:SetText("")
        result:SetText("Preview only")
    end
end

local function HealingTooltip()
    local prefix = addon.HealthClickModifiers()
    local lines = {}
    for _, button in ipairs(primaryButtons) do
        local name = ClickActionText(activeClicks[prefix .. button])
        if name then lines[#lines + 1] = addon.HealthClickLabel(prefix, button) .. "  " .. name end
    end
    if #lines == 0 then
        lines[1] = prefix == "" and "No plain mouse clicks assigned." or "No clicks assigned for the held modifiers."
    end
    if not InCombatLockdown() then
        lines[#lines + 1] = "More bindings in Custom spells > Saved clicks."
    end
    return table.concat(lines, "\n")
end

local function LayoutHealthReadouts(row, both)
    local amount, percent, health = row.amount, row.percent, row.health
    amount:ClearAllPoints()
    percent:ClearAllPoints()
    if row.raidNotify then
        local available = raidCellWidth - 26
        local percentWidth = 33
        amount:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 4, 2)
        amount:SetWidth(both and available - percentWidth - 1 or available)
        percent:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", both and available - percentWidth + 4 or 4, 2)
        percent:SetWidth(both and percentWidth or available)
    else
        local party = row.unit:match("^party") ~= nil
        local right = party and -135 or -8
        local left = party and -181 or -52
        amount:SetPoint("RIGHT", health, "RIGHT", both and left or right, 0)
        amount:SetWidth(both and (party and 46 or 58) or 79)
        percent:SetPoint("RIGHT", health, "RIGHT", right, 0)
        percent:SetWidth(37)
    end
    row.bothHealthReadouts = both
end

local function PaintRow(row)
    local appearance = addon.db.appearance
    local color
    if appearance.classColors and RAID_CLASS_COLORS then
        local _, class = UnitClass(row.unit)
        if not (issecretvalue and issecretvalue(class)) then color = RAID_CLASS_COLORS[class] end
    end
    if color then
        row.health:SetStatusBarColor(color.r * 0.62, color.g * 0.62, color.b * 0.62, 1)
    else
        row.health:SetStatusBarColor(unpack(addon.healthColors[appearance.palette]))
    end
    row.amount:SetShown(appearance.healthAmount and not row.unitCondition)
    row.percent:SetShown(appearance.healthText and not row.unitCondition)
    local both = appearance.healthAmount and appearance.healthText
    if row.bothHealthReadouts ~= both then LayoutHealthReadouts(row, both) end
end

local function RefreshUnitCondition(row)
    local connected, dead = UnitIsConnected(row.unit), UnitIsDeadOrGhost(row.unit)
    local ghost = UnitIsGhost and UnitIsGhost(row.unit)
    local condition
    if not isSecret(connected) and connected == false then
        condition = "Offline"
    elseif not isSecret(ghost) and ghost == true then
        condition = "Ghost"
    elseif not isSecret(dead) and dead == true then
        condition = "Dead"
    end
    if row.unitCondition == condition then return end
    row.unitCondition = condition
    row.status:SetText(condition or "")
    row.status:SetShown(condition ~= nil)
    row.amount:SetShown(not condition and addon.db.appearance.healthAmount)
    row.percent:SetShown(not condition and addon.db.appearance.healthText)
end

local function UpdateHealth(row, includeMaximum)
    local appearance = addon.db.appearance
    local amount = UnitHealth(row.unit)
    if includeMaximum then
        local maximum = UnitHealthMax(row.unit)
        row.readableMaximum = not isSecret(maximum) and type(maximum) == "number" and maximum or nil
        row.health:SetMinMaxValues(0, maximum)
        addon.RefreshRowHealthCues(row, maximum)
    end
    local readable = not isSecret(amount) and type(amount) == "number"
    if readable and not includeMaximum and row.readableHealth == amount then return end
    row.readableHealth = readable and amount or nil
    row.health:SetValue(amount)
    local maximum = row.readableMaximum
    local fraction = readable and maximum and maximum > 0 and amount / maximum
    if fraction then
        row.critical:SetAlpha(fraction > 0 and fraction < criticalHealth and 1 or 0)
    elseif criticalCurve then
        local color = UnitHealthPercent(row.unit, false, criticalCurve)
        if color then row.critical:SetAlpha(select(4, color:GetRGBA()))
        else row.critical:SetAlpha(0) end
    else
        row.critical:SetAlpha(0)
    end
    -- Native formatting and widget setters accept protected health values.
    if appearance.healthAmount then
        if AbbreviateNumbers then row.amount:SetText((AbbreviateNumbers(amount)))
        else row.amount:SetFormattedText("%d", amount) end
    end
    if appearance.healthText then
        local percent = fraction and fraction * 100
        if not fraction and UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
            percent = UnitHealthPercent(row.unit, false, CurveConstants.ScaleTo100)
        end
        if isSecret(percent) or type(percent) == "number" then
            row.percent:SetFormattedText("%.0f%%", percent)
        else
            row.percent:SetText("")
        end
    end
end

local function FlushHealthRows()
    healthQueued = false
    for row, maximum in pairs(healthRows) do
        healthRows[row] = nil
        if row:IsVisible() then UpdateHealth(row, maximum) end
    end
end

local function QueueHealth(row, maximum)
    healthRows[row] = healthRows[row] or maximum
    if not healthQueued then
        healthQueued = true
        C_Timer.After(0, FlushHealthRows)
    end
end

local function PaintCleanse(row)
    local visible = false
    if row:IsVisible() then
        local ok, auras = pcall(C_UnitAuras.GetUnitAuras, row.unit, "HARMFUL|RAID_PLAYER_DISPELLABLE", 12)
        if ok and not isSecret(auras) and type(auras) == "table" then
            for index = 1, math.min(#auras, 12) do
                local aura = auras[index]
                if not isSecret(aura) and type(aura) == "table" then
                    local canDispel = aura.canActivePlayerDispel
                    if not isSecret(canDispel) and canDispel == true then visible = true; break end
                end
            end
        end
    end
    row.cleanse:SetAlpha(visible and 1 or 0)
end

local function FlushCleanseRows()
    local processed = 0
    for row in pairs(cleanseRows) do
        cleanseRows[row] = nil
        PaintCleanse(row)
        processed = processed + 1
        if processed == 10 then break end
    end
    cleanseQueued = next(cleanseRows) ~= nil
    if cleanseQueued then C_Timer.After(0.1, FlushCleanseRows) end
end

local function QueueCleanse(row)
    if not cleanseEnabled then return end
    cleanseRows[row] = true
    if not cleanseQueued then
        cleanseQueued = true
        C_Timer.After(0.1, FlushCleanseRows)
    end
end

function addon.RefreshCleanseCues()
    local enabled = addon.db.appearance.cleanseCue and C_UnitAuras and C_UnitAuras.GetUnitAuras ~= nil
    if not healingEvents or enabled == cleanseEnabled then return end
    cleanseEnabled = enabled
    if enabled then
        healingEvents:RegisterEvent("UNIT_AURA")
        for _, row in pairs(rows) do
            if row:IsVisible() then QueueCleanse(row) end
        end
    else
        healingEvents:UnregisterEvent("UNIT_AURA")
        wipe(cleanseRows)
        for _, row in pairs(rows) do row.cleanse:SetAlpha(0) end
    end
end

function addon.RefreshHealingIndicatorOptions()
    if healingEvents then
        addon.RegisterHealthCueEvents(healingEvents)
        addon.RegisterThreatCueEvents(healingEvents)
    end
    addon.RefreshLegacyResources()
end

local function RefreshRow(row)
    if not row:IsVisible() then return end
    PaintRow(row)
    RefreshUnitCondition(row)
    addon.RefreshThreatCue(row)
    row.unitLabel:SetText((UnitName(row.unit)))
    if row.raidNotify and UnitIsUnit then
        local same = UnitIsUnit(row.unit, "player")
        row.raidNotify:SetShown(isSecret(same) or not same)
    end
    local nameWidth = row.normalNameWidth
    if row.privateAuraID then nameWidth = row.raidNotify and nameWidth - 12 or math.min(nameWidth, 125) end
    if row.roleLabel then
        local showRole = addon.db.appearance.groupRoles and IsInGroup()
        row.roleLabel:SetShown(showRole)
        if showRole then nameWidth = 84 end
        if showRole then
            local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(row.unit)
            row.roleLabel:SetText((not isSecret(role) and roleLabels[role]) or roleLabels.NONE)
        end
    end
    if row.nameWidth ~= nameWidth then
        row.unitLabel:SetWidth(nameWidth)
        row.nameWidth = nameWidth
    end
    healthRows[row] = nil
    UpdateHealth(row, true)
    QueueCleanse(row)
end

local function MakeRow(panel, unit, label, width, raid)
    local row = addon.Button(panel, nil, width, 24, "SecureActionButtonTemplate")
    row:SetAttribute("useOnKeyDown", false)
    row:RegisterForClicks("AnyUp")
    row:SetAttribute("unit", unit)
    InheritClickBindings(row)
    row:SetAttribute("checkselfcast", false)
    row:SetAttribute("checkfocuscast", false)
    row:SetAttribute("checkmouseovercast", false)
    row.unit = unit
    for attribute, cast in pairs(targetCasts) do
        row:SetAttribute(attribute, TargetCastMacro(unit, cast))
    end

    local health = CreateFrame("StatusBar", nil, row)
    health:SetAllPoints(row)
    health:SetStatusBarTexture(addon.solidTexture)
    if health.SetReverseFill then health:SetReverseFill(false) end
    row.health = health
    addon.AttachRowHealthCues(row)
    addon.TrackPrivateAuraRow(row, raid)
    addon.AttachThreatCue(row)
    local party = unit:match("^party") ~= nil
    local name = addon.Label(health, "", raid and "GameFontHighlightSmall" or "GameFontHighlight", 0, 0)
    name:ClearAllPoints()
    if raid then
        name:SetPoint("TOPLEFT", health, "TOPLEFT", 5, addon.HasHealthCues() and -8 or -4)
    else
        local tag = addon.Label(health, label, nil, 0, 0, addon.color.text)
        tag:ClearAllPoints()
        tag:SetPoint("LEFT", health, "LEFT", 8, 0)
        name:SetPoint("LEFT", health, "LEFT", 61, 0)
    end
    row.normalNameWidth = raid and width - 32 or (party and 130 or 248)
    name:SetWidth(row.normalNameWidth)
    name:SetWordWrap(false)
    name:SetJustifyH("LEFT")
    row.unitLabel = name
    if unit == "player" or party then
        local role = addon.Label(health, "", "GameFontHighlightSmall", 0, 0, addon.color.text)
        role:ClearAllPoints()
        role:SetPoint("LEFT", health, "LEFT", 147, 0)
        role:SetWidth(45)
        role:SetWordWrap(false)
        role:SetJustifyH("LEFT")
        role:Hide()
        row.roleLabel = role
    end
    local percent = addon.Label(health, "", nil, 0, 0, addon.color.text)
    local amount = addon.Label(health, "", nil, 0, 0, addon.color.text)
    amount:SetJustifyH(raid and "LEFT" or "RIGHT")
    percent:SetJustifyH(raid and "LEFT" or "RIGHT")
    amount:SetWordWrap(false)
    percent:SetWordWrap(false)
    row.amount, row.percent = amount, percent
    row.status = addon.Label(health, "", "GameFontHighlightSmall", 0, 0, addon.color.dim)
    row.status:ClearAllPoints()
    row.status:SetPoint("LEFT", amount, "LEFT")
    row.status:Hide()
    row.critical = health:CreateTexture(nil, "ARTWORK")
    row.critical:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT")
    row.critical:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT")
    row.critical:SetHeight(3)
    row.critical:SetColorTexture(1, 0.26, 0.25, 0.95)
    row.critical:SetAlpha(0)
    row.cleanse = health:CreateTexture(nil, "OVERLAY")
    row.cleanse:SetPoint("TOPLEFT", health, "TOPLEFT")
    row.cleanse:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT")
    row.cleanse:SetWidth(3)
    row.cleanse:SetColorTexture(0.54, 0.78, 0.93, 0.9)
    row.cleanse:SetAlpha(0)
    local outline = {}
    for index, anchors in ipairs(outlineAnchors) do
        local edge = health:CreateTexture(nil, "OVERLAY", nil, 1)
        edge:SetPoint(anchors[1], health, anchors[1])
        edge:SetPoint(anchors[2], health, anchors[2])
        if index <= 2 then edge:SetHeight(1) else edge:SetWidth(1) end
        edge:SetColorTexture(0.97, 0.82, 0.55, 0.72)
        edge:Hide()
        outline[index] = edge
    end
    local function ShowOutline(shown)
        for _, edge in ipairs(outline) do edge:SetShown(shown) end
    end

    row.ShowClickTooltip = addon.Tooltip(row, function()
        local name = UnitName(row.unit)
        return not isSecret(name) and type(name) == "string" and name or label
    end, HealingTooltip, addon.ShowHealingTooltips)
    row:HookScript("OnEnter", function() ShowOutline(addon.db.appearance.hoverEdge) end)
    row:HookScript("OnLeave", function() ShowOutline(false) end)
    row:HookScript("OnHide", function()
        ShowOutline(false)
        if GameTooltip.GetOwner and GameTooltip:GetOwner() == row then GameTooltip:Hide() end
        row.cleanse:SetAlpha(0)
    end)
    if party or raid then addon.AttachRangeAlert(row, raid) end
    if party then
        local placeholder = panel:CreateTexture(nil, "BACKGROUND")
        placeholder:SetAllPoints(row)
        placeholder:SetColorTexture(0.07, 0.13, 0.15, 1)
        local tag = addon.Label(panel, label, nil, 0, 0, addon.color.dim)
        tag:ClearAllPoints()
        tag:SetPoint("LEFT", placeholder, "LEFT", 8, 0)
    end
    row:HookScript("OnShow", RefreshRow)
    RegisterUnitWatch(row)
    PaintRow(row)
    return row
end


function addon.OpenBlizzardClickCasting()
    if not addon.CanEdit() then return end
    if ToggleClickBindingFrame then
        ToggleClickBindingFrame()
    else
        local loadAddOn = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
        if loadAddOn then loadAddOn("Blizzard_ClickBindingUI") end
        if ClickBindingFrame then
            ShowUIPanel(ClickBindingFrame)
        else
            addon.Print("Blizzard Click Casting is available only on clients that include it. Configure Triage in Custom spells.")
        end
    end
end

local function BuildSpellKeys()
    for _, mode in ipairs(addon.healModes) do
        keys[mode] = {}
        local prefix = mode == "single" and "Single" or "Area"
        for index in ipairs(slots) do
            local gesture = clicks[mode][index]
            keys[mode][index] = addon.CreateBindingButton(prefix .. index,
                addon.healModeLabels[mode] .. " spell " .. index)
            clickKeys[gesture.prefix .. gesture.suffix] = KeyName(mode, index)
        end
    end
    keys.emergency = addon.CreateBindingButton("Emergency", "Emergency heal")
    keys.emergency:SetScript("PreClick", PrepareEmergencyCast)
    clickKeys["alt-2"] = BindingCommand(keys.emergency)
end

local function BuildSpellTile(panel, iconKey, click, emergency)
    local button = addon.Button(panel, nil, 110, tileHeight, "SecureActionButtonTemplate")
    button.iconKey, button.gesture, button.emergency = iconKey, click, emergency
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(19, 19)
    button.icon:SetPoint("LEFT", button, "LEFT", 4, 0)
    button.text = addon.Label(button, "", nil, 26, emergency and -16 or -4)
    button.hint = addon.Label(button, emergency and "Emergency" or "", nil, 26, emergency and -4 or -16,
        emergency and { 1, 0.58, 0.53, 1 } or addon.color.dim)
    button.detail = addon.Label(button, "", nil, 26, -28, addon.color.dim)
    button.lines = { button.text, button.hint, button.detail }
    for _, label in ipairs(button.lines) do
        label:SetWordWrap(false)
        label:SetJustifyH("LEFT")
    end
    if emergency then
        button.spellLabel = button.text
        button:SetScript("PreClick", PrepareEmergencyCast)
        addon.AttachEmergencyTiming(button)
    else
        button.name = button.text
    end
    addon.Tooltip(button, emergency and "Emergency heal" or "Healing panel", function()
        local spell = button.spell
        local info = addon.SpellInfo(spell)
        local prefix, mouse = addon.ParseHealthClick(button.click)
        local key = addon.AssignedHealingKey(spell, button.click)
        local detail = { addon.SpellDisplay(spell) or "Unassigned" }
        if info and type(spell) == "number" and info.spellID ~= spell then
            detail[#detail + 1] = "Active spell ID " .. info.spellID
        end
        if prefix then detail[#detail + 1] = "Health bar  " .. addon.HealthClickLabel(prefix, mouse) end
        if key then detail[#detail + 1] = "Keyboard  " .. key end
        if spell == addon.targetClick then
            detail[#detail + 1] = "Use this click on a health bar to select that unit."
        elseif emergency then
            detail[#detail + 1] = "Use a living friendly mouseover or Alt + right-click an ally's bar. Outside combat, Auto target can choose the most injured ally in confirmed range before falling back to your current target."
            if button.cooldown then detail[#detail + 1] = "The icon shows the client's spell cooldown." end
        else
            detail[#detail + 1] = "Use left, middle, or right-click on this tile for a quick cast."
            local style = addon.SpellStyle(spell)
            if style == "ally" then detail[#detail + 1] = "Requires a living friendly target or mouseover."
            elseif style == "enemy" then detail[#detail + 1] = "Uses a living hostile mouseover or target."
            elseif style == "self" then detail[#detail + 1] = "Casts on your character."
            elseif style == "pet" then detail[#detail + 1] = "Casts on your living pet."
            elseif style == "resurrect" then detail[#detail + 1] = "Requires a friendly dead target or mouseover."
            elseif style == "standalone" then detail[#detail + 1] = "Uses the spell's normal targeting."
            elseif style == "dual" then detail[#detail + 1] = "Uses a living friendly or hostile mouseover or target, then you."
            else detail[#detail + 1] = "Uses a friendly mouseover or target, then you." end
        end
        return table.concat(detail, "\n")
    end, addon.ShowHealingTooltips)
    button:Hide()
    return button
end

local function BuildSpellControls(panel, heading, contentWidth)
    addon.Label(panel, heading, "GameFontHighlight", addon.inset, -11, addon.color.accent)
    local edit = addon.Button(panel, "Assign spells", 103, 25)
    edit:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -addon.inset, -5)
    edit:SetScript("OnClick", addon.OpenSpellOptions)
    addon.Tooltip(edit, "Assign spells", "Choose spells for mouse buttons and modifier combinations. Combat changes apply after combat.")
    local mouse = addon.Button(panel, "Mouse buttons", 91, 25)
    mouse:SetPoint("RIGHT", edit, "LEFT", -5, 0)
    mouse:SetScript("OnClick", addon.OpenMouseOptions)
    local allHeals = addon.Button(panel, "All heals", 69, 25)
    allHeals:SetPoint("RIGHT", mouse, "LEFT", -5, 0)
    allHeals:SetScript("OnClick", addon.OpenHealingLoadout)

    local tray = { panel = panel, width = contentWidth, groups = {} }
    tinsert(trays, tray)
    for _, group in ipairs(addon.spellIconGroups) do
        local row = { heading = addon.Label(panel, group.label, nil, addon.inset, 0, addon.color.dim), buttons = {} }
        for _, icon in ipairs(group.icons) do tinsert(row.buttons, BuildSpellTile(panel, icon.key, icon.click)) end
        tinsert(tray.groups, row)
    end
    local extras = tray.groups[#tray.groups]
    tinsert(extras.buttons, BuildSpellTile(panel, "emergency", "alt-2", true))
end

function addon.RefreshHealingAppearance()
    if partyHint then
        partyHint:SetText(IsInRaid() and "Your raid subgroup. Use Raid or Combined for all groups." or partyHintText)
    end
    for _, row in pairs(rows) do RefreshRow(row) end
end

function addon.RefreshPartyAppearance()
    local appearance = addon.db.appearance
    local compact = appearance.density == "compact"
    local height = compact and 22 or 27
    local gap = compact and 3 or 5
    for index, unit in ipairs(OrderedUnits("party", 4, "player", partyTank)) do
        local row = rows[unit]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", partySection, "TOPLEFT", addon.inset, -rowStart - (index - 1) * (height + gap))
        row:SetHeight(height)
    end
    petSection:ClearAllPoints()
    petSection:SetPoint("TOPLEFT", partySection, "TOPLEFT", addon.inset, -rowStart - 5 * (height + gap))
    petSection:SetSize(addon.contentWidth, height)
    rows.pet:SetHeight(height)
    petSection:SetShown(appearance.pet)
    local slotsHeight = (appearance.pet and 6 or 5) * (height + gap)
    partyHint:ClearAllPoints()
    partyHint:SetPoint("TOPLEFT", partySection, "TOPLEFT", addon.inset, -rowStart - 10 - slotsHeight)
    partySection:SetHeight(rowStart + 33 + slotsHeight + addon.LegacyResourceHeight())
    addon.RefreshHealingAppearance()
end

function addon.BuildHealing(panel)
    partySection = panel
    if type(addon.db.targetOnHeal) ~= "boolean" then addon.db.targetOnHeal = true end
    InheritClickBindings(panel)
    addon.BuildProfiles()

    BuildSpellKeys()
    BuildSpellControls(panel, "Party healing", addon.contentWidth)

    rows.player = MakeRow(panel, "player", "Self", addon.contentWidth)
    for index = 1, 4 do
        local unit = "party" .. index
        rows[unit] = MakeRow(panel, unit, "Party " .. index, addon.contentWidth)
    end
    petSection = CreateFrame("Frame", nil, panel)
    InheritClickBindings(petSection)
    rows.pet = MakeRow(petSection, "pet", "Pet", addon.contentWidth)
    rows.pet:SetPoint("TOPLEFT", petSection, "TOPLEFT")
    partyHint = addon.Label(panel, partyHintText, nil, addon.inset, 0, addon.color.dim)
    addon.BuildLegacyResources(panel, partyHint)
    addon.RefreshPartyAppearance()
    ApplyBindings()

    local events = CreateFrame("Frame", nil, panel)
    healingEvents = events
    events:RegisterEvent("UNIT_HEALTH")
    events:RegisterEvent("UNIT_MAXHEALTH")
    events:RegisterEvent("UNIT_NAME_UPDATE")
    addon.TryRegisterEvent(events, "UNIT_CONNECTION")
    addon.TryRegisterEvent(events, "UNIT_FLAGS")
    addon.RegisterHealthCueEvents(events)
    addon.RegisterThreatCueEvents(events)
    events:RegisterEvent("GROUP_ROSTER_UPDATE")
    events:RegisterEvent("UNIT_PET")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    addon.TryRegisterEvent(events, "PLAYER_ROLES_ASSIGNED")
    addon.TryRegisterEvent(events, "MODIFIER_STATE_CHANGED")
    local rosterRefreshQueued
    events:SetScript("OnEvent", function(_, event, unit)
        if event == "MODIFIER_STATE_CHANGED" then
            RefreshHoveredClickTooltip()
        elseif event == "PLAYER_REGEN_DISABLED" then
            addon.ClearHealingTooltip()
        elseif event == "PLAYER_REGEN_ENABLED" then
            if pendingPriority then addon.RefreshHealingPriorities() end
        elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_ROLES_ASSIGNED" then
            if not rosterRefreshQueued then
                rosterRefreshQueued = true
                C_Timer.After(0, function()
                    rosterRefreshQueued = nil
                    addon.RefreshHealingPriorities()
                    addon.RefreshHealingAppearance()
                end)
            end
        elseif issecretvalue and issecretvalue(unit) then
            return
        elseif event == "UNIT_PET" and unit == "player" then
            RefreshRow(rows.pet)
        else
            local row = rows[unit]
            if not row or not row:IsVisible() then return end
            if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
                QueueHealth(row, event == "UNIT_MAXHEALTH")
            elseif event == "UNIT_NAME_UPDATE" then
                row.unitLabel:SetText((UnitName(unit)))
            elseif event == "UNIT_AURA" then
                QueueCleanse(row)
            elseif event == "UNIT_CONNECTION" or event == "UNIT_FLAGS" then
                RefreshUnitCondition(row)
            elseif event == "UNIT_THREAT_SITUATION_UPDATE" then
                addon.RefreshThreatCue(row)
            else
                addon.QueueRowHealthCue(row, event)
            end
        end
    end)

    for _, row in pairs(rows) do
        RefreshRow(row)
    end

    local profileEvents = CreateFrame("Frame")
    for _, event in ipairs({ "SPELLS_CHANGED", "SPELL_FLYOUT_UPDATE", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_SPECIALIZATION_CHANGED",
        "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_TALENT_UPDATE", "ACTIVE_COMBAT_CONFIG_CHANGED", "TRAIT_CONFIG_UPDATED",
        "PLAYER_PVP_TALENT_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "UNIT_PET",
        "SPELL_DATA_LOAD_RESULT", "UPDATE_BINDINGS" }) do
        addon.TryRegisterEvent(profileEvents, event)
    end
    local queued
    profileEvents:SetScript("OnEvent", function(_, event, unit)
        if event == "UPDATE_BINDINGS" then
            if not changingShortcuts then
                RefreshHealingShortcuts()
                if addon.RefreshHealingLoadout then addon.RefreshHealingLoadout() end
                refreshTrayLabels()
            end
            return
        end
        if ((event == "PLAYER_SPECIALIZATION_CHANGED" or event == "UNIT_PET") and unit and unit ~= "player")
            or (event == "TRAIT_CONFIG_UPDATED" and not addon.IsTalentConfig(unit))
            or (event == "SPELL_DATA_LOAD_RESULT" and not addon.HealingDescriptionLoaded(unit))
            or (event == "PLAYER_REGEN_ENABLED" and not pendingBindings) then
            return
        end
        if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
            addon.CloseSettings()
        end
        if not queued then
            queued = true
            C_Timer.After(0, function()
                queued = false
                if InCombatLockdown() then
                    pendingBindings = true
                    return
                end
                local wasPending = pendingBindings
                addon.RefreshProfiles()
                ApplyBindings()
                if syncSpellFields and options:IsVisible() then syncSpellFields({}) end
                if addon.RefreshSpellIconSettings then addon.RefreshSpellIconSettings(true) end
                addon.RefreshAbilityPicker()
                if addon.UpdateRangeReference then addon.UpdateRangeReference() end
                if wasPending and options and options.errorText:GetText() == pendingBindingNote then
                    options.errorText:SetText("New spell bindings are active.")
                end
            end)
        end
    end)
end


function addon.BuildRaid(panel)
    raidSection = panel
    InheritClickBindings(panel)
    BuildSpellControls(panel, "Raid healing", addon.raidWidth - 2 * addon.inset)

    for group = 1, addon.raidGroupLimit do
        raidLabels[group] = addon.Label(panel, "", "GameFontHighlightSmall", addon.inset, 0, addon.color.accent)
    end
    for index = 1, addon.raidMemberLimit do
        local unit = "raid" .. index
        local row = MakeRow(panel, unit, "Raid member " .. index, raidCellWidth, true)
        row:SetHeight(31)
        rows[unit] = row
    end
    raidHint = addon.Label(panel, "Use the same clicks on party and raid bars. See All heals for every assignment.", nil,
        addon.inset, 0, addon.color.dim)
    addon.BuildLegacyResources(panel, raidHint)
    addon.RefreshPrivateAuraAnchors()
    addon.RefreshHealingPriorities()
    addon.RefreshCleanseCues()
    ApplyBindings()
end
