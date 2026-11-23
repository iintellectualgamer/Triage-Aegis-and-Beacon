local addonName, addon = ...

if addonName ~= "TriageAegisBeacon" then return end

local legacyAddon = "VigilSigil"
addon.title = "Triage - Aegis & Beacon"
addon.chatPrefix = "[" .. addon.title .. "] "
addon.creator = {
    name = "iintellectualgamer",
    email = "iintellectualgamer@gmail.com",
    characters = "Wissegmini-Kil'jaeden & Wwiisseegemi-Tichondrius",
}
addon.width = 456
addon.inset = 16
addon.contentWidth = addon.width - addon.inset * 2
addon.raidWidth = 553
addon.raidGroupLimit = 8
addon.raidGroupSize = 5
addon.raidMemberLimit = addon.raidGroupLimit * addon.raidGroupSize

function addon.ForEachRaidMember(visit)
    for index = 1, addon.raidMemberLimit do
        local unit = "raid" .. index
        local exists = UnitExists(unit)
        if not (issecretvalue and issecretvalue(exists)) and exists then visit(unit, index) end
    end
end

addon.solidTexture = "Interface\\Buttons\\WHITE8X8"
addon.color = {
    panel = { 0.051, 0.098, 0.118, 0.98 },
    header = { 0.082, 0.145, 0.165, 1 },
    border = { 0.19, 0.32, 0.35, 1 },
    button = { 0.10, 0.19, 0.22, 1 },
    selected = { 0.17, 0.31, 0.32, 1 },
    accent = { 0.96, 0.79, 0.46, 1 },
    dim = { 0.70, 0.79, 0.81, 1 },
    text = { 0.92, 0.96, 0.96, 1 },
}
addon.GroupChatEvents = {
    CHAT_MSG_PARTY = "PARTY",
    CHAT_MSG_PARTY_LEADER = "PARTY",
    CHAT_MSG_RAID = "RAID",
    CHAT_MSG_RAID_LEADER = "RAID",
    CHAT_MSG_INSTANCE_CHAT = "INSTANCE_CHAT",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "INSTANCE_CHAT",
}

function addon.WatchGroupChat(frame, enabled)
    for event in pairs(addon.GroupChatEvents) do
        if enabled then
            addon.TryRegisterEvent(frame, event)
        else
            frame:UnregisterEvent(event)
        end
    end
end

function addon.Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cfff5c975" .. addon.title .. "|r " .. message)
end

function addon.ReleaseLabel()
    local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = metadata and metadata(addonName, "Version") or "0.1.1"
    local build = metadata and metadata(addonName, "X-Build") or "Test 17"
    return version .. " / " .. build
end

local function PrintLoadCredit()
    if addon.db.showLoadCredits == false then return end
    local creator = addon.creator
    addon.Print(addon.ReleaseLabel() .. " Loaded (" .. creator.email .. " || Twitch & YouTube:  "
        .. creator.name .. " || " .. creator.characters .. ").  |cffa5dfd9/triage credits|r")
end

function addon.ChatIsOpen()
    local active = ChatFrameUtil and ChatFrameUtil.GetActiveWindow
    if active then return not not active() end
    return ChatEdit_GetActiveWindow and not not ChatEdit_GetActiveWindow() or false
end

function addon.CanEdit()
    if InCombatLockdown() then
        addon.Print("This control is available when combat ends.")
        return false
    end
    return true
end

function addon.StylePanel(frame)
    frame:SetBackdrop({
        bgFile = addon.solidTexture,
        edgeFile = addon.solidTexture,
        edgeSize = 1,
    })
    frame:SetBackdropColor(unpack(addon.color.panel))
    frame:SetBackdropBorderColor(unpack(addon.color.border))
end

function addon.Label(parent, text, font, x, y, color)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetText(text)
    if color then
        label:SetTextColor(unpack(color))
    end
    return label
end

function addon.Button(parent, text, width, height, template)
    local button = CreateFrame("Button", nil, parent, template)
    button:SetSize(width, height)

    local base = button:CreateTexture(nil, "BACKGROUND")
    base:SetAllPoints()
    base:SetColorTexture(unpack(addon.color.button))
    button.surface = base

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(0.68, 0.91, 0.89, 0.14)
    button:SetHighlightTexture(highlight)

    if text then
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("CENTER")
        label:SetText(text)
        button.label = label
    end

    if template then
        button:RegisterForClicks("AnyDown", "AnyUp")
    end
    return button
end

function addon.Tab(parent, text, width, height, side, template)
    local tab = addon.Button(parent, text, width, height, template)
    local edge = tab:CreateTexture(nil, "ARTWORK")
    edge:SetColorTexture(unpack(addon.color.accent))
    if side then
        edge:SetPoint("TOPLEFT")
        edge:SetPoint("BOTTOMLEFT")
        edge:SetWidth(3)
        tab.label:ClearAllPoints()
        tab.label:SetPoint("LEFT", tab, "LEFT", 13, 0)
    else
        edge:SetPoint("BOTTOMLEFT")
        edge:SetPoint("BOTTOMRIGHT")
        edge:SetHeight(2)
    end
    tab.edge = edge
    addon.SelectTab(tab, false)
    return tab
end

function addon.SelectTab(tab, selected)
    tab.edge:SetShown(selected)
    tab.surface:SetColorTexture(unpack(selected and addon.color.selected or addon.color.button))
    tab.label:SetTextColor(unpack(selected and addon.color.accent or addon.color.text))
end

function addon.HeaderBand(frame, height)
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    background:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    background:SetHeight(height)
    background:SetColorTexture(unpack(addon.color.header))
end

function addon.CreateBindingButton(action, label)
    local name = "TriageBeaconKey" .. action
    _G["BINDING_NAME_CLICK " .. name .. ":LeftButton"] = label
    local button = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyDown", "AnyUp")
    return button
end

function addon.OpenKeybindings()
    if not addon.CanEdit() then
        return
    end
    local category = Settings and (Settings.KEYBINDINGS_CATEGORY_ID or KEYBINDINGS_CATEGORY_ID)
    if category and Settings.OpenToCategory then
        Settings.OpenToCategory(category)
    else
        addon.Print("Choose Options > Keybindings and look for " .. addon.title .. ".")
    end
end

function addon.ShowHealingTooltips()
    return not InCombatLockdown() or addon.db.appearance.combatTooltips
end

function addon.ClearHealingTooltip()
    if addon.db.appearance.combatTooltips or not GameTooltip.GetOwner then return end
    local owner = GameTooltip:GetOwner()
    if owner and owner.triageHealingTooltip then GameTooltip:Hide() end
end

function addon.Tooltip(frame, title, detail, canShow)
    if canShow then frame.triageHealingTooltip = true end
    frame:SetScript("OnEnter", function(self)
        if canShow and not canShow() then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(type(title) == "function" and title(self) or title)
        local text = detail
        if type(detail) == "function" then
            text = detail()
        end
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local validPoints = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local function PlacePanel(panel)
    local position = addon.db.position
    panel:ClearAllPoints()
    if type(position) == "table" and validPoints[position.point] and validPoints[position.relativePoint]
        and type(position.x) == "number" and type(position.y) == "number" then
        panel:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
    else
        panel:SetPoint("RIGHT", UIParent, "RIGHT", -36, 34)
    end
end

local moving = false

local function FinishMoving()
    if moving and not InCombatLockdown() then
        moving = false
        local panel = addon.panel
        panel:StopMovingOrSizing()
        local point, _, relativePoint, x, y = panel:GetPoint(1)
        addon.db.position = { point = point, relativePoint = relativePoint, x = x, y = y }
    end
end

local layoutOrder = { "healing", "raid", "markers", "full" }
local layouts = {
    healing = { label = "Party" },
    raid = { label = "Raid" },
    markers = { label = "Markers" },
    full = { label = "Combined" },
}
local panelHeaderHeight = 124

local function BuildPanel()
    if type(TriageAegisBeaconDB) ~= "table" then
        TriageAegisBeaconDB = type(VigilSigilDB) == "table" and VigilSigilDB or {}
    end
    VigilSigilDB = nil
    addon.db = TriageAegisBeaconDB
    addon.db.spells = type(addon.db.spells) == "table" and addon.db.spells or {}
    addon.InitializeAppearance()

    local panel = CreateFrame("Frame", "TriageAegisBeaconPanel", UIParent,
        "BackdropTemplate,SecureHandlerAttributeTemplate")
    addon.panel = panel
    panel:SetSize(addon.width, 495)
    panel:SetFrameStrata("MEDIUM")
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    addon.StylePanel(panel)
    addon.HeaderBand(panel, 39)
    panel:SetScale(addon.db.appearance.scale)
    panel:SetAlpha(addon.db.appearance.opacity / 100)
    PlacePanel(panel)

    local handle = CreateFrame("Frame", nil, panel)
    handle:SetPoint("TOPLEFT", panel, "TOPLEFT", addon.inset, -5)
    handle:SetSize(270, 34)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function()
        if addon.CanEdit() then
            moving = true
            panel:StartMoving()
        end
    end)
    handle:SetScript("OnDragStop", FinishMoving)
    addon.Label(handle, addon.title, "GameFontHighlightLarge", 0, -8, addon.color.accent)

    local close = addon.Button(panel, "x", 26, 26, "SecureHandlerClickTemplate")
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -addon.inset, -10)
    addon.BindPanelButton(close, "hide")
    addon.Tooltip(close, "Hide " .. addon.title, "Use the gold minimap button to open the panel again.")

    local minimize = addon.Button(panel, "-", 26, 26, "SecureHandlerClickTemplate")
    minimize:SetPoint("RIGHT", close, "LEFT", -5, 0)
    addon.BindPanelButton(minimize, "collapse-toggle")
    addon.Tooltip(minimize, "Minimize or expand", "Keep the title bar and settings within reach.")
    panel.minimizeButton = minimize

    local settings = addon.Button(panel, "Settings", 72, 26)
    settings:SetPoint("RIGHT", minimize, "LEFT", -5, 0)
    settings:SetScript("OnClick", function()
        addon.OpenSettings()
    end)

    local body = CreateFrame("Frame", nil, panel, "SecureHandlerBaseTemplate")
    body:SetAllPoints(panel)
    panel.body = body
    panel.layoutTabs = {}
    for index, key in ipairs(layoutOrder) do
        local tab = addon.Tab(body, layouts[key].label, 76, 26, false, "SecureHandlerClickTemplate")
        tab:SetPoint("TOPLEFT", body, "TOPLEFT", addon.inset + (index - 1) * 80, -47)
        addon.BindPanelButton(tab, key)
        panel.layoutTabs[key] = tab
    end

    panel.markerSection = CreateFrame("Frame", nil, body, "SecureHandlerBaseTemplate")
    panel.markerSection:SetWidth(addon.width)
    panel.markerSection:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -panelHeaderHeight)
    panel.healingSection = CreateFrame("Frame", nil, body, "SecureHandlerBaseTemplate")
    panel.healingSection:SetSize(addon.width, 259)
    panel.raidSection = CreateFrame("Frame", nil, body, "SecureHandlerBaseTemplate")
    panel.raidSection:SetWidth(addon.raidWidth)
    panel.raidSection:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -panelHeaderHeight)
    addon.BuildMarkers(panel.markerSection)
    addon.BuildHealing(panel.healingSection)
    addon.BuildRaid(panel.raidSection)
    addon.BuildRangeAlerts(body)
    addon.InitializeBuffCoverage()
    addon.InitializePanelControls(panel, layouts[addon.db.layout] and addon.db.layout or "healing", panelHeaderHeight)
    addon.RefreshHealingAppearance()
    addon.BuildMinimap()
end

BINDING_NAME_TRIAGEBEACON_MARKERS = "Toggle marker list"
SLASH_TRIAGEAEGISBEACON1 = "/triage"
SlashCmdList.TRIAGEAEGISBEACON = function(input)
    local command, argument = input:match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if not addon.panel then
        addon.Print("The panel will be ready when combat ends.")
    elseif command == "" then
        addon.TogglePanel()
    elseif command == "show" or command == "hide" then
        addon.PanelAction(command)
    elseif command == "spells" then
        addon.OpenSpellOptions()
    elseif command == "icons" then
        addon.OpenSpellIcons()
    elseif command == "mouse" then
        addon.OpenMouseOptions()
    elseif command == "practice" then
        addon.OpenSettings("practice")
    elseif command == "alerts" then
        addon.OpenRangeOptions()
    elseif command == "settings" then
        addon.OpenSettings()
    elseif command == "credits" then
        addon.OpenSettings("credits")
    elseif command == "minimize" or command == "expand" then
        addon.PanelAction(command)
    elseif command == "minimap" then
        addon.MinimapCommand(argument:lower())
    elseif command == "keys" then
        addon.OpenKeybindings()
    elseif command == "markers" then
        addon.PanelAction("marker-key")
    elseif command == "version" then
        addon.Print(addon.ReleaseLabel())
    elseif command == "reset" then
        if addon.CanEdit() then
            FinishMoving()
            addon.db.position = nil
            PlacePanel(addon.panel)
            addon.PanelAction("show")
        end
    else
        addon.Print("/triage, /triage show, /triage hide, /triage minimize, /triage expand, /triage reset")
        addon.Print("/triage settings, /triage spells, /triage icons, /triage mouse, /triage practice, /triage alerts")
        addon.Print("/triage keys, /triage markers, /triage version, /triage credits, /triage help")
        addon.Print("/triage minimap, /triage minimap show, /triage minimap hide, /triage minimap reset")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    if not addon.panel and not InCombatLockdown() then
        local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if isLoaded and isLoaded(legacyAddon) then
            addon.Print("Disable the older addon in the AddOns list and restart WoW to use this release.")
            events:UnregisterAllEvents()
            return
        end
        BuildPanel()
        TriageBeacon_ToggleMarkers = function() addon.PanelAction("marker-key") end
        PrintLoadCredit()
    elseif addon.panel and event == "PLAYER_REGEN_ENABLED" then
        FinishMoving()
        addon.ApplyPendingAppearance()
        addon.UpdateMinimap()
    end
end)
