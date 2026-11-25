local _, addon = ...

-- Raid icons and matching world markers use different numbers.
local markers = {
    { name = "Star",     world = 5 },
    { name = "Circle",   world = 6 },
    { name = "Diamond",  world = 3 },
    { name = "Triangle", world = 2 },
    { name = "Moon",     world = 7 },
    { name = "Square",   world = 1 },
    { name = "Cross",    world = 4 },
    { name = "Skull",    world = 8 },
}

local recipients = {
    { label = "Target",  unit = "target" },
    { label = "Self",    unit = "player" },
    { label = "Party 1", unit = "party1" },
    { label = "Party 2", unit = "party2" },
    { label = "Party 3", unit = "party3" },
    { label = "Party 4", unit = "party4" },
}

local markerButtonWidth, markerButtonHeight, markerIconSize = 32, 30, 20

local function MarkAction(button, isWorld, markerIndex, action)
    button:SetAttribute("*type1", isWorld and "worldmarker" or "raidtarget")
    button:SetAttribute("*action1", action)
    button:SetAttribute("marker", markerIndex)
end

local function AddMarkerRow(parent, y, isWorld)
    local actionType = isWorld and "worldmarker" or "raidtarget"
    for iconIndex, marker in ipairs(markers) do
        local button = addon.Button(parent, nil, markerButtonWidth, markerButtonHeight, "SecureActionButtonTemplate")
        button:SetPoint("TOPLEFT", parent, "TOPLEFT", addon.inset + (iconIndex - 1) * 42, y)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetSize(markerIconSize, markerIconSize)
        icon:SetPoint("CENTER")
        icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. iconIndex)

        MarkAction(button, isWorld, isWorld and marker.world or iconIndex, "set")
        if isWorld then
            button:SetAttribute("*type2", actionType)
            button:SetAttribute("*action2", "clear")
            addon.Tooltip(button, marker.name .. " world marker", "Left-click, then click the ground. Right-click to clear this marker.")
        else
            button:SetAttribute("useparent-unit", true)
            addon.Tooltip(button, marker.name .. " unit icon", "Apply to the selected recipient above.")
        end
    end

    local clear = addon.Button(parent, isWorld and "Clear all" or "Clear icon", 88, markerButtonHeight,
        "SecureActionButtonTemplate")
    clear:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -addon.inset, y)
    MarkAction(clear, isWorld, nil, "clear")
    if not isWorld then
        clear:SetAttribute("useparent-unit", true)
    end
    local description = isWorld and "Remove all world markers." or "Remove the icon from the selected recipient."
    addon.Tooltip(clear, isWorld and "Clear all world markers" or "Clear unit icon", description)
end

local function AddRecipientSelector(panel, unitMarkers, y)
    local tabs = {}

    for index, entry in ipairs(recipients) do
        local button = addon.Button(panel, entry.label, 66, 22, "SecureActionButtonTemplate")
        button:SetPoint("TOPLEFT", panel, "TOPLEFT", addon.inset + (index - 1) * 71, y)
        button:SetAttribute("*type1", "attribute")
        button:SetAttribute("attribute-frame", unitMarkers)
        button:SetAttribute("attribute-name", "unit")
        button:SetAttribute("attribute-value", entry.unit)

        local selection = button:CreateTexture(nil, "ARTWORK")
        selection:SetPoint("BOTTOMLEFT", 0, 0)
        selection:SetPoint("BOTTOMRIGHT", 0, 0)
        selection:SetHeight(2)
        selection:SetColorTexture(unpack(addon.color.accent))
        selection:SetShown(entry.unit == "target")
        tabs[entry.unit] = selection

        addon.Tooltip(button, entry.label, "Send the next unit icon to this recipient.")
    end

    unitMarkers:HookScript("OnAttributeChanged", function(_, name, value)
        if name == "unit" then
            for unit, selection in pairs(tabs) do
                selection:SetShown(unit == value)
            end
        end
    end)
end

function addon.BuildMarkers(panel)
    local side = addon.inset
    local worldMarkers = addon.HasWorldMarkers()
    addon.Label(panel, "World markers", "GameFontHighlight", side, -4, addon.color.accent)
    if worldMarkers then
        local hint = addon.Label(panel, "Right-click clears one", nil, side, -4, addon.color.dim)
        hint:ClearAllPoints()
        hint:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -side, -4)
        AddMarkerRow(panel, -21, true)
    else
        addon.Label(panel, "World markers are unavailable on this client.", nil, side, -25, addon.color.dim)
    end

    addon.Label(panel, "Party & target icons", "GameFontHighlight", side, -59, addon.color.accent)
    local unitMarkers = CreateFrame("Frame", nil, panel, "SecureHandlerBaseTemplate")
    unitMarkers:SetAllPoints(panel)
    unitMarkers:SetAttribute("unit", "target")
    AddRecipientSelector(panel, unitMarkers, -76)
    AddMarkerRow(unitMarkers, -103, false)

    local footerTop, footerHeight = 139, 23
    local ready = addon.Button(panel, "Ready check", 102, footerHeight, "SecureActionButtonTemplate")
    ready:SetPoint("TOPLEFT", panel, "TOPLEFT", side, -footerTop)
    ready:SetAttribute("*type1", "macro")
    ready:SetAttribute("macrotext", "/readycheck")
    addon.Tooltip(ready, "Ready check", "Start a built-in group ready check when you have permission.")

    local pull = addon.Button(panel, "10s pull", 92, footerHeight)
    pull:SetPoint("LEFT", ready, "RIGHT", 6, 0)
    local countdown = (C_PartyInfo and C_PartyInfo.DoCountdown) or DoCountdown
    pull:SetEnabled(type(countdown) == "function")
    pull:SetScript("OnClick", function()
        if not IsInGroup() then
            addon.Print("Join a group before starting a countdown.")
            return
        end
        local ok, started = pcall(countdown, 10)
        if not ok or started == false then
            addon.Print("WoW could not start the countdown. Check your group permissions.")
        end
    end)
    addon.Tooltip(pull, "Pull countdown", "Start WoW's ten-second group countdown.")
    panel:SetHeight(footerTop + footerHeight + 6)

    for index, marker in ipairs(markers) do
        local target = addon.CreateBindingButton("Target" .. index, "Target icon: " .. marker.name)
        target:SetAttribute("unit", "target")
        MarkAction(target, false, index, "set")
        local world = addon.CreateBindingButton("World" .. index, "World marker: " .. marker.name)
        if worldMarkers then MarkAction(world, true, marker.world, "set") end
    end

    local clearTarget = addon.CreateBindingButton("ClearTarget", "Clear target icon")
    clearTarget:SetAttribute("unit", "target")
    MarkAction(clearTarget, false, nil, "clear")
    local clearWorld = addon.CreateBindingButton("ClearWorld", "Clear all world markers")
    if worldMarkers then MarkAction(clearWorld, true, nil, "clear") end
end
