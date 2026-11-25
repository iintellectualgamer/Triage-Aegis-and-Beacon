local _, addon = ...
local Spell = addon.Spell

local buffs = {
    { key = "intellect", label = "Intellect", class = "MAGE", retail = { 1459 },
        forever = { 1459, 1460, 1461, 10156, 10157, 23028 } },
    { key = "fortitude", label = "Fortitude", class = "PRIEST", retail = { 21562 },
        forever = { 1243, 1244, 1245, 2791, 10937, 10938, 21562, 21564 } },
    { key = "wild", label = "Mark of the Wild", class = "DRUID", retail = { 1126 },
        forever = { 1126, 5232, 6756, 5234, 8907, 9884, 9885, 21849, 21850 } },
    { key = "shout", label = "Battle Shout", class = "WARRIOR", retail = { 6673 },
        forever = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 } },
    { key = "skyfury", label = "Skyfury", class = "SHAMAN", retail = { 462854 } },
    { key = "bronze", label = "Blessing of the Bronze", class = "EVOKER", provider = { 364342 }, nameID = 364342,
        retail = { 364342, 381732, 381741, 381746, 381748, 381749, 381750, 381751, 381752, 381753, 381754, 381756, 381757, 381758 } },
    { key = "devotion", label = "Devotion Aura", class = "PALADIN", retail = { 465 } },
    { key = "kings", label = "Blessing of Kings", class = "PALADIN", forever = { 20217, 25898 } },
}
local classicBuffs = {
    intellect = { 1459, 1460, 1461, 10156, 10157, 23028, 27126, 27127, 42995, 43002, 61024, 61316 },
    fortitude = { 1243, 1244, 1245, 2791, 10937, 10938, 21562, 21564, 25389, 25392, 48161, 48162 },
    wild = { 1126, 5232, 6756, 5234, 8907, 9884, 9885, 21849, 21850, 26990, 26991, 48469, 48470 },
    shout = { 6673, 5242, 6192, 11549, 11550, 11551, 25289, 2048, 47436 },
    kings = { 20217, 25898 },
}
local destinations = {
    { key = "group", label = "Current group" },
    { key = "party", label = "Party", prefix = "/p " },
    { key = "raid", label = "Raid", prefix = "/raid " },
    { key = "instance", label = "Instance / battleground", prefix = "/i " },
    { key = "warning", label = "Raid warning", prefix = "/rw " },
    { key = "say", label = "Say", prefix = "/s " },
    { key = "yell", label = "Yell", prefix = "/y " },
    { key = "guild", label = "Guild", prefix = "/g " },
    { key = "officer", label = "Officer", prefix = "/o " },
    { key = "emote", label = "Emote", prefix = "/e " },
    { key = "whisper", label = "Whisper", target = "Player name" },
    { key = "channel", label = "Numbered channel", target = "Channel number" },
}
local isSecret = issecretvalue or function() return false end
local buffHeading = addon.chatPrefix .. "Missing buffs"
local buffNoticePrefix = buffHeading .. " / "
local config, events, startTimer, page, groupContext, groupGUID, pendingStart
local trackedBuffs = {}
local watchingChat = false
local attempts, nextAnnouncement = 0, 0

local function Destination(key)
    for _, item in ipairs(destinations) do
        if item.key == key then return item end
    end
    return destinations[1]
end

local function ActiveGroup()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT", "/i " end
    if IsInRaid() then return "RAID", "/raid " end
    if IsInGroup() then return "PARTY", "/p " end
end

local function ReadableTrue(value)
    return not isSecret(value) and value == true
end

local function CoverageUnits()
    local units, found, unavailable = {}, 0, 0
    local function Inspect(unit)
        found = found + 1
        local dead = UnitIsDeadOrGhost(unit)
        if not ReadableTrue(UnitIsConnected(unit)) or not ReadableTrue(UnitIsVisible(unit))
            or isSecret(dead) or dead then
            unavailable = unavailable + 1
            return
        end
        local _, class = UnitClass(unit)
        local name = UnitName(unit)
        tinsert(units, {
            token = unit,
            name = not isSecret(name) and type(name) == "string" and name or nil,
            class = not isSecret(class) and class or nil,
            own = unit == "player" or (UnitIsUnit and ReadableTrue(UnitIsUnit(unit, "player"))),
        })
    end
    if IsInRaid() then
        addon.ForEachRaidMember(Inspect)
    else
        if ReadableTrue(UnitExists("player")) then Inspect("player") end
        for index = 1, 4 do
            local unit = "party" .. index
            if ReadableTrue(UnitExists(unit)) then Inspect(unit) end
        end
    end
    local expected = GetNumGroupMembers()
    if not isSecret(expected) and type(expected) == "number" then
        unavailable = unavailable + math.max(0, expected - found)
    end
    return units, unavailable
end

local function HasProvider(units, buff, spells)
    for _, unit in ipairs(units) do
        if unit.class == buff.class then
            if not unit.own then return true end
            for _, id in ipairs(spells) do
                if addon.KnowsSpell(id) then return true end
            end
        end
    end
    return false
end

local function ReadAura(lookup, ...)
    local ok, aura = pcall(lookup, ...)
    if not ok or isSecret(aura) or (aura and isSecret(aura.spellId)) then return nil end
    return aura ~= nil
end

local function HasLegacyBuff(unit, spells)
    local seen = unit.legacyBuffs or {}
    unit.legacyBuffs = seen
    for spell in pairs(spells) do
        if seen[spell] then return true end
    end
    if unit.legacyUnavailable then return nil end
    for index = unit.nextLegacyBuff or 1, 40 do
        local name, id
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit.token, index, "HELPFUL")
            if not ok or isSecret(aura) then unit.legacyUnavailable = true; return nil end
            if not aura then unit.nextLegacyBuff = 41; return false end
            name, id = aura.name, aura.spellId
        else
            local ok, auraName, _, _, _, _, _, _, _, _, auraID = pcall(UnitBuff, unit.token, index)
            if not ok then unit.legacyUnavailable = true; return nil end
            name, id = auraName, auraID
        end
        if isSecret(name) or isSecret(id) then unit.legacyUnavailable = true; return nil end
        if not name then unit.nextLegacyBuff = 41; return false end
        unit.nextLegacyBuff = index + 1
        seen[name] = true
        if id then seen[id] = true end
        if spells[id] or spells[name] then return true end
    end
    return false
end

local function HasBuff(unit, buff, auraName)
    if auraName then return ReadAura(C_UnitAuras.GetAuraDataBySpellName, unit.token, auraName, "HELPFUL") end
    if not (C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID) then
        return HasLegacyBuff(unit, buff.legacyAuras)
    end
    local spells = buff.spells
    local unknown = false
    for _, id in ipairs(spells) do
        local present = ReadAura(C_UnitAuras.GetUnitAuraBySpellID, unit.token, id)
        if present then return true end
        if present == nil then unknown = true end
    end
    if not unknown then return false end
end

local function ScanCoverage(requireTeammate)
    if InCombatLockdown() then return nil, "Buff coverage is paused during combat." end
    if not (C_UnitAuras and (C_UnitAuras.GetUnitAuraBySpellID or C_UnitAuras.GetAuraDataByIndex))
        and not UnitBuff then
        return nil, "Buff coverage is unavailable on this client."
    end
    local units, unavailable = CoverageUnits()
    if #units == 0 then return nil, "No visible group members are available to check." end
    if requireTeammate and #units == 1 and units[1].own then return end
    local report, uncertain = {}, {}
    for _, buff in ipairs(trackedBuffs) do
        local details = { missing = 0, names = {}, checked = 0 }
        local spells = buff.spells
        report[buff.key] = details
        if not config.tracked[buff.key] then
            details.state = "Tracking off"
        elseif not HasProvider(units, buff, buff.provider or spells) then
            details.state = "No available group provider"
        else
            local auraName = buff.nameID and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName and Spell.GetSpellName(buff.nameID)
            for _, unit in ipairs(units) do
                local present = HasBuff(unit, buff, auraName)
                if present == nil then
                    uncertain[unit.token] = true
                else
                    details.checked = details.checked + 1
                    if not present then
                        details.missing = details.missing + 1
                        if unit.name then tinsert(details.names, unit.name) end
                    end
                end
            end
        end
    end
    local unchecked = unavailable
    for _ in pairs(uncertain) do unchecked = unchecked + 1 end
    local message = unchecked > 0 and (unchecked .. " members could not be checked fully. Counts show verified results.")
        or ("Coverage check complete for " .. #units .. " members.")
    return report, message, unchecked
end

local function Announcement(report, unchecked, limit)
    local parts, examples = { buffHeading }, {}
    for _, buff in ipairs(trackedBuffs) do
        local detail = report[buff.key]
        if detail.missing > 0 then
            tinsert(parts, " / " .. buff.label .. " " .. detail.missing)
            if #detail.names > 0 then
                table.sort(detail.names)
                local count = math.min(2, #detail.names)
                examples[#parts] = " (" .. table.concat(detail.names, ", ", 1, count)
                    .. (detail.missing > count and " and others)" or ")")
            end
        end
    end
    if #parts == 1 then return end
    if unchecked > 0 then tinsert(parts, " / " .. unchecked .. " not fully checked") end
    local budget = limit - #table.concat(parts)
    if budget < 0 then return nil, "Choose a shorter chat destination to fit all buff counts." end
    for index = 2, #parts do
        local sample = examples[index]
        if sample and #sample <= budget then
            parts[index] = parts[index] .. sample
            budget = budget - #sample
        end
    end
    return table.concat(parts)
end

local function ActiveContext()
    local channel = ActiveGroup()
    if not channel then return end
    if GetInstanceInfo then
        local _, kind, difficulty, _, _, _, id = GetInstanceInfo()
        if not isSecret(kind) and not isSecret(difficulty) and not isSecret(id) and type(kind) == "string"
            and kind ~= "none" and type(difficulty) == "number" and type(id) == "number" then
            return channel .. "/" .. kind .. "/" .. id .. "/" .. difficulty, channel
        end
    end
    return channel, channel
end

local function TryAnnouncement(channel, finalAttempt)
    if addon.ChatIsOpen() then return false end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    local locked = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
    if not send or isSecret(locked) or locked then return false end
    local report, _, unchecked = ScanCoverage(true)
    if not report or (unchecked > 0 and not finalAttempt) then return false end
    local message = Announcement(report, unchecked, 235)
    if not message then return unchecked == 0 end
    local ok, result = pcall(send, message, channel)
    if ok and not isSecret(result) and result ~= false then
        nextAnnouncement = GetTime() + 30
        addon.RecordAutomaticGroupNotice()
        return true
    end
    return false
end

local function CancelStart()
    if startTimer then startTimer:Cancel(); startTimer = nil end
end

local function StartDelay()
    local guid = UnitGUID and UnitGUID("player")
    local offset = not isSecret(guid) and type(guid) == "string" and tonumber(guid:sub(-4), 16)
    return 4 + (offset and (offset % 17) / 8 or math.random() * 2)
end

local function RefreshStart()
    local context = not addon.db.quietGroup and config.announceAtStart and ActiveContext() or nil
    if groupContext ~= context then
        CancelStart()
        groupContext = context
        pendingStart, attempts = context ~= nil, 0
    end
    local listen = pendingStart == true
    if listen ~= watchingChat then
        addon.WatchGroupChat(events, listen)
        watchingChat = listen
    end
    if InCombatLockdown() then CancelStart(); return end
    if pendingStart and not startTimer then
        local delay = math.max(attempts == 0 and StartDelay() or 6, nextAnnouncement - GetTime(),
            addon.AutomaticGroupNoticeDelay())
        startTimer = C_Timer.NewTimer(delay, function()
            startTimer = nil
            local current, channel = ActiveContext()
            if current == groupContext and channel and config.announceAtStart and not addon.db.quietGroup
                and not InCombatLockdown() and addon.AutomaticGroupNoticeDelay() == 0 then
                attempts = attempts + 1
                if TryAnnouncement(channel, attempts >= 3) or attempts >= 3 then pendingStart = false end
            end
            RefreshStart()
        end)
    end
end

function addon.RefreshBuffAnnouncements()
    RefreshStart()
end

local function DisplayReport()
    local report, message, unchecked = ScanCoverage()
    page.message:SetText(message)
    for _, buff in ipairs(trackedBuffs) do
        local detail = report and report[buff.key]
        local text = "-"
        if detail then
            if detail.state then text = detail.state
            elseif detail.checked == 0 then text = "Aura data unavailable"
            elseif detail.missing == 0 then text = detail.checked .. " covered"
            else text = detail.missing .. " missing of " .. detail.checked .. " checked"
            end
        end
        page.results[buff.key]:SetText(text)
    end
    return report, unchecked
end

local function DraftAnnouncement()
    local report, unchecked = DisplayReport()
    if not report then return end
    local choice = page.destination
    local prefix = choice.prefix
    local target = page.target:GetText():match("^%s*(.-)%s*$")
    if choice.key == "group" then
        local _, slash = ActiveGroup()
        prefix = slash
    elseif choice.key == "whisper" and target ~= "" and not target:find("[%s/|]") then
        prefix = "/w " .. target .. " "
    elseif choice.key == "channel" and target:match("^[1-9]%d?$") then
        prefix = "/" .. target .. " "
    end
    if not prefix then page.message:SetText("Choose a group or enter a valid destination."); return end
    local text, reason = Announcement(report, unchecked, math.min(235, 255 - #prefix))
    if not text then
        page.message:SetText(reason or "No verified missing buffs to announce.")
        return
    end

    page.draft:SetText(prefix .. text)
    page.message:SetText("Copy the draft below, then paste it into WoW chat.")
end

function addon.InitializeBuffCoverage()
    addon.db.buffCoverage = type(addon.db.buffCoverage) == "table" and addon.db.buffCoverage or {}
    config = addon.db.buffCoverage
    config.announceAtStart = config.announceAtStart == true
    config.tracked = type(config.tracked) == "table" and config.tracked or {}
    local client = addon.IsForever() and "forever" or (addon.IsClassic() and "classic" or "retail")
    for _, buff in ipairs(buffs) do
        buff.spells = client == "classic" and classicBuffs[buff.key] or buff[client]
        if buff.spells then
            buff.legacyAuras = {}
            for _, id in ipairs(buff.spells) do
                buff.legacyAuras[id] = true
                local name = Spell.GetSpellName(id)
                if name then buff.legacyAuras[name] = true end
            end
            tinsert(trackedBuffs, buff)
            if type(config.tracked[buff.key]) ~= "boolean" then config.tracked[buff.key] = true end
        end
    end
    config.destination = Destination(config.destination).key
    config.target = type(config.target) == "string" and config.target or ""
    events = CreateFrame("Frame")
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "GROUP_JOINED", "PLAYER_ENTERING_WORLD",
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        addon.TryRegisterEvent(events, event)
    end
    events:SetScript("OnEvent", function(_, event, category, guid)
        if not config.announceAtStart then return end
        local chatChannel = addon.GroupChatEvents[event]
        if chatChannel then
            local context, channel = ActiveContext()
            if pendingStart and context == groupContext and chatChannel == channel and not isSecret(category)
                and type(category) == "string" and (category:sub(1, #buffNoticePrefix) == buffNoticePrefix
                    or category:find("^Triage buff check / ")) then
                pendingStart = false
                CancelStart()
            end
        elseif event == "GROUP_JOINED" and not isSecret(category) and not isSecret(guid) and type(guid) == "string" then
            local instance = ActiveGroup() == "INSTANCE_CHAT"
            if (category == LE_PARTY_CATEGORY_INSTANCE) == instance and guid ~= groupGUID then
                CancelStart()
                groupGUID, groupContext, pendingStart = guid, nil, false
            end
        end
        RefreshStart()
    end)
    RefreshStart()
end

function addon.BuildBuffSettings(frame)
    page = frame
    page.results = {}
    local checks = {}
    addon.Label(page, "Buff coverage", "GameFontHighlightLarge", 0, 0, addon.color.accent)
    addon.Label(page, "Check the full party or raid roster for available group buffs.", nil, 0, -28, addon.color.dim)
    for index, buff in ipairs(trackedBuffs) do
        local x, y = ((index - 1) % 2) * 223, -51 - math.floor((index - 1) / 2) * 35
        local check = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
        check:SetSize(22, 22)
        check:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
        addon.Label(page, buff.label, "GameFontHighlight", x + 25, y - 2, addon.color.accent)
        checks[buff.key] = check
        page.results[buff.key] = addon.Label(page, "-", nil, x + 25, y - 17, addon.color.dim)
    end
    local automatic = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    automatic:SetSize(24, 24)
    automatic:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -199)
    page.announceAtStart = automatic
    addon.Label(page, "Announce missing buffs when a group or instance starts", nil, 29, -204)
    addon.Label(page, "Draft destination", nil, 0, -240, addon.color.dim)
    local picker = addon.Button(page, "", 160, 26)
    picker:SetPoint("TOPLEFT", page, "TOPLEFT", 103, -232)
    local target = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    target:SetSize(160, 26)
    target:SetPoint("LEFT", picker, "RIGHT", 12, 0)
    target:SetAutoFocus(false)
    target:SetMaxLetters(60)
    target:SetScript("OnEscapePressed", addon.CloseSettings)
    page.target = target
    local targetLabel = addon.Label(page, "", nil, 276, -260, addon.color.dim)
    local function Pick(choice)
        page.destination = choice
        picker.label:SetText(choice.label)
        target:SetShown(choice.target ~= nil)
        targetLabel:SetText(choice.target or "")
    end
    if MenuUtil and MenuUtil.CreateContextMenu then
        picker:SetScript("OnClick", function(owner)
            MenuUtil.CreateContextMenu(owner, function(_, root)
                root:CreateTitle("Prepare chat announcement")
                for _, choice in ipairs(destinations) do
                    root:CreateButton(choice.label, function()
                        if page.destination ~= choice then target:SetText("") end
                        Pick(choice)
                    end)
                end
            end)
        end)
    else
        picker:SetEnabled(false)
    end
    page.message = addon.Label(page, "", nil, 0, -276, addon.color.dim)
    local field = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    field:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -306)
    field:SetSize(433, 22)
    field:SetAutoFocus(false)
    field:SetMaxLetters(255)
    field:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    field:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    page.draft = field
    page.message:SetWidth(442)
    page.message:SetWordWrap(true)
    page.message:SetJustifyH("LEFT")
    local scan = addon.Button(page, "Scan now", 84, 27)
    scan:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT")
    scan:SetScript("OnClick", DisplayReport)
    local draft = addon.Button(page, "Draft announcement", 134, 27)
    draft:SetPoint("LEFT", scan, "RIGHT", 6, 0)
    draft:SetScript("OnClick", DraftAnnouncement)
    local save = addon.Button(page, "Save preferences", 115, 27)
    save:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT")
    save:SetScript("OnClick", function()
        config.announceAtStart = not not automatic:GetChecked()
        config.destination = page.destination.key
        config.target = target:GetText()
        target:ClearFocus()
        for key, check in pairs(checks) do config.tracked[key] = not not check:GetChecked() end
        RefreshStart()
        DisplayReport()
        local confirmation = "Buff coverage preferences saved."
        page.message:SetText(confirmation .. " " .. page.message:GetText())
        addon.Print(confirmation)
    end)
    page:SetScript("OnHide", function() target:ClearFocus(); field:ClearFocus() end)
    return function()
        for key, check in pairs(checks) do check:SetChecked(config.tracked[key]) end
        automatic:SetChecked(config.announceAtStart)
        target:SetText(config.target)
        Pick(Destination(config.destination))
        field:SetText("")
        page.message:SetText("Use Scan now to check group buffs.")
    end
end
