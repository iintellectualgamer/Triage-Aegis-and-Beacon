local _, addon = ...
local Spell = addon.Spell

local methods = { "party", "whisper", "minimap" }
local methodDelay = { party = 30, whisper = 15, minimap = 30 }
local defaultMessage = "Please come closer to the healer"
local legacyDefaultMessage = defaultMessage .. "."

local function WithoutChatPrefix(message)
    if message:sub(1, #addon.chatPrefix) == addon.chatPrefix then
        return message:sub(#addon.chatPrefix + 1)
    end
    return message
end

local switches = {
    { key = "automaticAlerts", default = false, x = 0, y = -19, label = "Enable automatic alerts" },
    { key = "autoChat", default = true, x = 0, y = -39, label = "Send chat announcements" },
    { key = "manualChat", default = false, x = 226, y = -19, label = "Announce on manual click" },
    { key = "autoPing", default = false, x = 0, y = -19, label = "Send native minimap ping", behavior = true },
    { key = "sustained", default = false, x = 0, y = -41, label = "Repeat while out of range", behavior = true },
    { key = "manualPing", default = false, x = 226, y = -19, label = "Add native minimap ping", behavior = true },
    { key = "assist", default = true, x = 226, y = -41, label = "Enable healer shortcut", behavior = true },
    { key = "quiet", default = true, x = 226, y = -63, label = "Use healer mark for shortcut", behavior = true },
}

local routes = {
    { key = "auto", label = "Current group", automatic = true },
    { key = "party", label = "Party (/p)", channel = "PARTY", slash = "/p", automatic = true },
    { key = "raid", label = "Raid (/raid)", channel = "RAID", slash = "/raid", automatic = true },
    { key = "instance", label = "Instance (/i)", channel = "INSTANCE_CHAT", slash = "/i", automatic = true },
    { key = "bg", label = "Battleground (/i)", channel = "INSTANCE_CHAT", slash = "/i", automatic = true },
    { key = "whisper", label = "Whisper (/w)", channel = "WHISPER", slash = "/w", automatic = true },
    { key = "say", label = "Say (/s)", channel = "SAY", slash = "/say", automatic = true, autoDraft = true },
    { key = "yell", label = "Yell (/y)", channel = "YELL", slash = "/y" },
    { key = "guild", label = "Guild (/g)", channel = "GUILD", slash = "/g" },
    { key = "officer", label = "Officer (/o)", channel = "OFFICER", slash = "/o" },
    { key = "warning", label = "Raid warning", channel = "RAID_WARNING", slash = "/rw" },
    { key = "emote", label = "Emote (/em)", channel = "EMOTE", slash = "/em" },
    { key = "numbered", label = "Joined channel", channel = "CHANNEL" },
}
local routeByKey = {}
for _, route in ipairs(routes) do routeByKey[route.key] = route end
local channelOrder = { "auto", "instance", "raid", "party", "whisper", "say", "bg" }
local config, options
local indicators, roster, methodReadyAt = {}, {}, {}
local orderedUnits, firstUnit, totals = {}, 1
local rangeEvents, rosterQueued
local passiveRange = false
local ticker, interval, status, autoButton, manualButton, assistButton, assistKey, pendingAssist
local trackedSpell, isRaid, outcomeUntil, statusText, lastDraft
local watchingChat, watchingPings = false, false
local heardGroupNotices, heardPing = {}, 0
local unitsPerTick = 10
local quietMarker = 4
local coverage, outcome = "Join a group for range checks.", "No alerts requested yet."
local isSecret = issecretvalue or function() return false end

local function MatchRoute(key, automatic)
    local route = routeByKey[key]
    return route and (not automatic or route.automatic) and route or routeByKey.auto
end

local function InMatchmadeGroup()
    return LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
end

local function AvailableRoute(key)
    local inInstance = InMatchmadeGroup()
    if key == "auto" then
        if inInstance then return routeByKey.instance end
        if IsInRaid() then return routeByKey.raid end
        if IsInGroup() then return routeByKey.party end
    elseif key == "instance" then
        if inInstance then return routeByKey.instance end
    elseif key == "bg" then
        if inInstance and IsInInstance then
            local _, kind = IsInInstance()
            if not isSecret(kind) and kind == "pvp" then return routeByKey.bg end
        end
    elseif key == "party" or key == "raid" then
        if not inInstance and IsInGroup() and (not not IsInRaid()) == (key == "raid") then return routeByKey[key] end
    elseif key == "warning" then
        if IsInGroup() then return routeByKey.warning end
    elseif key == "guild" or key == "officer" then
        if IsInGuild and IsInGuild() then return routeByKey[key] end
    else
        return routeByKey[key]
    end
end

local function AutomaticChatRoute()
    if not addon.db.quietGroup and config.automaticAlerts and config.autoChat then
        return AvailableRoute(config.autoRoute)
    end
end

local function AutoEnabled()
    return not addon.db.quietGroup and config.automaticAlerts and (config.autoPing or AutomaticChatRoute())
end

local function SetCoverage(text)
    if text ~= coverage then
        coverage = text
        if options then options.coverage:SetText(text) end
    end
end

local function DisplayStatus(text)
    if status and statusText ~= text then
        statusText = text
        status:SetText(text)
    end
end

local function SetOutcome(text)
    if options then
        options.outcome:SetTextColor(unpack(addon.color.dim))
        if options.outcome:GetText() ~= text then options.outcome:SetText(text) end
    end
    outcome = text
    outcomeUntil = GetTime() + 7
    DisplayStatus(text)
end

local function ReadRange(unit)
    local spellRange
    if trackedSpell then
        local ok, value = pcall(Spell.IsSpellInRange, trackedSpell, unit)
        if ok then
            if not isSecret(value) and type(value) == "boolean" then return value, true end
            spellRange = value
        end
    end
    local inRange, checked
    if UnitInRange then
        inRange, checked = UnitInRange(unit)
        if addon.IsClassic() and not isSecret(inRange) and not isSecret(checked) then
            if inRange == 1 or inRange == 0 then inRange = inRange == 1 end
            if checked == nil and type(inRange) == "boolean" then checked = true end
        end
    end
    if isSecret(spellRange) then
        if not config.spell and not isSecret(checked) and checked
            and not isSecret(inRange) and type(inRange) == "boolean" then
            return inRange, checked, true
        end
        return spellRange, true
    end
    return inRange, checked, true
end

local function DisplayRange(indicator, inRange, checked)
    if not indicator then return end
    if isSecret(checked) or isSecret(inRange) then
        indicator.rangeState = nil
        if indicator.checked.SetAlphaFromBoolean
            and (isSecret(checked) or type(checked) == "boolean")
            and (isSecret(inRange) or type(inRange) == "boolean") then
            indicator.checked:SetAlphaFromBoolean(checked, 1, 0)
            indicator.out:SetAlphaFromBoolean(inRange, 0, 1)
        else
            indicator.checked:SetAlpha(0)
        end
    else
        local state = checked == true and type(inRange) == "boolean" and (inRange and 1 or 2) or 0
        if state == indicator.rangeState then return end
        indicator.rangeState = state
        indicator.checked:SetAlpha(state == 0 and 0 or 1)
        indicator.out:SetAlpha(state == 2 and 1 or 0)
    end
end

local function Eligible(unit)
    local exists = UnitExists(unit)
    if isSecret(exists) or not exists then return false end
    local connected, dead = UnitIsConnected(unit), UnitIsDeadOrGhost(unit)
    if isSecret(connected) or isSecret(dead) or not connected or dead then return false end
    local same = isRaid and UnitIsUnit and UnitIsUnit(unit, "player")
    return not isSecret(same) and not same
end

local function Recipient(unit)
    local name, realm = UnitFullName(unit)
    if isSecret(name) or isSecret(realm) or type(name) ~= "string" or name == "" then return end
    if realm and realm ~= "" then return name .. "-" .. realm:gsub("%s+", "") end
    return name
end

local function MemberIdentity(unit)
    local guid = UnitGUID and UnitGUID(unit)
    if not isSecret(guid) and type(guid) == "string" and guid ~= "" then return guid end
    return Recipient(unit)
end

local function SetDraft(text)
    lastDraft = text
    if options then
        options.draft:SetText(text or "")
        options.draft:SetShown(text ~= nil)
    end
end

local function ChatLocked()
    local locked = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
    return isSecret(locked) or locked == true
end

local function FindJoinedChannel(input)
    if not GetChannelList or input == "" then return end
    local wanted = tonumber(input:match("^/?(%d+)$"))
    local folded = input:lower()
    local joined = { GetChannelList() }
    for i = 1, #joined, 3 do
        local id, name, disabled = joined[i], joined[i + 1], joined[i + 2]
        if not isSecret(id) and not isSecret(name) and not isSecret(disabled) and not disabled
            and type(id) == "number" and (id == wanted or (type(name) == "string" and name:lower() == folded)) then
            return id
        end
    end
end

local function FriendlyTargetName()
    if not UnitIsPlayer or not UnitCanAssist then return end
    local player, friendly = UnitIsPlayer("target"), UnitCanAssist("player", "target")
    local same = UnitIsUnit and UnitIsUnit("target", "player")
    if not isSecret(player) and not isSecret(friendly) and not isSecret(same)
        and player and friendly and not same then
        return Recipient("target")
    end
end

local function MessageWithNames(list, limit)
    local fallback = addon.chatPrefix .. config.message
    if not list or #list == 0 then return fallback end
    local names = table.concat(list, ", ", 1, math.min(3, #list))
    if #list > 3 then names = names .. " and " .. (#list - 3) .. " others" end
    local message = addon.chatPrefix .. names .. ": " .. config.message
    return #message <= limit and message or fallback
end

local function RequestChat(route, recipient, names, automatic)
    if not route then return false, "The selected chat channel is unavailable here." end
    local kind = route.key == "whisper" and "whisper" or "party"
    local now = GetTime()
    local groupNotice = automatic and kind == "party" and not route.autoDraft
    if groupNotice and addon.AutomaticGroupNoticeDelay() > 0 then return false, "Group chat is on cooldown." end
    if now < (methodReadyAt[kind] or 0) then return false, "Chat is on cooldown." end
    local target, slash = nil, route.slash
    if route.key == "whisper" then
        target = recipient
        if not target then return false, "Select a friendly player or set a whisper recipient." end
        slash = slash .. " " .. target
    elseif route.key == "numbered" then
        local channel = FindJoinedChannel(config.manualChannel)
        if not channel then return false, "Join the selected channel before sending." end
        target, slash = tostring(channel), "/" .. channel
    end

    local message = MessageWithNames(names, 240)
    if automatic and route.autoDraft then
        SetDraft(slash .. " " .. MessageWithNames(names, math.min(240, 254 - #slash)))
        methodReadyAt[kind] = now + methodDelay[kind]
        return true, "Say draft ready. Copy it in Range alerts."
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if send and not addon.ChatIsOpen() and not ChatLocked() then
        methodReadyAt[kind] = now + methodDelay[kind]
        local ok, result = pcall(send, message, route.channel, nil, target)
        if ok and not isSecret(result) and result ~= false then
            if groupNotice then addon.RecordAutomaticGroupNotice() end
            return true, route.label .. " requested"
        end
    end
    if not automatic then
        SetDraft(slash .. " " .. MessageWithNames(names, math.min(240, 254 - #slash)))
        return false, "Chat unavailable. Copy the draft in Range alerts."
    end
    methodReadyAt[kind] = now + methodDelay[kind]
    return false, route.label .. " unavailable for addon chat"
end

local function RequestPing()
    local now = GetTime()
    if now < (methodReadyAt.minimap or 0) then return false, "Minimap ping is on cooldown." end
    if addon.ChatIsOpen() then return false, "Minimap ping paused while typing." end
    methodReadyAt.minimap = now + methodDelay.minimap
    local targeting = SpellIsTargeting()
    if isSecret(targeting) or targeting then return false, "Minimap ping paused while targeting." end
    if not ChatLocked() and Minimap and Minimap.PingLocation and Minimap:IsVisible() then
        local ok, result = pcall(Minimap.PingLocation, Minimap, 0, 0)
        if ok and not isSecret(result) and result ~= false then return true, "Minimap ping requested" end
    end
    return false, "WoW did not accept the minimap ping."
end

local function MarkAlert(member, kind, now)
    if member then
        member.sent[kind] = now
        if member.farSince then member.warned[kind] = true end
    end
end


local function ManualAlert(unit, override)
    SetDraft(nil)
    if unit and not Eligible(unit) then SetOutcome("Choose an available group member."); return end
    local results = {}
    local member = unit and roster[unit]
    if not override then
        if addon.FlashMinimapSignal() then tinsert(results, "Local minimap mark shown") end
        if config.manualPing then
            local sent, reason = RequestPing()
            if sent then MarkAlert(member, "minimap", GetTime()) end
            tinsert(results, reason)
        end
    end
    if override or config.manualChat then
        local route = AvailableRoute(override or config.manualRoute)
        local name = unit and Recipient(unit)
        local recipient, names
        if route and route.key == "whisper" then
            if unit then
                recipient = name
            else
                recipient = config.manualRecipient or FriendlyTargetName()
            end
        elseif name then
            names = { name }
        end
        local sent, reason = RequestChat(route, recipient, names, false)
        if sent then MarkAlert(member, route.key == "whisper" and "whisper" or "party", GetTime()) end
        tinsert(results, 1, reason)
    end
    SetOutcome(#results > 0 and table.concat(results, " · ") or "Local minimap mark unavailable.")
end

local function NoticeMenu(owner, unit)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        SetOutcome("Use Settings > Range alerts to choose a route.")
        return
    end
    local identity = MemberIdentity(unit)
    local function SendTo(key)
        if identity and identity == MemberIdentity(unit) then ManualAlert(unit, key)
        else SetOutcome("The group member changed. Choose their current bar.") end
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Ask player to move closer to the healer")
        root:SetScrollMode(255)
        root:CreateButton("Whisper this player", function() SendTo("whisper") end)
        for _, route in ipairs(routes) do
            if route.key ~= "whisper" then
                root:CreateButton("Send in " .. route.label, function() SendTo(route.key) end)
            end
        end
    end)
end

local function Due(member, kind, now)
    return (config.sustained or not member.warned[kind])
        and (not member.sent[kind] or now - member.sent[kind] >= config.repeatSeconds)
end

local function Scan()
    if rosterQueued or not AutoEnabled() then return end
    local now = GetTime()
    local route = AutomaticChatRoute()
    local chatKind = route and (route.key == "whisper" and "whisper" or "party")
    if firstUnit == 1 then totals = { known = 0, far = 0, protected = 0, fallback = 0 } end
    local due
    if (route or config.autoPing) and not addon.ChatIsOpen() then
        if chatKind and now >= (methodReadyAt[chatKind] or 0) and now >= (heardGroupNotices[route.channel] or 0) then
            due = { [chatKind] = {} }
        end
        if config.autoPing and now >= (methodReadyAt.minimap or 0) and now >= heardPing then
            due = due or {}
            due.minimap = {}
        end
    end
    -- Split a large raid across ticks to cap the amount of work per callback.
    local lastUnit = math.min(firstUnit + unitsPerTick - 1, #orderedUnits)
    for index = firstUnit, lastUnit do
        local unit = orderedUnits[index]
        local member = roster[unit]
        local inRange, checked, groupCheck
        if Eligible(unit) then inRange, checked, groupCheck = ReadRange(unit) end
        DisplayRange(indicators[unit], inRange, checked)
        if isSecret(inRange) or isSecret(checked) then
            totals.protected = totals.protected + 1
            member.farSince = nil
        elseif checked == true and type(inRange) == "boolean" then
            totals.known = totals.known + 1
            if groupCheck then totals.fallback = totals.fallback + 1 end
            if inRange then
                if member.farSince or next(member.warned) then wipe(member.warned) end
                member.farSince = nil
            else
                totals.far = totals.far + 1
                member.farSince = member.farSince or now
                if due and now - member.farSince >= config.confirmSeconds then
                    local name = (due.party or due.whisper) and Recipient(unit)
                    if name then member.name = name end
                    for _, kind in ipairs(methods) do
                        if due[kind] and (name or kind == "minimap") and Due(member, kind, now) then
                            tinsert(due[kind], member)
                        end
                    end
                end
            end
        else
            member.farSince = nil
        end
    end

    if due then
        local results = {}
        for _, kind in ipairs(methods) do
            local players = due[kind]
            if players and players[1] then
                local names
                if kind == "party" then
                    names = {}
                    for _, member in ipairs(players) do tinsert(names, member.name) end
                    table.sort(names)
                elseif kind == "whisper" and players[2] then
                    table.sort(players, function(a, b) return (a.sent.whisper or 0) < (b.sent.whisper or 0) end)
                end
                local sent, reason
                if kind == "minimap" then
                    sent, reason = RequestPing()
                    if not sent and addon.FlashMinimapSignal() then
                        sent, reason = true, reason .. " Local mark shown."
                    end
                else
                    sent, reason = RequestChat(route, players[1].name, names, true)
                end
                if sent then
                    for index = 1, kind == "whisper" and 1 or #players do
                        MarkAlert(players[index], kind, now)
                    end
                end
                tinsert(results, reason)
            end
        end
        if #results > 0 then
            local result = table.concat(results, " · ")
            if result ~= outcome or not outcomeUntil or now >= outcomeUntil then SetOutcome(result) end
        end
    end

    if lastUnit < #orderedUnits then
        firstUnit = lastUnit + 1
        return
    end
    firstUnit = 1
    local summary = totals.known .. " checked · " .. totals.far .. " out"
    if totals.protected > 0 then summary = summary .. " · " .. totals.protected .. " restricted" end
    if totals.fallback > 0 then summary = summary .. " · group range fallback" end
    if route then summary = summary .. " · " .. route.label end
    SetCoverage(summary)
    if not outcomeUntil or now >= outcomeUntil then DisplayStatus(summary) end
end

function addon.UpdateRangeReference()
    if not config then return end
    local spell = config.spell and addon.IsRangeReference(config.spell) and config.spell or addon.primaryHeal
    if spell ~= trackedSpell then
        trackedSpell = spell
        firstUnit = 1
        for _, member in pairs(roster) do
            member.farSince = nil
            wipe(member.warned)
        end
    end
end


local function RangeBarsVisible()
    local panel = addon.panel
    local layout = panel.activeLayout
    return panel:IsVisible() and not panel.minimized
        and (layout == "full" or (isRaid and layout == "raid") or (not isRaid and layout == "healing"))
end

local function DisplayGroupRange(unit)
    local indicator = indicators[unit]
    if indicator and indicator.row:IsVisible() then
        local inRange, checked
        if Eligible(unit) then inRange, checked = UnitInRange(unit) end
        DisplayRange(indicator, inRange, checked)
    end
end

function addon.RefreshRangePolling(rosterChanged)
    if not config or not rangeEvents then return end
    local period
    if #orderedUnits > 0 and AutoEnabled() then
        period = #orderedUnits > unitsPerTick and 0.5 or 1
    end
    if interval ~= period then
        if ticker then ticker:Cancel() end
        interval, ticker = period, period and C_Timer.NewTicker(period, Scan) or nil
        firstUnit = 1
        if not interval then
            for unit, member in pairs(roster) do
                member.farSince = nil
                DisplayRange(indicators[unit], nil, false)
            end
        end
    end
    local chatRoute = period and AutomaticChatRoute()
    local listenChat = not not (chatRoute and chatRoute.key ~= "whisper" and not chatRoute.autoDraft)
    if listenChat ~= watchingChat then
        addon.WatchGroupChat(rangeEvents, listenChat)
        watchingChat = listenChat
    end
    local listenPings = period ~= nil and config.autoPing
    if listenPings ~= watchingPings then
        if listenPings then
            watchingPings = addon.TryRegisterEvent(rangeEvents, "MINIMAP_PING")
        else
            rangeEvents:UnregisterEvent("MINIMAP_PING")
            watchingPings = false
        end
    end
    -- The displayed group range can follow game events while reminders are off.
    local wantPassive = not ticker and #orderedUnits > 0 and RangeBarsVisible()
    local wasPassive = passiveRange
    if wantPassive ~= wasPassive then
        if wantPassive then
            wantPassive = addon.TryRegisterEvent(rangeEvents, "UNIT_IN_RANGE_UPDATE")
        else
            rangeEvents:UnregisterEvent("UNIT_IN_RANGE_UPDATE")
        end
    end
    passiveRange = wantPassive
    if wantPassive and (not wasPassive or rosterChanged) then
        for _, unit in ipairs(orderedUnits) do DisplayGroupRange(unit) end
    end
    if not ticker then
        SetCoverage(addon.db.quietGroup and "Quiet Group · Automatic messages and pings paused"
            or config.automaticAlerts and IsInGroup() and not AutoEnabled() and "Auto alerts waiting for an available route."
            or wantPassive and "Auto reminders off · Group range display"
            or IsInGroup() and "Auto reminders off" or "Join a group for range checks.")
        if not outcomeUntil or GetTime() >= outcomeUntil then DisplayStatus(coverage) end
    end
end

local function UpdateRoster()
    rosterQueued = false
    local previous = roster
    roster = {}
    wipe(orderedUnits)
    firstUnit = 1
    isRaid = IsInRaid()
    if IsInGroup() then
        local automatic = AutoEnabled()
        local function AddUnit(unit)
            tinsert(orderedUnits, unit)
            if not automatic then return end
            local identity = MemberIdentity(unit)
            local member = previous[unit]
            if identity and member and member.identity == identity then
                roster[unit] = member
            else
                roster[unit] = { identity = identity, sent = {}, warned = {} }
                DisplayRange(indicators[unit], nil, false)
            end
        end
        if isRaid then
            addon.ForEachRaidMember(AddUnit)
        else
            local count = math.min(GetNumSubgroupMembers and GetNumSubgroupMembers() or 4, 4)
            for index = 1, count do AddUnit("party" .. index) end
        end
    end
    for unit in pairs(previous) do
        if not roster[unit] then DisplayRange(indicators[unit], nil, false) end
    end
    addon.RefreshRangePolling(true)
end

function addon.AttachRangeAlert(row, raid)
    local notify = addon.Button(row, raid and "!" or "Notify", raid and 22 or 59, raid and 18 or 20)
    if raid then
        notify:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -1)
        notify.label:SetFontObject(GameFontHighlight)
        notify.label:SetTextColor(0.78, 0.83, 0.83)
        row.raidNotify = notify
    else
        notify:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    end
    notify:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    notify:SetScript("OnClick", function(owner, button)
        if button == "RightButton" or button == "MiddleButton" then NoticeMenu(owner, row.unit)
        else ManualAlert(row.unit) end
    end)
    addon.Tooltip(notify, "Ask the player to move closer to the healer",
        "Left-click uses your manual alert. Right-click or middle-click to choose a chat channel.")
    if raid then
        local function ClearHighlight() notify.label:SetTextColor(0.78, 0.83, 0.83) end
        notify:HookScript("OnEnter", function() notify.label:SetTextColor(0.94, 0.85, 0.68) end)
        notify:HookScript("OnLeave", ClearHighlight)
        notify:HookScript("OnHide", ClearHighlight)
    end

    local checked = CreateFrame("Frame", nil, row.health)
    checked:SetSize(raid and 19 or 66, raid and 10 or 19)
    if raid then checked:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 2)
    else checked:SetPoint("RIGHT", row, "RIGHT", -65, 0) end
    checked:SetAlpha(0)
    local out = CreateFrame("Frame", nil, checked)
    out:SetAllPoints(checked)
    addon.Label(out, raid and "Far" or "Out of range", nil, raid and 0 or 3, raid and 0 or -5, { 1, 0.58, 0.48 })
    indicators[row.unit] = { checked = checked, out = out, row = row }
end


local function SetAssistAction()
    if InCombatLockdown() then pendingAssist = true; return end
    pendingAssist = false
    local quiet = config.assist and config.quiet
    local nativePing = addon.HasNativePing()
    local enabled = config.assist and (quiet or nativePing) and true or false
    for _, button in ipairs({ assistButton, assistKey }) do
        button:SetAttribute("*type1", enabled and (quiet and "raidtarget" or "macro") or nil)
        button:SetAttribute("*action1", quiet and "set" or nil)
        button:SetAttribute("marker", quiet and quietMarker or nil)
        button:SetAttribute("unit", "player")
        button:SetAttribute("macrotext", enabled and not quiet and "/ping [@player,group] Assist" or nil)
        button:SetEnabled(enabled)
    end
    assistButton.label:SetText(config.quiet and "Mark healer" or (nativePing and "Assist ping" or "Ping unavailable"))
end

local function ShowAlertButtons()
    local quiet = addon.db.quietGroup
    local enabled = config.automaticAlerts and not quiet
    autoButton.label:SetText(quiet and "Auto alerts: Quiet" or enabled and "Auto alerts: On" or "Auto alerts: Off")
    autoButton.label:SetTextColor(unpack(enabled and addon.color.accent or addon.color.text))
    local label = config.manualChat and "Map + chat" or "Manual mark"
    if config.manualPing then label = config.manualChat and "Map + chat + ping" or "Map + ping" end
    manualButton.label:SetText(label)
end

function addon.SetQuietGroup(enabled)
    addon.db.quietGroup = enabled
    ShowAlertButtons()
    UpdateRoster()
    addon.RefreshBuffAnnouncements()
    SetOutcome(enabled and "Quiet Group enabled." or "Quiet Group disabled.")
end

local function ReadSeconds(input, low, high)
    local seconds = tonumber(input)
    if seconds and seconds >= low and seconds <= high then return seconds end
end

local function PlainLine(value, maxLength)
    if type(value) ~= "string" or value:find("%c") then return end
    local trimmed = value:match("^%s*(.-)%s*$")
    if #trimmed <= maxLength then return trimmed end
end

local function KeepManualArgument(frame)
    local key = frame.manualRoute
    if key == "whisper" or key == "numbered" then
        frame.arguments[key] = frame.argument:GetText()
    end
end

local function ShowManualArgument(frame)
    local key = frame.manualRoute
    local required = key == "whisper" or key == "numbered"
    frame.argument:SetShown(required)
    frame.argumentLabel:SetShown(required)
    frame.argumentLabel:SetText(key == "whisper" and "Name or target" or "Name or /number")
    frame.argument:SetText(required and (frame.arguments[key] or "") or "")
    frame.argument:ClearFocus()
end

local function PaintChannels(frame)
    for key, buttons in pairs(frame.channelButtons) do
        for route, button in pairs(buttons) do addon.SelectTab(button, frame[key] == route) end
    end
    local auto = frame.autoRoute
    frame.autoHelp:SetText(auto == "say" and "Auto Say prepares a /say draft."
        or auto == "whisper" and "Whisper alerts one teammate at a time."
        or auto == "bg" and "Battleground uses instance chat (/i)."
        or auto == "auto" and "Uses party, raid, or instance chat."
        or "Waits until the selected channel is available.")
    local route = routeByKey[frame.manualRoute]
    frame.moreChannels.label:SetText(route.automatic and "More channels" or route.label)
    addon.SelectTab(frame.moreChannels, not route.automatic)
end

local function SettingsError(message, input)
    options.showBehavior(input == options.spell or input == options.confirmSeconds or input == options.repeatSeconds)
    options.outcome:SetTextColor(1, 0.56, 0.54, 1)
    options.outcome:SetText(message)
    if input then input:SetFocus() end
end

local function SaveOptions()
    local spell, errorMessage = addon.ReadSpell(options.spell:GetText())
    if spell and not addon.IsRangeReference(spell) then
        errorMessage = "Choose a helpful spell with a casting range and no minimum distance."
    end
    if errorMessage then SettingsError(errorMessage, options.spell); return end
    local confirm = ReadSeconds(options.confirmSeconds:GetText(), 0.5, 15)
    local repeatSeconds = ReadSeconds(options.repeatSeconds:GetText(), 20, 300)
    if not confirm then
        SettingsError("Enter a confirmation time between 0.5 and 15 seconds.", options.confirmSeconds)
        return
    elseif not repeatSeconds then
        SettingsError("Enter a repeat delay between 20 and 300 seconds.", options.repeatSeconds)
        return
    end
    local message = PlainLine(WithoutChatPrefix(options.message:GetText()), 160)
    if not message or message:sub(1, 1) == "/" then
        SettingsError("Enter one line of announcement text up to 160 bytes.", options.message)
        return
    end
    KeepManualArgument(options)
    local recipient = PlainLine(options.arguments.whisper, 65)
    if not recipient or recipient:find("[%s/|]") then
        if options.manualRoute == "whisper" then
            SettingsError("Use a character name or Name-Realm for whispers.", options.argument)
            return
        end
        recipient = config.manualRecipient or ""
    end
    local channel = PlainLine(options.arguments.numbered, 65)
    if not channel or channel:find("|", 1, true) or (channel:sub(1, 1) == "/" and not channel:match("^/%d+$")) then
        if options.manualRoute == "numbered" then
            SettingsError("Enter a joined channel name or its number, such as /2.", options.argument)
            return
        end
        channel = config.manualChannel
    end
    if options.manualRoute == "numbered" and options.boxes.manualChat:GetChecked() and channel == "" then
        SettingsError("Enter the name or number of your joined channel.", options.argument)
        return
    end
    local assist, quiet = config.assist, config.quiet
    for _, switch in ipairs(switches) do config[switch.key] = not not options.boxes[switch.key]:GetChecked() end
    config.spell = spell
    config.autoRoute, config.manualRoute = options.autoRoute, options.manualRoute
    config.message = message ~= "" and message ~= legacyDefaultMessage and message or defaultMessage
    config.manualRecipient = recipient ~= "" and recipient or nil
    config.manualChannel = channel
    config.confirmSeconds, config.repeatSeconds = confirm, repeatSeconds
    ShowAlertButtons()
    if assist ~= config.assist or quiet ~= config.quiet then SetAssistAction() end
    options.argument:ClearFocus()
    options.message:ClearFocus()
    options.spell:ClearFocus()
    options.confirmSeconds:ClearFocus()
    options.repeatSeconds:ClearFocus()
    SetDraft(nil)
    addon.UpdateRangeReference()
    UpdateRoster()
    local confirmation = pendingAssist and "Range alerts saved. Healer shortcut changes apply after combat."
        or ("Range alerts saved. Auto " .. routeByKey[config.autoRoute].label .. " · Manual " .. routeByKey[config.manualRoute].label)
    SetOutcome(confirmation)
    addon.Print(confirmation)
end


local pingSoundCVar = "Sound_EnablePingSounds"

local function PingSoundState()
    local read = (C_CVar and C_CVar.GetCVar) or GetCVar
    if not read then return end
    local ok, state = pcall(read, pingSoundCVar)
    if ok and not isSecret(state) and (state == "0" or state == "1") then return state end
end

local function UpdateSoundButton(button)
    local value = PingSoundState()
    button:SetEnabled(value ~= nil)
    button.label:SetText(value == "1" and "Mute game ping sounds" or value == "0"
        and "Enable game ping sounds" or "Game ping sound unavailable")
end

local function LoadOptions(frame, values)
    for _, switch in ipairs(switches) do
        local value = values[switch.key]
        if value == nil then value = switch.default end
        frame.boxes[switch.key]:SetChecked(value)
    end
    frame.message:SetText(values.message or defaultMessage)
    frame.spell:SetText(values.spell and tostring(values.spell) or "")
    frame.confirmSeconds:SetText(tostring(values.confirmSeconds or 2))
    frame.repeatSeconds:SetText(tostring(values.repeatSeconds or 30))
    frame.autoRoute = MatchRoute(values.autoRoute, true).key
    frame.manualRoute = MatchRoute(values.manualRoute).key
    frame.arguments = { whisper = values.manualRecipient or "", numbered = values.manualChannel or "" }
    ShowManualArgument(frame)
    PaintChannels(frame)
    UpdateSoundButton(frame.pingSound)
    frame.coverage:SetText(coverage)
    frame.outcome:SetText(outcome)
    frame.outcome:SetTextColor(unpack(addon.color.dim))
    SetDraft(lastDraft)
end

local function EditField(frame, width, x, y)
    local edit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    edit:SetSize(width, 22)
    edit:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(100)
    edit:SetScript("OnEnterPressed", SaveOptions)
    edit:SetScript("OnEscapePressed", addon.CloseSettings)
    return edit
end

local function BuildChannelChoices(frame, parent, key, x)
    local automatic = key == "autoRoute"
    local buttons = {}
    frame.channelButtons[key] = buttons
    local function Choose(route)
        if not automatic then KeepManualArgument(frame) end
        frame[key] = route.key
        if not automatic then ShowManualArgument(frame) end
        PaintChannels(frame)
    end
    for index, routeKey in ipairs(channelOrder) do
        local route = routeByKey[routeKey]
        local button = addon.Tab(parent, route.label, 103, 23)
        button:SetPoint("TOPLEFT", parent, "TOPLEFT", x + ((index - 1) % 2) * 109, -66 - math.floor((index - 1) / 2) * 27)
        button:SetScript("OnClick", function() Choose(route) end)
        if routeKey == "bg" then
            addon.Tooltip(button, "Battleground channel", "Uses WoW's instance chat (/i) while in a battleground.")
        elseif routeKey == "say" then
            addon.Tooltip(button, "Say (/s)", automatic and "Prepares a /say draft you can send."
                or "Requests local chat when you click the manual alert.")
        end
        buttons[routeKey] = button
    end
    if automatic then return end
    local more = addon.Tab(parent, "More channels", 103, 23)
    more:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 109, -147)
    frame.moreChannels = more
    more:SetScript("OnClick", function(owner)
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(owner, function(_, root)
                root:CreateTitle("More manual channels")
                for _, route in ipairs(routes) do
                    if not route.automatic then root:CreateButton(route.label, function() Choose(route) end) end
                end
            end)
        else
            local nextRoute
            for index = #routes, 1, -1 do
                local route = routes[index]
                if not route.automatic then
                    if route.key == frame.manualRoute and nextRoute then break end
                    nextRoute = route
                end
            end
            if nextRoute then Choose(nextRoute) end
        end
    end)
end

function addon.BuildRangeSettings(frame)
    options = frame
    frame.boxes = {}
    frame.channelButtons = {}
    addon.Label(frame, "Range alerts", "GameFontHighlightLarge", 0, 0, addon.color.accent)
    frame.coverage = addon.Label(frame, coverage, nil, 0, -28, addon.color.dim)
    local channels = CreateFrame("Frame", nil, frame)
    local behavior = CreateFrame("Frame", nil, frame)
    for _, pane in ipairs({ channels, behavior }) do
        pane:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -47)
        pane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 83)
    end
    local behaviorTab = addon.Tab(frame, "Behavior", 87, 23)
    behaviorTab:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 1)
    local channelsTab = addon.Tab(frame, "Channels", 87, 23)
    channelsTab:SetPoint("RIGHT", behaviorTab, "LEFT", -5, 0)
    frame.showBehavior = function(show)
        if show then
            frame.argument:ClearFocus()
            frame.message:ClearFocus()
        else
            frame.spell:ClearFocus()
            frame.confirmSeconds:ClearFocus()
            frame.repeatSeconds:ClearFocus()
        end
        channels:SetShown(not show)
        behavior:SetShown(show)
        addon.SelectTab(channelsTab, not show)
        addon.SelectTab(behaviorTab, show)
    end
    addon.ShowRangeChannels = function() frame.showBehavior(false) end
    channelsTab:SetScript("OnClick", addon.ShowRangeChannels)
    behaviorTab:SetScript("OnClick", function() frame.showBehavior(true) end)

    local sound = addon.Button(behavior, "", 165, 23)
    frame.pingSound = sound
    sound:SetPoint("TOPLEFT", behavior, "TOPLEFT", 0, -184)
    sound:SetScript("OnClick", function(self)
        local current = PingSoundState()
        local set = (C_CVar and C_CVar.SetCVar) or SetCVar
        if not current or not set then return end
        local requested = current == "1" and "0" or "1"
        pcall(set, pingSoundCVar, requested)
        UpdateSoundButton(self)
        if PingSoundState() == requested then
            SetOutcome(requested == "0" and "Game ping sounds muted on your client." or "Game ping sounds enabled.")
        else
            SetOutcome("Change Enable Ping Sounds in WoW's Audio options.")
        end
    end)
    addon.Tooltip(sound, "Game ping sounds", "Changes WoW's ping audio on your client. The group controls its own audio.")
    addon.Label(channels, "Automatic chat channel", "GameFontHighlight", 0, 0, addon.color.accent)
    addon.Label(channels, "Manual chat channel", "GameFontHighlight", 226, 0, addon.color.accent)
    addon.Label(channels, "Uses the manual button, Notify, or raid !.", nil, 226, -43, addon.color.dim)
    addon.Label(behavior, "Automatic alerts", "GameFontHighlight", 0, 0, addon.color.accent)
    addon.Label(behavior, "Manual alerts and healer shortcut", "GameFontHighlight", 226, 0, addon.color.accent)
    for _, switch in ipairs(switches) do
        local pane = switch.behavior and behavior or channels
        local check = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
        check:SetSize(20, 20)
        check:SetPoint("TOPLEFT", pane, "TOPLEFT", switch.x, switch.y)
        frame.boxes[switch.key] = check
        addon.Label(pane, switch.label, nil, switch.x + 25, switch.y - 4)
    end
    addon.Tooltip(frame.boxes.autoPing, "Automatic native minimap ping",
        "Use Auto alerts to turn reminders on or off. A native ping may be visible to your group.")
    addon.Tooltip(frame.boxes.manualPing, "Manual native minimap ping",
        "Adds a native ping to the local minimap mark on your next manual alert click.")
    BuildChannelChoices(frame, channels, "autoRoute", 0)
    BuildChannelChoices(frame, channels, "manualRoute", 226)
    frame.autoHelp = addon.Label(channels, "", nil, 0, -183, addon.color.dim)
    frame.autoHelp:SetWidth(211)
    frame.autoHelp:SetWordWrap(true)
    frame.autoHelp:SetJustifyH("LEFT")
    frame.argumentLabel = addon.Label(channels, "", nil, 226, -183)
    frame.argument = EditField(channels, 113, 319, -176)
    frame.argument:SetMaxLetters(65)
    addon.Tooltip(frame.argument, "Manual chat recipient", "For Whisper, leave it blank to use your friendly target or the player's own alert button.")
    addon.Label(channels, "Announcement", nil, 0, -217)
    frame.message = EditField(channels, 332, 100, -211)
    frame.message:SetMaxLetters(160)
    addon.Label(behavior, "Range spell", nil, 0, -108)
    frame.spell = EditField(behavior, 332, 100, -102)
    addon.Label(behavior, "Confirm after (s)", nil, 0, -144)
    frame.confirmSeconds = EditField(behavior, 45, 100, -138)
    addon.Label(behavior, "Repeat delay (s)", nil, 226, -144)
    frame.repeatSeconds = EditField(behavior, 45, 332, -138)
    frame.outcome = addon.Label(frame, outcome, nil, 0, -289, addon.color.dim)
    frame.outcome:SetWidth(436)
    frame.outcome:SetHeight(24)
    frame.outcome:SetJustifyH("LEFT")
    frame.outcome:SetWordWrap(true)
    frame.draft = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.draft:SetSize(430, 21)
    frame.draft:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -315)
    frame.draft:SetAutoFocus(false)
    frame.draft:SetMaxLetters(255)
    frame.draft:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    frame.draft:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame.draft:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.draft:Hide()
    addon.Tooltip(frame.draft, "Chat draft", "Click the draft and press Ctrl+C to copy it.")
    local save = addon.Button(frame, "Save alerts", 92, 27)
    save:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
    save:SetScript("OnClick", SaveOptions)
    local reset = addon.Button(frame, "Reset defaults", 102, 26)
    reset:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
    reset:SetScript("OnClick", function() LoadOptions(frame, {}) end)
    frame:SetScript("OnHide", function()
        frame.argument:ClearFocus()
        frame.message:ClearFocus()
        frame.spell:ClearFocus()
        frame.confirmSeconds:ClearFocus()
        frame.repeatSeconds:ClearFocus()
        frame.draft:ClearFocus()
    end)
    frame.showBehavior(false)
    return function() LoadOptions(frame, config) end
end

function addon.BuildRangeAlerts(panel)
    addon.db.rangeAlerts = type(addon.db.rangeAlerts) == "table" and addon.db.rangeAlerts or {}
    config = addon.db.rangeAlerts
    for _, switch in ipairs(switches) do
        if type(config[switch.key]) ~= "boolean" then config[switch.key] = switch.default end
    end
    if not addon.ValidSpellIdentifier(config.spell) then config.spell = nil end
    if config.groupRouteDefaultMigrated ~= true then
        if config.autoRoute == "whisper"
            or (config.autoRoute == nil and config.autoWhisper and not config.autoGroup and not config.instanceAuto) then
            config.autoRoute, config.automaticAlerts = "auto", false
        elseif config.autoRoute == nil and config.instanceAuto and not config.autoGroup then
            config.autoRoute = "instance"
        end
        config.groupRouteDefaultMigrated = true
    end
    config.autoRoute = MatchRoute(config.autoRoute, true).key
    config.manualRoute = MatchRoute(config.manualRoute or config.route).key
    local message = type(config.message) == "string" and PlainLine(WithoutChatPrefix(config.message), 160)
    config.message = message and message ~= "" and message ~= legacyDefaultMessage
        and message:sub(1, 1) ~= "/" and message or defaultMessage
    local recipient = PlainLine(config.manualRecipient, 65)
    config.manualRecipient = recipient and recipient ~= "" and not recipient:find("[%s/|]") and recipient or nil
    config.manualChannel = PlainLine(config.manualChannel, 65) or ""
    config.confirmSeconds = ReadSeconds(config.confirmSeconds, 0.5, 15) or 2
    config.repeatSeconds = ReadSeconds(config.repeatSeconds, 20, 300) or 30

    status = addon.Label(panel, coverage, nil, addon.inset, -104, addon.color.dim)
    status:SetWidth(addon.contentWidth)
    status:SetWordWrap(false)
    status:SetJustifyH("LEFT")
    assistButton = addon.Button(panel, "Assist ping", 88, 23, "SecureActionButtonTemplate")
    assistButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -addon.inset, -47)
    addon.Tooltip(assistButton, "Signal your position", function()
        if assistButton:GetAttribute("*type1") == "raidtarget" then return "Mark yourself with a green triangle." end
        return "Request WoW's Assist ping on your character."
    end)
    assistKey = addon.CreateBindingButton("Assist", "Healer mark or Assist ping")
    for _, button in ipairs({ assistButton, assistKey }) do
        button:RegisterForClicks("LeftButtonUp")
        button:SetAttribute("useOnKeyDown", false)
    end

    local ping = addon.Button(panel, "Ping target", 84, 22, "SecureActionButtonTemplate")
    ping:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -addon.inset, -77)
    if addon.HasNativePing() then
        ping:SetAttribute("*type1", "macro")
        ping:SetAttribute("macrotext", "/ping [@target,group,help,nodead] Assist")
        addon.Tooltip(ping, "Ping your current friendly target",
            "Select a teammate, then click for WoW's Assist ping. Your game ping audio setting applies.")
    else
        ping.label:SetText("Ping unavailable")
        ping:SetEnabled(false)
        addon.Tooltip(ping, "Assist ping unavailable", "Minimap pings can still be used where the game allows them.")
    end
    autoButton = addon.Button(panel, "", 110, 22)
    autoButton:SetPoint("TOPLEFT", panel, "TOPLEFT", addon.inset, -77)
    autoButton:SetScript("OnClick", function()
        if not config.automaticAlerts and not (config.autoChat or config.autoPing) then
            SetOutcome("Set an automatic chat or ping action in Range alerts.")
            return
        end
        config.automaticAlerts = not config.automaticAlerts
        if options then options.boxes.automaticAlerts:SetChecked(config.automaticAlerts) end
        ShowAlertButtons()
        UpdateRoster()
        local route = AutomaticChatRoute()
        SetOutcome(addon.db.quietGroup and "Quiet Group is active. Change it in All heals."
            or config.automaticAlerts and (route and ("Auto chat: " .. route.label)
            or "Automatic alerts enabled. Check the Auto channel in Range alerts.") or "Automatic alerts off")
    end)
    addon.Tooltip(autoButton, "Automatic range alerts", function()
        local message = "Toggle the automatic actions selected in Alert settings."
        if config.autoChat then
            local route = AutomaticChatRoute() or MatchRoute(config.autoRoute, true)
            return message .. "\nAuto channel: " .. route.label
        end
        return message
    end)
    manualButton = addon.Button(panel, "", 113, 22)
    manualButton:SetPoint("LEFT", autoButton, "RIGHT", 5, 0)
    manualButton:SetScript("OnClick", function() ManualAlert() end)
    addon.Tooltip(manualButton, "Manual alert", function()
        local note = "Shows a local minimap mark and uses your enabled manual alert actions."
        return config.manualChat and (note .. "\nManual channel  " .. routeByKey[config.manualRoute].label) or note
    end)
    local settings = addon.Button(panel, "Alert settings", 101, 22)
    settings:SetPoint("LEFT", manualButton, "RIGHT", 5, 0)
    settings:SetScript("OnClick", addon.OpenRangeOptions)
    ShowAlertButtons()
    SetAssistAction()
    addon.UpdateRangeReference()

    rangeEvents = CreateFrame("Frame")
    rangeEvents:RegisterEvent("GROUP_ROSTER_UPDATE")
    rangeEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
    rangeEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
    rangeEvents:SetScript("OnEvent", function(_, event, unit, inRange)
        local channel = addon.GroupChatEvents[event]
        if channel then
            local route = AutomaticChatRoute()
            if not route or route.channel ~= channel or isSecret(unit) or type(unit) ~= "string" then return end
            local suffix = ": " .. config.message
            unit = WithoutChatPrefix(unit)
            if config.message == defaultMessage and unit:sub(-1) == "." then unit = unit:sub(1, -2) end
            if unit == config.message or unit:sub(-#suffix) == suffix then
                heardGroupNotices[channel] = GetTime() + 15
            end
        elseif event == "MINIMAP_PING" then
            if isSecret(unit) or type(unit) ~= "string" or unit == "player" then return end
            local same = UnitIsUnit and UnitIsUnit(unit, "player")
            if not isSecret(same) and not same then heardPing = GetTime() + 8 end
        elseif event == "UNIT_IN_RANGE_UPDATE" then
            if rosterQueued or isSecret(unit) then return end
            local indicator = indicators[unit]
            if indicator and indicator.row:IsVisible() and Eligible(unit) then
                DisplayRange(indicator, inRange, true)
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            if pendingAssist and not InCombatLockdown() then
                SetAssistAction()
                local confirmation = "Saved healer shortcut is active."
                SetOutcome(confirmation)
                addon.Print(confirmation)
            end
        elseif not rosterQueued then
            rosterQueued = true
            C_Timer.After(0, function()
                if rosterQueued then UpdateRoster() end
            end)
        end
    end)
    UpdateRoster()
end
