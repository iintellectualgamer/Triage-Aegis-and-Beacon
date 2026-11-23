local _, addon = ...

-- Only fixed panel commands run inside the secure handler. Saved settings and
-- styling are updated by the ordinary UI after the protected layout is applied.
local panelCommand = [=[
    if name == "state-triage-group" then
        if self:GetAttribute("triage-view") ~= "full" then return end
        value = "reflow"
    elseif name == "triage-command" and value then
        self:SetAttribute("triage-command", nil)
    else
        return
    end

    local view = self:GetAttribute("triage-view")
    local minimized = self:GetAttribute("triage-minimized")
    local shown = self:GetAttribute("triage-shown")
    local temporary = self:GetAttribute("triage-temporary")
    if value == "marker-key" then
        if view == "markers" and shown and not minimized then
            if temporary then
                view = self:GetAttribute("triage-previous-view")
                minimized = self:GetAttribute("triage-previous-minimized")
                shown = self:GetAttribute("triage-previous-shown")
                temporary = false
            else
                shown = false
            end
        else
            self:SetAttribute("triage-previous-view", view)
            self:SetAttribute("triage-previous-minimized", minimized)
            self:SetAttribute("triage-previous-shown", shown)
            view, minimized, shown, temporary = "markers", false, true, true
        end
    elseif value == "healing" or value == "raid" or value == "markers" or value == "full" then
        view, minimized, temporary = value, false, false
    elseif value ~= "reflow" then
        if temporary then
            view = self:GetAttribute("triage-previous-view")
            minimized = self:GetAttribute("triage-previous-minimized")
            temporary = false
        end
        if value == "hide" then shown = false
        elseif value == "show" then shown = true
        elseif value == "toggle" then shown = not shown
        elseif value == "minimize" then minimized = true
        elseif value == "expand" then minimized = false
        elseif value == "collapse-toggle" then minimized = not minimized
        else return end
    end

    local body = self:GetFrameRef("body")
    local markers = self:GetFrameRef("markers")
    local party = self:GetFrameRef("party")
    local raid = self:GetFrameRef("raid")
    local height = self:GetAttribute("triage-header-height")
    local raidView = view == "raid" or (view == "full" and self:GetAttribute("state-triage-group") == "raid")
    if raidView then
        raid:ClearAllPoints()
        raid:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -height)
        raid:Show()
        height = height + raid:GetHeight()
    else
        raid:Hide()
    end
    if view == "healing" or (view == "full" and not raidView) then
        party:ClearAllPoints()
        party:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -height)
        party:Show()
        height = height + party:GetHeight()
    else
        party:Hide()
    end
    if view == "markers" or view == "full" then
        markers:ClearAllPoints()
        markers:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -height)
        markers:Show()
        height = height + markers:GetHeight()
    else
        markers:Hide()
    end
    if minimized then body:Hide(); height = 42
    else body:Show() end
    local width = raidView and not minimized and raid:GetWidth() or party:GetWidth()
    if self:GetWidth() ~= width then self:SetWidth(width) end
    self:SetHeight(height)
    if shown then self:Show()
    else self:Hide() end

    self:SetAttribute("triage-view", view)
    self:SetAttribute("triage-minimized", minimized)
    self:SetAttribute("triage-shown", shown)
    self:SetAttribute("triage-temporary", temporary)
    self:SetAttribute("triage-revision", (self:GetAttribute("triage-revision") or 0) + 1)
]=]

local tap = [=[
    if button == "LeftButton" and not self:GetAttribute("triage-dragging") then
        self:GetFrameRef("panel"):SetAttribute("triage-command", self:GetAttribute("triage-action"))
    end
]=]

function addon.BindPanelButton(button, action, rightClick)
    button:SetFrameRef("panel", addon.panel)
    button:SetAttribute("triage-action", action)
    button:SetAttribute("_onclick", tap)
    if rightClick then
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    else
        button:RegisterForClicks("LeftButtonUp")
    end
end

function addon.PanelAction(action)
    if InCombatLockdown() then
        addon.Print("Use the panel tabs, title controls, or minimap button during combat.")
        return
    end
    addon.panel:SetAttribute("triage-command", action)
end

function addon.TogglePanel()
    if addon.panel then addon.PanelAction("toggle") end
end

function addon.ResizePanel()
    addon.PanelAction("reflow")
end

function addon.InitializePanelControls(panel, initialView, headerHeight)
    panel:SetFrameRef("body", panel.body)
    panel:SetFrameRef("party", panel.healingSection)
    panel:SetFrameRef("raid", panel.raidSection)
    panel:SetFrameRef("markers", panel.markerSection)
    panel:SetAttribute("triage-header-height", headerHeight)
    panel:SetAttribute("triage-view", initialView)
    panel:SetAttribute("triage-shown", addon.db.hidden ~= true)
    panel:SetAttribute("triage-minimized", addon.db.minimized == true)
    panel:SetAttribute("state-triage-group", IsInRaid() and "raid" or "party")
    panel:SetAttribute("_onattributechanged", panelCommand)

    panel:HookScript("OnAttributeChanged", function(self, name)
        if name ~= "triage-revision" then return end
        local view = self:GetAttribute("triage-view")
        local minimized = self:GetAttribute("triage-minimized")
        self.activeLayout, self.minimized = view, minimized
        self.minimizeButton.label:SetText(minimized and "+" or "-")
        for key, tab in pairs(self.layoutTabs) do
            addon.SelectTab(tab, key == view)
        end
        addon.RefreshRangePolling()
        if not self:GetAttribute("triage-temporary") then
            addon.db.layout = view
            addon.db.minimized = minimized
            addon.db.hidden = not self:GetAttribute("triage-shown")
        end
    end)

    RegisterStateDriver(panel, "triage-group", "[group:raid] raid; party")

    local key = CreateFrame("Button", "TriageBeaconMarkerPanelButton", UIParent, "SecureHandlerClickTemplate")
    addon.BindPanelButton(key, "marker-key")
    if SetOverrideBindingClick and ClearOverrideBindings then
        local function UpdateBindings()
            if InCombatLockdown() then return end
            ClearOverrideBindings(key)
            for _, binding in ipairs({ GetBindingKey("TRIAGEBEACON_MARKERS") }) do
                SetOverrideBindingClick(key, false, binding, "TriageBeaconMarkerPanelButton", "LeftButton")
            end
        end
        key:RegisterEvent("UPDATE_BINDINGS")
        key:RegisterEvent("PLAYER_REGEN_ENABLED")
        key:SetScript("OnEvent", UpdateBindings)
        UpdateBindings()
    end

    addon.ResizePanel()
end
