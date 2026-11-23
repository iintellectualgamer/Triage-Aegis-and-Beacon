local _, addon = ...

local button, signal, signalVisible
local defaultAngle = -0.38
local dragging, dragElapsed

local function PositionButton()
    if InCombatLockdown() then return end
    local x, y = Minimap:GetCenter()
    if not x or not y then return end
    local scale = Minimap:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local angle = addon.db.minimapAngle
    if type(angle) ~= "number" or angle ~= angle or math.abs(angle) > 2 * math.pi then
        angle = defaultAngle
    end
    local horizontal = Minimap:GetWidth() / 2 + 3
    local vertical = Minimap:GetHeight() / 2 + 3
    button:ClearAllPoints()
    button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (x + math.cos(angle) * horizontal) * scale,
        (y + math.sin(angle) * vertical) * scale)
end

function addon.UpdateMinimap()
    if button and not InCombatLockdown() then
        if not dragging then button:SetAttribute("triage-dragging", nil) end
        PositionButton()
        button:SetShown(addon.db.appearance.minimap and Minimap:IsVisible())
    end
end

function addon.MinimapCommand(argument)
    if argument == "reset" then
        addon.db.minimapAngle = nil
        addon.db.appearance.minimap = true
    elseif argument == "show" or argument == "hide" then
        addon.db.appearance.minimap = argument == "show"
    elseif argument == "" then
        addon.db.appearance.minimap = not addon.db.appearance.minimap
    else
        addon.Print("/triage minimap [show, hide, reset]")
        return
    end
    addon.UpdateMinimap()
    if InCombatLockdown() then
        addon.Print("Minimap changes saved for after combat.")
    else
        addon.Print(addon.db.appearance.minimap and "Minimap button shown." or "Minimap button hidden.")
    end
end

local function DragButton(self, elapsed)
    if InCombatLockdown() or (IsMouseButtonDown and not IsMouseButtonDown("LeftButton")) then
        dragging = nil
        self:SetScript("OnUpdate", nil)
        if not InCombatLockdown() then self:SetAttribute("triage-dragging", nil) end
        return
    end
    dragElapsed = dragElapsed + elapsed
    if dragElapsed < 1 / 30 then return end
    dragElapsed = 0
    local centerX, centerY = Minimap:GetCenter()
    if not centerX or not centerY then
        return
    end
    local scale = Minimap:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    addon.db.minimapAngle = math.atan2(cursorY / scale - centerY, cursorX / scale - centerX)
    PositionButton()
end

function addon.FlashMinimapSignal()
    if not signal or not Minimap:IsVisible() then return false end
    if signalVisible then return true end
    signalVisible = true
    signal:SetAlpha(1)
    C_Timer.After(4, function()
        signalVisible = nil
        signal:SetAlpha(0)
    end)
    return true
end

function addon.BuildMinimap()
    if not Minimap then return end
    signal = Minimap:CreateTexture(nil, "OVERLAY", nil, 6)
    signal:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_4")
    signal:SetPoint("CENTER", Minimap, "CENTER", 0, 14)
    signal:SetSize(19, 19)
    signal:SetAlpha(0)
    button = CreateFrame("Button", "TriageAegisBeaconMinimap", UIParent,
        "BackdropTemplate,SecureHandlerClickTemplate")
    button:SetSize(30, 30)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    addon.StylePanel(button)
    button:SetBackdropBorderColor(unpack(addon.color.accent))

    local function Stroke(x, y, width, height, color)
        local mark = button:CreateTexture(nil, "ARTWORK")
        mark:SetSize(width, height)
        mark:SetPoint("CENTER", button, "CENTER", x, y)
        mark:SetColorTexture(unpack(color))
    end
    local amber = addon.color.accent
    Stroke(0, -1, 3, 16, amber)
    Stroke(0, 4, 16, 3, amber)
    Stroke(0, -9, 11, 2, amber)
    Stroke(-8, 8, 2, 2, amber)
    Stroke(8, 8, 2, 2, amber)

    addon.BindPanelButton(button, "toggle", true)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self)
        if addon.CanEdit() then
            dragging = true
            dragElapsed = 0
            self:SetAttribute("triage-dragging", true)
            self:SetScript("OnUpdate", DragButton)
        end
    end)
    button:HookScript("OnHide", function(self)
        if dragging then
            dragging = nil
            self:SetScript("OnUpdate", nil)
            if not InCombatLockdown() then self:SetAttribute("triage-dragging", nil) end
        end
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        dragging = nil
        C_Timer.After(0, function()
            if not InCombatLockdown() and not dragging then self:SetAttribute("triage-dragging", nil) end
        end)
    end)
    button:HookScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then addon.OpenSettings() end
    end)
    addon.Tooltip(button, addon.title, "Left-click to show or hide.\nRight-click for Settings.\nDrag to reposition.")
    Minimap:HookScript("OnSizeChanged", addon.UpdateMinimap)
    Minimap:HookScript("OnShow", addon.UpdateMinimap)
    Minimap:HookScript("OnHide", addon.UpdateMinimap)
    local events = CreateFrame("Frame")
    events:RegisterEvent("UI_SCALE_CHANGED")
    events:RegisterEvent("DISPLAY_SIZE_CHANGED")
    events:SetScript("OnEvent", addon.UpdateMinimap)
    addon.UpdateMinimap()
end
