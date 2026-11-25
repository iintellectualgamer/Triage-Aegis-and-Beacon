local _, addon = ...
local isSecret = issecretvalue or function() return false end

local healthCues = {
    { event = "UNIT_ABSORB_AMOUNT_CHANGED", read = UnitGetTotalAbsorbs, color = { 0.41, 0.76, 1 } },
    { event = "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", read = UnitGetTotalHealAbsorbs, color = { 1, 0.68, 0.22 }, reverse = true },
    { event = "UNIT_HEAL_PREDICTION", read = UnitGetIncomingHeals, color = { 0.47, 1, 0.60 } },
}
local availableCues, queuedCues = {}, {}
local cuesScheduled

for _, cue in ipairs(healthCues) do
    if cue.read then availableCues[cue.event] = cue end
end

function addon.HasHealthCues()
    return next(availableCues) ~= nil
end

local function NewCue(row, cue, index)
    local bar = CreateFrame("StatusBar", nil, row.health)
    local y = 1 + (index - 1) * 2
    bar:SetPoint("TOPLEFT", row.health, "TOPLEFT", 3, -y)
    bar:SetPoint("TOPRIGHT", row.health, "TOPRIGHT", -3, -y)
    bar:SetHeight(2)
    bar:SetStatusBarTexture(addon.solidTexture)
    bar:SetStatusBarColor(unpack(cue.color))
    if cue.reverse and bar.SetReverseFill then bar:SetReverseFill(true) end
    bar:EnableMouse(false)
    return bar
end

local function PaintCue(row, cue, bar)
    local value = cue.read(row.unit)
    -- The client can render an opaque combat value directly in a status bar.
    bar:SetValue((isSecret(value) or type(value) == "number") and value or 0)
end

function addon.AttachRowHealthCues(row)
    if not addon.HasHealthCues() then return end
    row.healthCues = {}
    for index, cue in ipairs(healthCues) do
        if cue.read then
            local bar = NewCue(row, cue, index)
            bar:Hide()
            row.healthCues[cue.event] = bar
        end
    end
end

function addon.RefreshRowHealthCues(row, maximum)
    if not row.healthCues then return end
    queuedCues[row] = nil
    local enabled = addon.db.appearance.healthCues
    for event, bar in pairs(row.healthCues) do
        if enabled then
            bar:SetMinMaxValues(0, maximum)
            PaintCue(row, availableCues[event], bar)
        end
        bar:SetShown(enabled)
    end
end

local function FlushCues()
    cuesScheduled = false
    for row, events in pairs(queuedCues) do
        queuedCues[row] = nil
        if row:IsVisible() and addon.db.appearance.healthCues then
            for event in pairs(events) do
                local bar = row.healthCues and row.healthCues[event]
                if bar then PaintCue(row, availableCues[event], bar) end
            end
        end
    end
end

function addon.QueueRowHealthCue(row, event)
    if not availableCues[event] or not addon.db.appearance.healthCues then return end
    local events = queuedCues[row]
    if not events then
        events = {}
        queuedCues[row] = events
    end
    events[event] = true
    if not cuesScheduled then
        cuesScheduled = true
        C_Timer.After(0, FlushCues)
    end
end

function addon.RegisterHealthCueEvents(frame)
    for event in pairs(availableCues) do
        if addon.db.appearance.healthCues then
            addon.TryRegisterEvent(frame, event)
        else
            frame:UnregisterEvent(event)
        end
    end
end

function addon.AddPracticeVitals(button)
    local width = button:GetWidth() - 12
    local fill = button:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", button, "TOPLEFT", 6, -7)
    fill:SetHeight(button:GetHeight() - 14)
    local lanes = {}
    for index, cue in ipairs(healthCues) do
        local lane = button:CreateTexture(nil, "OVERLAY")
        lane:SetPoint(cue.reverse and "TOPRIGHT" or "TOPLEFT", button,
            cue.reverse and "TOPRIGHT" or "TOPLEFT", cue.reverse and -6 or 6, -3 - (index - 1) * 3)
        lane:SetHeight(2)
        lane:SetColorTexture(unpack(cue.color))
        lanes[index] = lane
    end
    local critical = button:CreateTexture(nil, "OVERLAY")
    critical:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 6, 3)
    critical:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -6, 3)
    critical:SetHeight(3)
    critical:SetColorTexture(1, 0.26, 0.25, 0.95)
    local sample = {
        { "Practice target", nil },
        { "Damage shield  |  72% health", 0.72, 0.47 },
        { "Healing absorbed  |  58% health", 0.58, 0, 0.55 },
        { "Incoming heals  |  41% health", 0.41, 0, 0, 0.25 },
        { "Critical health  |  22% health", 0.22 },
    }
    local selected = 1
    return function(advance)
        selected = advance and selected % #sample + 1 or 1
        local state = sample[selected]
        button.label:SetText(state[1])
        fill:SetShown(state[2] ~= nil)
        if state[2] then
            fill:SetWidth(width * state[2])
            fill:SetColorTexture(unpack(addon.healthColors[addon.db.appearance.palette]))
        end
        critical:SetShown(selected == #sample)
        for index, lane in ipairs(lanes) do
            local amount = state[index + 2] or 0
            lane:SetShown(amount > 0)
            if amount > 0 then lane:SetWidth(width * amount) end
        end
    end
end

local privateRows = {}
function addon.HasPrivateAuraAnchors()
    return (addon.InterfaceVersion() >= 120000 or addon.IsForever())
        and C_UnitAuras and C_UnitAuras.AddPrivateAuraAnchor and C_UnitAuras.RemovePrivateAuraAnchor ~= nil
end

function addon.TrackPrivateAuraRow(row, raid)
    if row.unit ~= "pet" and addon.HasPrivateAuraAnchors() then privateRows[row] = raid == true end
end

function addon.RefreshPrivateAuraAnchors()
    if InCombatLockdown() or not addon.HasPrivateAuraAnchors() then return end
    local enabled = addon.db.appearance.privateAuras
    for row, raid in pairs(privateRows) do
        if enabled and not row.privateAuraID then
            local icon = row.privateAuraSlot
            if not icon then
                icon = CreateFrame("Frame", nil, row.health)
                icon:SetSize(14, 14)
                icon:EnableMouse(false)
                if raid then icon:SetPoint("RIGHT", row.health, "RIGHT", -23, 4)
                else icon:SetPoint("LEFT", row.health, "LEFT", 190, 0) end
                row.privateAuraSlot = icon
            end
            local options = {
                unitToken = row.unit, auraIndex = 1, parent = icon,
                iconInfo = { iconWidth = 14, iconHeight = 14, iconAnchor = {
                    point = "CENTER", relativeTo = icon, relativePoint = "CENTER", offsetX = 0, offsetY = 0,
                } },
            }
            if addon.InterfaceVersion() >= 120100 then options.showCooldownFrame = true
            else options.showCountdownFrame = true end
            local ok, id = pcall(C_UnitAuras.AddPrivateAuraAnchor, options)
            if ok and not isSecret(id) and type(id) == "number" then row.privateAuraID = id end
        elseif not enabled and row.privateAuraID then
            C_UnitAuras.RemovePrivateAuraAnchor(row.privateAuraID)
            row.privateAuraID = nil
        end
    end
end

local cooldownEvents, cooldownQueued
local emergencyTiles = {}
local getDuration = C_Spell and C_Spell.GetSpellCooldownDuration
local getCooldown = C_Spell and C_Spell.GetSpellCooldown
local legacyCooldown = GetSpellCooldown

local function RenderedCooldown(tile, spell)
    local overlay = tile.cooldown
    if getDuration and overlay.SetCooldownFromDurationObject then
        local duration = getDuration(spell, true)
        if isSecret(duration) or duration then
            overlay:SetCooldownFromDurationObject(duration, true)
            return
        end
    end
    local start, seconds, rate
    if getCooldown then
        local data = getCooldown(spell)
        if not isSecret(data) and data then
            start, seconds, rate = data.startTime, data.duration, data.modRate
        end
    elseif legacyCooldown then
        start, seconds, _, rate = legacyCooldown(spell)
    end
    if not isSecret(start) and not isSecret(seconds) and type(start) == "number" and type(seconds) == "number" then
        overlay:SetCooldown(start, seconds, not isSecret(rate) and type(rate) == "number" and rate or 1)
    else
        overlay:SetCooldown(0, 0)
    end
end

local function RefreshCooldowns()
    cooldownQueued = false
    for tile in pairs(emergencyTiles) do
        if tile:IsVisible() and tile.spellID then RenderedCooldown(tile, tile.spellID) end
    end
end

local function SyncCooldownEvents()
    local visible
    for tile in pairs(emergencyTiles) do
        if tile:IsVisible() and tile.spellID then
            visible = true
            break
        end
    end
    if cooldownEvents.active == visible then return end
    cooldownEvents.active = visible
    if visible then
        addon.TryRegisterEvent(cooldownEvents, "SPELL_UPDATE_COOLDOWN")
        addon.TryRegisterEvent(cooldownEvents, "SPELL_UPDATE_CHARGES")
    else
        cooldownEvents:UnregisterAllEvents()
    end
end

function addon.RefreshEmergencyTiming(tile)
    if not tile.cooldown then return end
    SyncCooldownEvents()
    if tile:IsVisible() and tile.spellID then RenderedCooldown(tile, tile.spellID) end
end

function addon.AttachEmergencyTiming(tile)
    if not (getDuration or getCooldown or legacyCooldown) then return end
    local overlay = CreateFrame("Cooldown", nil, tile, "CooldownFrameTemplate")
    overlay:SetAllPoints(tile.icon)
    overlay:EnableMouse(false)
    tile.cooldown = overlay
    emergencyTiles[tile] = true
    if not cooldownEvents then
        cooldownEvents = CreateFrame("Frame")
        cooldownEvents:SetScript("OnEvent", function()
            if cooldownQueued then return end
            cooldownQueued = true
            C_Timer.After(0, RefreshCooldowns)
        end)
    end
    tile:HookScript("OnShow", addon.RefreshEmergencyTiming)
    tile:HookScript("OnHide", SyncCooldownEvents)
end

local powerType = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
local meters, resourceEvents = {}, nil
local lastMana, castAt, spentAt, regenStarts
local manaWindow = 5
local castMatchWindow = 0.25
local getCost = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost

local function LegacyClient()
    return addon.IsClassic() or addon.IsForever()
end

function addon.HasLegacyResources()
    return LegacyClient() and (UnitPower and UnitPowerMax or UnitThreatSituation) ~= nil
end

function addon.LegacyResourceHeight()
    return addon.HasLegacyResources() and addon.db.appearance.legacyResources and 23 or 0
end

local function ThreatLevel(unit)
    local state = UnitThreatSituation(unit)
    return not isSecret(state) and type(state) == "number" and state or 0
end

function addon.AttachThreatCue(row)
    if not LegacyClient() or not UnitThreatSituation or row.unit == "pet" then return end
    local edge = row.health:CreateTexture(nil, "OVERLAY")
    edge:SetPoint("TOPRIGHT", row.health, "TOPRIGHT", -1, -2)
    edge:SetPoint("BOTTOMRIGHT", row.health, "BOTTOMRIGHT", -1, 2)
    edge:SetWidth(2)
    edge:Hide()
    row.threatCue = edge
end

function addon.RefreshThreatCue(row)
    local edge = row.threatCue
    if not edge then return end
    local level = addon.db.appearance.legacyResources and ThreatLevel(row.unit) or 0
    if level == row.threatLevel then return end
    row.threatLevel = level
    if level >= 2 then edge:SetColorTexture(1, 0.37, 0.37, 1)
    elseif level == 1 then edge:SetColorTexture(1, 0.68, 0.24, 1) end
    edge:SetShown(level > 0)
end

function addon.RegisterThreatCueEvents(frame)
    if not LegacyClient() or not UnitThreatSituation then return end
    if addon.db.appearance.legacyResources then
        addon.TryRegisterEvent(frame, "UNIT_THREAT_SITUATION_UPDATE")
    else
        frame:UnregisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    end
end

local function TrackRegen(now)
    if castAt and spentAt and math.abs(castAt - spentAt) <= castMatchWindow then
        regenStarts = now
        castAt, spentAt = nil, nil
        for _, meter in ipairs(meters) do
            if meter:IsVisible() and meter.timer then meter.timer:SetCooldown(now, manaWindow) end
        end
    end
end

local function ReadMana(trackSpend)
    if not UnitPower or not UnitPowerMax then return end
    local current, maximum = UnitPower("player", powerType), UnitPowerMax("player", powerType)
    local readable = not isSecret(current) and type(current) == "number"
    local hasMana = isSecret(maximum) or type(maximum) == "number" and maximum > 0
    if trackSpend and hasMana and readable and lastMana and current < lastMana then
        spentAt = GetTime()
        TrackRegen(spentAt)
    end
    lastMana = readable and hasMana and current or nil
    for _, meter in ipairs(meters) do
        if meter:IsVisible() and meter.mana then
            meter.mana:SetShown(hasMana and (readable or isSecret(current)))
            if meter.mana:IsShown() then
                meter.mana:SetMinMaxValues(0, maximum)
                meter.mana:SetValue(current)
                meter.mana.label:SetFormattedText("Mana  %d / %d", current, maximum)
            end
        end
    end
end

local function ReadThreat()
    if not UnitThreatSituation then return end
    local level = ThreatLevel("player")
    for _, meter in ipairs(meters) do
        if meter:IsVisible() and meter.threat then
            meter.threat:SetText(level >= 2 and "|cffff8383Aggro on you|r" or level == 1 and "|cffffca66High threat|r"
                or "Threat  -")
        end
    end
end

local function CostsMana(spell)
    if not getCost then return true end
    local costs = getCost(spell)
    if isSecret(costs) or type(costs) ~= "table" then return false end
    for _, cost in ipairs(costs) do
        if not isSecret(cost) and type(cost) == "table" and not isSecret(cost.type) and not isSecret(cost.cost)
            and cost.type == powerType and type(cost.cost) == "number" and cost.cost > 0 then
            return true
        end
    end
    return false
end

local function OnResourceEvent(_, event, unit, power, spell)
    if event == "PLAYER_ENTERING_WORLD" then
        lastMana, castAt, spentAt, regenStarts = nil, nil, nil, nil
        for _, meter in ipairs(meters) do
            if meter.timer then meter.timer:SetCooldown(0, 0) end
        end
        ReadMana(false)
        ReadThreat()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ReadThreat()
    elseif isSecret(unit) or unit ~= "player" then
        return
    elseif event == "UNIT_THREAT_SITUATION_UPDATE" then
        ReadThreat()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if not isSecret(spell) and type(spell) == "number" and CostsMana(spell) then
            local now = GetTime()
            castAt = now
            ReadMana(true)
            TrackRegen(now)
        end
    elseif event ~= "UNIT_POWER_UPDATE" or (not isSecret(power) and power == "MANA") then
        ReadMana(event == "UNIT_POWER_UPDATE")
    end
end

local function WatchResources()
    local visible, regen
    for _, meter in ipairs(meters) do
        if meter:IsVisible() then
            visible = true
            if meter.timer then regen = true end
        end
    end
    if resourceEvents.active == visible then return end
    resourceEvents.active = visible
    if not visible then
        resourceEvents:UnregisterAllEvents()
        lastMana, castAt, spentAt = nil, nil, nil
        return
    end
    addon.TryRegisterEvent(resourceEvents, "PLAYER_ENTERING_WORLD")
    if UnitPower and UnitPowerMax then
        for _, event in ipairs({ "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
            addon.TryRegisterPlayerEvent(resourceEvents, event)
        end
        if regen then addon.TryRegisterPlayerEvent(resourceEvents, "UNIT_SPELLCAST_SUCCEEDED") end
    end
    if UnitThreatSituation then
        addon.TryRegisterPlayerEvent(resourceEvents, "UNIT_THREAT_SITUATION_UPDATE")
        addon.TryRegisterEvent(resourceEvents, "PLAYER_REGEN_ENABLED")
    end
end

local function ShowResourceMeter(meter)
    WatchResources()
    if meter.timer then
        local start = regenStarts and GetTime() - regenStarts < manaWindow and regenStarts
        meter.timer:SetCooldown(start or 0, start and manaWindow or 0)
    end
    ReadMana(false)
    ReadThreat()
end

function addon.BuildLegacyResources(panel, hint)
    if not addon.HasLegacyResources() then return end
    if not resourceEvents then
        resourceEvents = CreateFrame("Frame")
        resourceEvents:SetScript("OnEvent", OnResourceEvent)
    end
    local meter = CreateFrame("Frame", nil, panel)
    meter:SetSize(290, 18)
    meter:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -3)
    if UnitPower and UnitPowerMax then
        local bar = CreateFrame("StatusBar", nil, meter)
        bar:SetPoint("TOPLEFT", meter, "TOPLEFT")
        bar:SetSize(164, 18)
        bar:SetStatusBarTexture(addon.solidTexture)
        bar:SetStatusBarColor(0.20, 0.47, 0.76)
        bar.label = addon.Label(bar, "", "GameFontHighlightSmall", 5, -3)
        meter.mana = bar
        if addon.IsRankedClassic() or addon.IsForever() then
            addon.Label(bar, "5s", "GameFontHighlightSmall", 145, -3)
            local timer = CreateFrame("Cooldown", nil, bar, "CooldownFrameTemplate")
            timer:SetSize(17, 17)
            timer:SetPoint("RIGHT", bar, "RIGHT", -1, 0)
            timer:EnableMouse(false)
            meter.timer = timer
        end
    end
    if UnitThreatSituation then
        meter.threat = addon.Label(meter, "", "GameFontHighlightSmall", meter.mana and 174 or 0, -3)
    end
    meters[#meters + 1] = meter
    meter:SetScript("OnShow", ShowResourceMeter)
    meter:SetScript("OnHide", WatchResources)
    if addon.LegacyResourceHeight() == 0 then meter:Hide()
    elseif meter:IsVisible() then ShowResourceMeter(meter) end
end

function addon.RefreshLegacyResources()
    local show = addon.LegacyResourceHeight() ~= 0
    for _, meter in ipairs(meters) do meter:SetShown(show) end
end
