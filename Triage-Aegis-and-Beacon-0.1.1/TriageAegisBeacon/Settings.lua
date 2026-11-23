local _, addon = ...

addon.healthColors = {
    teal = { 0.12, 0.42, 0.35, 1 },
    blue = { 0.15, 0.31, 0.53, 1 },
    gold = { 0.43, 0.33, 0.17, 1 },
}
local defaults = {
    scale = 1, opacity = 100, density = "comfortable", palette = "teal",
    healthAmount = true, healthText = true, classColors = false, minimap = true, pet = false, groupRoles = true,
    pinSelf = false, pinTank = false, combatTooltips = false, cleanseCue = false, hoverEdge = false,
}
local window, refreshSpellSettings, refreshMouseSettings, pendingAppearance

function addon.InitializeAppearance()
    local values = addon.db.appearance
    if type(values) ~= "table" then
        values = {}
        addon.db.appearance = values
    end
    if values.scale ~= 0.85 and values.scale ~= 1 and values.scale ~= 1.15 then
        values.scale = defaults.scale
    end
    if type(values.opacity) ~= "number" or not (values.opacity >= 25 and values.opacity <= 100) then
        values.opacity = defaults.opacity
    else
        values.opacity = math.floor(values.opacity / 5 + 0.5) * 5
    end
    if values.density ~= "compact" and values.density ~= "comfortable" then
        values.density = defaults.density
    end
    if type(values.palette) ~= "string" or not addon.healthColors[values.palette] then
        values.palette = defaults.palette
    end
    for key, default in pairs(defaults) do
        if type(default) == "boolean" and type(values[key]) ~= "boolean" then
            values[key] = default
        end
    end
end

function addon.ApplyPendingAppearance()
    if not pendingAppearance or InCombatLockdown() then return end
    pendingAppearance = false
    addon.panel:SetScale(addon.db.appearance.scale)
    addon.RefreshPartyAppearance()
    addon.RefreshHealingPriorities()
    addon.ResizePanel()
    addon.UpdateMinimap()
end

local function ChoiceRow(page, draft, key, title, choices, y)
    addon.Label(page, title, "GameFontHighlight", 0, y - 5)
    local buttons = {}
    local function Refresh()
        for index, choice in ipairs(choices) do
            addon.SelectTab(buttons[index], draft[key] == choice[2])
        end
    end
    for index, choice in ipairs(choices) do
        local button = addon.Tab(page, choice[1], 92, 24)
        button:SetPoint("TOPLEFT", page, "TOPLEFT", 151 + (index - 1) * 97, y)
        button:SetScript("OnClick", function()
            draft[key] = choice[2]
            Refresh()
        end)
        buttons[index] = button
    end
    return Refresh
end

local function BuildAppearance(page)
    local draft, checks = {}, {}
    addon.Label(page, "Appearance", "GameFontHighlightLarge", 0, 0, addon.color.accent)
    addon.Label(page, "Adjust the play panel and party health bars.", nil, 0, -29, addon.color.dim)
    local refreshScale = ChoiceRow(page, draft, "scale", "Panel scale", {
        { "85%", 0.85 }, { "100%", 1 }, { "115%", 1.15 },
    }, -60)
    local refreshDensity = ChoiceRow(page, draft, "density", "Party bar spacing", {
        { "Compact", "compact" }, { "Comfortable", "comfortable" },
    }, -95)
    local refreshPalette = ChoiceRow(page, draft, "palette", "Party bar color", {
        { "Teal", "teal" }, { "Blue", "blue" }, { "Gold", "gold" },
    }, -130)
    addon.Label(page, "Panel opacity", "GameFontHighlight", 0, -166)
    local opacity = CreateFrame("Slider", nil, page)
    opacity:SetPoint("TOPLEFT", page, "TOPLEFT", 151, -161)
    opacity:SetSize(240, 20)
    opacity:SetOrientation("HORIZONTAL")
    opacity:EnableMouse(true)
    opacity:SetMinMaxValues(25, 100)
    opacity:SetValueStep(5)
    opacity:SetObeyStepOnDrag(true)
    local track = opacity:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", opacity, "LEFT")
    track:SetPoint("RIGHT", opacity, "RIGHT")
    track:SetHeight(4)
    track:SetColorTexture(unpack(addon.color.border))
    opacity:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local opacityText = addon.Label(page, "100%", "GameFontHighlight", 405, -166, addon.color.accent)
    local function ShowOpacity(value)
        draft.opacity = math.floor(value / 5 + 0.5) * 5
        opacityText:SetText(("%d%%"):format(draft.opacity))
    end
    opacity:SetScript("OnValueChanged", function(_, value) ShowOpacity(value) end)
    local choices = {
        { "healthAmount", "Show current health" },
        { "healthText", "Show health percentages" },
        { "classColors", "Use class colors on party bars" },
        { "pet", "Show a healing bar for your pet" },
        { "minimap", "Show the Triage minimap button" },
        { "hoverEdge", "Show a thin hover edge" },
        { "pinSelf", "Pin yourself in Raid view" },
        { "pinTank", "Pin the first assigned tank" },
        { "combatTooltips", "Show healing tooltips in combat" },
        { "cleanseCue", "Show a cleanse cue" },
        { "groupRoles", "Show party roles" },
    }
    for index, choice in ipairs(choices) do
        local x = index > 6 and 220 or 0
        local y = -187 - ((index - 1) % 6) * 21
        local check = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
        check:SetSize(21, 21)
        check:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
        addon.Label(page, choice[2], nil, x + 25, y - 5)
        checks[choice[1]] = check
    end
    local message = addon.Label(page, "", nil, 0, -314, addon.color.dim)
    local function Load(values)
        for key in pairs(defaults) do
            draft[key] = values[key]
        end
        for key, check in pairs(checks) do
            check:SetChecked(draft[key])
        end
        refreshScale()
        refreshDensity()
        refreshPalette()
        opacity:SetValue(draft.opacity)
        ShowOpacity(draft.opacity)
        message:SetText("")
    end
    local reset = addon.Button(page, "Reset defaults", 110, 27)
    reset:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT")
    reset:SetScript("OnClick", function() Load(defaults) end)
    local save = addon.Button(page, "Apply appearance", 127, 27)
    save:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT")
    save:SetScript("OnClick", function()
        for key, check in pairs(checks) do
            draft[key] = not not check:GetChecked()
        end
        for key in pairs(defaults) do
            addon.db.appearance[key] = draft[key]
        end
        addon.panel:SetAlpha(draft.opacity / 100)
        addon.RefreshCleanseCues()
        if InCombatLockdown() then addon.ClearHealingTooltip() end
        pendingAppearance = true
        if InCombatLockdown() then
            addon.RefreshHealingAppearance()
            message:SetText("Opacity and colors applied. Layout changes apply after combat.")
        else
            addon.ApplyPendingAppearance()
            message:SetText("Appearance saved.")
        end
    end)
    return function() Load(addon.db.appearance) end
end

local function BuildKeybinds(page)
    local keys = {}
    local function Row(name, command, x, y)
        addon.Label(page, name, nil, x, y, addon.color.text)
        local value = addon.Label(page, "", nil, x + 103, y, addon.color.dim)
        value:SetWidth(103)
        value:SetWordWrap(false)
        value:SetJustifyH("RIGHT")
        keys[command] = value
    end
    local function ClickCommand(action)
        return "CLICK TriageBeaconKey" .. action .. ":LeftButton"
    end
    local function Refresh()
        for command, value in pairs(keys) do
            local key = GetBindingKey(command)
            value:SetText(key or "Unbound")
            value:SetTextColor(unpack(key and addon.color.accent or addon.color.dim))
        end
    end

    addon.Label(page, "Keybinds", "GameFontHighlightLarge", 0, 0, addon.color.accent)
    local edit = addon.Button(page, "Assign in WoW", 114, 25)
    edit:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 1)
    edit:SetScript("OnClick", addon.OpenKeybindings)
    addon.Label(page, "Single-target heals", "GameFontHighlight", 0, -48, addon.color.accent)
    addon.Label(page, "Area heals", "GameFontHighlight", 232, -48, addon.color.accent)
    for index = 1, 3 do
        local y = -69 - (index - 1) * 17
        Row("Spell " .. index, ClickCommand("Single" .. index), 0, y)
        Row("Spell " .. index, ClickCommand("Area" .. index), 232, y)
    end
    addon.Label(page, "Target icons", "GameFontHighlight", 0, -133, addon.color.accent)
    addon.Label(page, "World markers", "GameFontHighlight", 232, -133, addon.color.accent)
    local markers = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
    for index, name in ipairs(markers) do
        local y = -154 - (index - 1) * 17
        Row(name, ClickCommand("Target" .. index), 0, y)
        Row(name, ClickCommand("World" .. index), 232, y)
    end
    Row("Clear icon", ClickCommand("ClearTarget"), 0, -290)
    Row("Clear all", ClickCommand("ClearWorld"), 232, -290)
    Row("Marker list", "TRIAGEBEACON_MARKERS", 0, -332)
    Row("Healer signal", ClickCommand("Assist"), 232, -332)
    local native = addon.Button(page, "Blizzard click casting", 145, 23)
    native:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT")
    native:SetScript("OnClick", addon.OpenBlizzardClickCasting)
    page:RegisterEvent("UPDATE_BINDINGS")
    page:SetScript("OnEvent", Refresh)
    return Refresh
end

local function RefreshProfileViews()
    if refreshSpellSettings then refreshSpellSettings() end
    if refreshMouseSettings then refreshMouseSettings() end
    if addon.RefreshSpellIconSettings then addon.RefreshSpellIconSettings() end
end

local function BuildProfileTransfer(page)
    addon.Label(page, "Healing profiles", "GameFontHighlightLarge", 0, 0, addon.color.accent)
    addon.Label(page, "Copy your spells, mouse bindings, and icon choices to another character.", nil, 0, -29, addon.color.dim)
    local box = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    box:SetSize(430, 28)
    box:SetPoint("TOPLEFT", page, "TOPLEFT", 5, -70)
    box:SetAutoFocus(false)
    box:SetMaxLetters(32767)
    box:SetScript("OnEscapePressed", addon.CloseSettings)
    local message = addon.Label(page, "", nil, 0, -148, addon.color.dim)
    message:SetWidth(440)
    message:SetWordWrap(true)
    message:SetJustifyH("LEFT")

    local export = addon.Button(page, "Select export text", 136, 26)
    export:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -112)
    export:SetScript("OnClick", function()
        local fields = { "TAB5" }
        local function AddField(spell)
            local value = addon.ValidSpellIdentifier(spell) and tostring(spell) or ""
            if value:find("[|\r\n]") then
                message:SetText("Clear invalid characters from the saved spell and try again.")
                return false
            end
            tinsert(fields, value)
            return true
        end
        for _, mode in ipairs(addon.healModes) do
            local spells = addon.ProfileInputs(mode)
            for _, slot in ipairs(addon.healSlots) do
                if not AddField(spells[slot.key]) then return end
            end
        end
        local mouse = addon.ProfileInputs("mouse")
        for _, key in ipairs({ "left", "middle" }) do
            if not AddField(mouse[key]) then return end
        end
        local extra = addon.ProfileInputs("extra")
        for _, key in ipairs(addon.extraKeys) do
            if not AddField(extra[key]) then return end
        end
        local hidden, flags = addon.ProfileInputs("icons"), {}
        for index, key in ipairs(addon.iconKeys) do flags[index] = hidden[key] == true and "1" or "0" end
        tinsert(fields, table.concat(flags))
        if not AddField(addon.ProfileInputs("emergency").spell) then return end
        local extraClicks = addon.ProfileInputs("clicks")
        local ordered = {}
        for key, spell in pairs(extraClicks) do
            if addon.ExtraHealthClick(key) and addon.ValidSpellIdentifier(spell) then tinsert(ordered, key) end
        end
        table.sort(ordered)
        for _, key in ipairs(ordered) do
            tinsert(fields, key)
            if not AddField(extraClicks[key]) then return end
        end
        box:SetText(table.concat(fields, "|"))
        box:SetFocus()
        box:HighlightText()
        message:SetText("Press Ctrl+C to copy the selected text.")
    end)

    local import = addon.Button(page, "Import profile", 135, 26)
    import:SetPoint("LEFT", export, "RIGHT", 8, 0)
    import:SetScript("OnClick", function()
        local fields = {}
        local maxFields = 13 + 2 * 8 * addon.mouseButtonCount
        for entry in (box:GetText() .. "|"):gmatch("([^|]*)|") do
            tinsert(fields, entry)
            if #fields > maxFields then
                message:SetText("This profile has too many click assignments.")
                return
            end
        end
        local old = fields[1] == "TAB1" and #fields == 7
        local withMouse = fields[1] == "TAB2" and #fields == 9
        local withClicks = fields[1] == "TAB5" and #fields >= 13 and (#fields - 13) % 2 == 0
        local withEmergency = (fields[1] == "TAB4" and #fields == 13) or withClicks
        local withIcons = ((fields[1] == "TAB3" and #fields == 12) or withEmergency)
            and #fields[12] == #addon.iconKeys and fields[12]:match("^[01]+$")
        if not old and not withMouse and not withIcons then
            message:SetText("Paste a complete profile export before importing.")
            return
        end
        local sets, index = {}, 2
        for _, mode in ipairs(addon.healModes) do
            sets[mode] = {}
            for position, slot in ipairs(addon.healSlots) do
                local spell, reason = addon.ReadClickAction(fields[index])
                if reason then
                    message:SetText(addon.healClicks[mode][position].label .. ". " .. reason)
                    return
                end
                sets[mode][slot.key] = spell
                index = index + 1
            end
        end
        if withMouse or withIcons then
            sets.mouse = {}
            for _, key in ipairs({ "left", "middle" }) do
                local spell, reason = addon.ReadClickAction(fields[index])
                if reason then message:SetText("Mouse " .. key .. " · " .. reason); return end
                sets.mouse[key], index = spell, index + 1
            end
        end
        if withIcons then
            sets.extra, sets.icons = {}, {}
            for slot, key in ipairs(addon.extraKeys) do
                local spell, reason = addon.ReadSpell(fields[index])
                if reason then message:SetText("Extra spell " .. slot .. ". " .. reason); return end
                sets.extra[key], index = spell, index + 1
            end
            for slot, key in ipairs(addon.iconKeys) do
                if fields[index]:sub(slot, slot) == "1" then sets.icons[key] = true end
            end
        end
        if withEmergency then
            local spell, reason = addon.ReadClickAction(fields[13])
            if reason then message:SetText("Emergency spell. " .. reason); return end
            sets.emergency = { spell = spell }
        end
        if withClicks then
            sets.clicks = {}
            for position = 14, #fields, 2 do
                local key = fields[position]
                if not addon.ExtraHealthClick(key) or sets.clicks[key] then
                    message:SetText("The profile contains an invalid or duplicate click combination.")
                    return
                end
                local spell, reason = addon.ReadClickAction(fields[position + 1])
                if not spell then
                    local prefix, button = addon.ParseHealthClick(key)
                    message:SetText(addon.HealthClickLabel(prefix, button) .. ". " .. (reason or "Choose a spell or click action."))
                    return
                end
                sets.clicks[key] = spell
            end
        end
        local applied = addon.SaveSpellSets(sets)
        RefreshProfileViews()
        box:ClearFocus()
        message:SetText(applied and "Profile imported." or "Imported. New bindings take effect after combat.")
    end)
    addon.Label(page, "Dungeon and raid presets", "GameFontHighlight", 0, -204, addon.color.accent)
    addon.Label(page, "Save spells, click bindings, and icon choices for this specialization.", nil, 0, -228, addon.color.dim)
    local presets = {
        { key = "dungeon", name = "Dungeon", view = "healing" },
        { key = "raid", name = "Raid", view = "raid" },
    }
    for index, preset in ipairs(presets) do
        local x = (index - 1) * 217
        local save = addon.Button(page, "Save " .. preset.name, 98, 26)
        save:SetPoint("TOPLEFT", page, "TOPLEFT", x, -250)
        save:SetScript("OnClick", function()
            addon.SaveHealingPreset(preset.key)
            message:SetText(preset.name .. " preset saved.")
        end)
        local use = addon.Button(page, "Use " .. preset.name, 98, 26)
        use:SetPoint("LEFT", save, "RIGHT", 5, 0)
        use:SetScript("OnClick", function()
            if InCombatLockdown() then
                message:SetText("Switch presets when combat ends.")
                return
            end
            local spells = addon.HealingPreset(preset.key)
            if spells then addon.SaveSpellSets(spells); RefreshProfileViews() end
            addon.PanelAction(preset.view)
            message:SetText(spells and preset.name .. " preset loaded." or preset.name .. " view opened. Save a preset there when ready.")
        end)
    end
    page:SetScript("OnHide", function() box:ClearFocus() end)
    return function()
        box:SetText("")
        message:SetText("")
    end
end

local function BuildCredits(page)
    addon.Label(page, "Credits", "GameFontHighlightLarge", 0, 0, addon.color.accent)
    local creator = addon.creator
    local card = CreateFrame("Frame", nil, page, "BackdropTemplate")
    card:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -34)
    card:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -34)
    card:SetHeight(166)
    addon.StylePanel(card)
    addon.HeaderBand(card, 42)
    addon.Label(card, creator.name, "GameFontHighlightLarge", 12, -11, addon.color.accent)
    local release = addon.Label(card, "Release " .. addon.ReleaseLabel(), nil, 0, 0, addon.color.dim)
    release:ClearAllPoints()
    release:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -16)

    local status = addon.Label(page, "Select a detail to copy it.", nil, 0, -217, addon.color.dim)
    local copy = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    copy:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -237)
    copy:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, -237)
    copy:SetHeight(24)
    copy:SetAutoFocus(false)
    copy:SetMaxLetters(120)
    local selected
    copy:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    copy:SetScript("OnTextChanged", function(self, userInput)
        if userInput and selected then
            self:SetText(selected)
            self:HighlightText()
        end
    end)
    local function ClearCopyFocus() copy:ClearFocus() end
    copy:SetScript("OnEnterPressed", ClearCopyFocus)
    copy:SetScript("OnEscapePressed", ClearCopyFocus)
    copy:Hide()

    local details = {
        { "Email", creator.email },
        { "Twitch & YouTube", creator.name },
        { "Characters", creator.characters },
    }
    for index, detail in ipairs(details) do
        local y = -50 - (index - 1) * 33
        addon.Label(card, detail[1], nil, 12, y - 4, addon.color.dim)
        local value = addon.Label(card, detail[2], nil, 111, y - 4, addon.color.text)
        value:SetPoint("TOPRIGHT", card, "TOPRIGHT", -81, y - 4)
        value:SetWordWrap(true)
        value:SetJustifyH("LEFT")
        local selectDetail = addon.Button(card, "Select", 55, 23)
        selectDetail:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, y)
        selectDetail:SetScript("OnClick", function()
            selected = detail[2]
            copy:SetText(selected)
            copy:Show()
            copy:SetFocus()
            copy:HighlightText()
            status:SetText(detail[1] .. " selected. Press Ctrl+C to copy.")
        end)
    end

    local showOnLogin = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    showOnLogin:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -284)
    showOnLogin:SetSize(23, 23)
    showOnLogin:SetScript("OnClick", function(self)
        addon.db.showLoadCredits = not not self:GetChecked()
    end)
    addon.Label(page, "Show credits in my chat when Triage loads", nil, 29, -289, addon.color.text)
    page:SetScript("OnHide", ClearCopyFocus)
    return function()
        showOnLogin:SetChecked(addon.db.showLoadCredits ~= false)
        ClearCopyFocus()
        selected = nil
        copy:SetText("")
        copy:Hide()
        status:SetText("Select a detail to copy it.")
    end
end

local pages = {
    { key = "spells", label = "Custom spells", build = addon.BuildSpellSettings },
    { key = "icons", label = "Spell icons", build = addon.BuildSpellIconSettings },
    { key = "mouse", label = "Mouse buttons", build = addon.BuildMouseSettings },
    { key = "practice", label = "Practice", build = addon.BuildPracticeSettings },
    { key = "alerts", label = "Range alerts", build = addon.BuildRangeSettings },
    { key = "buffs", label = "Buff coverage", build = addon.BuildBuffSettings },
    { key = "appearance", label = "Appearance", build = BuildAppearance },
    { key = "keybinds", label = "Keybinds", build = BuildKeybinds },
    { key = "profiles", label = "Profiles", build = BuildProfileTransfer },
    { key = "credits", label = "Credits", build = BuildCredits },
}

local function SelectPage(key)
    window.selected = key
    for _, entry in ipairs(pages) do
        local selected = entry.key == key
        if selected and not entry.refresh then
            entry.refresh = entry.build(entry.page)
            if key == "spells" then refreshSpellSettings = entry.refresh end
            if key == "mouse" then refreshMouseSettings = entry.refresh end
            entry.refresh()
        end
        entry.page:SetShown(selected)
        addon.SelectTab(entry.tab, selected)
    end
    if key == "alerts" then addon.ShowRangeChannels() end
end

local function BuildSettings()
    local frame = CreateFrame("Frame", "TriageAegisBeaconSettings", UIParent, "BackdropTemplate")
    frame:SetSize(650, 445)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    addon.StylePanel(frame)
    addon.HeaderBand(frame, 43)
    addon.Label(frame, addon.title, "GameFontHighlightLarge", 16, -12, addon.color.accent)
    local close = addon.Button(frame, "Close", 62, 25)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -9)
    close:SetScript("OnClick", function() frame:Hide() end)

    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 161, -57)
    rule:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 161, 16)
    rule:SetWidth(1)
    rule:SetColorTexture(unpack(addon.color.border))

    for index, entry in ipairs(pages) do
        local tab = addon.Tab(frame, entry.label, 132, 32, true)
        tab:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -61 - (index - 1) * 38)
        tab:SetScript("OnClick", function() SelectPage(entry.key) end)
        entry.tab = tab
        local page = CreateFrame("Frame", nil, frame)
        page:SetPoint("TOPLEFT", frame, "TOPLEFT", 180, -62)
        page:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -22, 17)
        entry.page = page
        page:Hide()
    end

    if UISpecialFrames then
        tinsert(UISpecialFrames, "TriageAegisBeaconSettings")
    end
    frame:Hide()
    return frame
end

function addon.OpenSettings(key)
    window = window or BuildSettings()
    if not window:IsShown() then
        for _, entry in ipairs(pages) do
            if entry.refresh then entry.refresh() end
        end
    end
    SelectPage(key or window.selected or "spells")
    window:Show()
end

function addon.OpenSpellOptions()
    addon.OpenSettings("spells")
end

function addon.OpenSpellIcons()
    addon.OpenSettings("icons")
end

function addon.OpenMouseOptions()
    addon.OpenSettings("mouse")
end

function addon.OpenRangeOptions()
    addon.OpenSettings("alerts")
end

function addon.CloseSettings()
    if window then
        window:Hide()
    end
end
