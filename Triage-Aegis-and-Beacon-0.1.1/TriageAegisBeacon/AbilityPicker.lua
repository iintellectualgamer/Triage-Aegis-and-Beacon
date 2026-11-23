local _, addon = ...
local Spell = addon.Spell

local picker
local visibleRows, stride = 9, 25
local modes = { "All abilities", "Assignable", "Talents" }

local function BuildPicker(page)
    local frame = CreateFrame("Frame", nil, page, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", page, "TOPLEFT", -8, 9)
    frame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 8, -3)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:EnableMouse(true)
    addon.StylePanel(frame)
    addon.Label(frame, "Spells and talents", "GameFontHighlightLarge", 14, -12, addon.color.accent)
    local close = addon.Button(frame, "Close", 55, 22)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -13, -9)
    close:SetScript("OnClick", function() frame:Hide() end)

    local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    search:SetSize(183, 23)
    search:SetPoint("TOPLEFT", frame, "TOPLEFT", 66, -42)
    search:SetAutoFocus(false)
    search:SetMaxLetters(100)
    addon.Tooltip(search, "Search abilities", "Enter a spell or talent name, a spell ID, or a source such as Pet.")
    local filter = addon.Button(frame, modes[1], 103, 23)
    filter:SetPoint("LEFT", search, "RIGHT", 10, 0)
    addon.Label(frame, "Search", nil, 14, -48, addon.color.text)

    local status = addon.Label(frame, "", nil, 14, -72, addon.color.dim)
    local rows, filtered, first, mode, send = {}, {}, 1, 1
    local prev = addon.Button(frame, "Previous", 79, 23)
    prev:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 13, 9)
    local nextPage = addon.Button(frame, "Next", 79, 23)
    nextPage:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -13, 9)
    local count = addon.Label(frame, "", nil, 0, 0, addon.color.dim)
    count:ClearAllPoints()
    count:SetPoint("BOTTOM", frame, "BOTTOM", 0, 15)

    local function Draw()
        for index, row in ipairs(rows) do
            local entry = filtered[first + index - 1]
            row.entry = entry
            row:SetShown(entry ~= nil)
            if entry then
                local detail = entry.id and Spell.GetSpellSubtext(entry.id)
                local ranked = detail and detail:find("%d")
                row.name:SetText(ranked and (entry.name .. " (" .. detail .. ")") or entry.name)
                row.name:SetTextColor(unpack(entry.state == "Assignable" and addon.color.text or addon.color.dim))
                row.state:SetText(entry.state)
                row.source:SetText(entry.source)
            end
        end
        local last = math.min(first + visibleRows - 1, #filtered)
        count:SetText(last == 0 and "No matching abilities" or ("%d–%d of %d"):format(first, last, #filtered))
        prev:SetEnabled(first > 1)
        nextPage:SetEnabled(last < #filtered)
    end

    for index = 1, visibleRows do
        local row = addon.Button(frame, nil, 432, stride - 2)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 13, -91 - (index - 1) * stride)
        row.name = addon.Label(row, "", nil, 8, -6)
        row.name:SetWidth(241)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.source = addon.Label(row, "", nil, 256, -6, addon.color.dim)
        row.state = addon.Label(row, "", nil, 346, -6, addon.color.accent)
        row:SetScript("OnClick", function(self)
            local entry = self.entry
            if entry and entry.state == "Assignable" and send and send(entry.id) then frame:Hide() end
        end)
        row:SetScript("OnEnter", function(self)
            local entry = self.entry
            if not entry then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if entry.id and GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(entry.id)
            else GameTooltip:SetText(entry.name) end
            if entry.id then GameTooltip:AddLine("Spell ID " .. entry.id) end
            GameTooltip:AddLine(entry.source .. " · " .. entry.state)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[index] = row
    end

    local function Filter()
        wipe(filtered)
        first = 1
        local query = search:GetText():lower():match("^%s*(.-)%s*$")
        local id = tonumber(query)
        for _, entry in ipairs(addon.AbilityEntries()) do
            local shown = mode == 1 or (mode == 2 and entry.state == "Assignable")
                or (mode == 3 and entry.source ~= "Spellbook" and entry.source ~= "Pet")
            if shown and (query == "" or (id and entry.id == id)
                or entry.name:lower():find(query, 1, true) or entry.source:lower():find(query, 1, true)) then
                filtered[#filtered + 1] = entry
            end
        end
        status:SetText("Choose an assignable spell for this field.")
        Draw()
    end

    search:SetScript("OnTextChanged", Filter)
    search:SetScript("OnEscapePressed", function() frame:Hide() end)
    search:SetScript("OnEnterPressed", function() search:ClearFocus() end)
    filter:SetScript("OnClick", function()
        mode = mode % #modes + 1
        filter.label:SetText(modes[mode])
        Filter()
    end)
    prev:SetScript("OnClick", function() first = first - visibleRows; Draw() end)
    nextPage:SetScript("OnClick", function() first = first + visibleRows; Draw() end)
    frame:SetScript("OnHide", function()
        search:ClearFocus()
        GameTooltip:Hide()
        send = nil
        if picker == frame then picker = nil end
    end)
    frame.Refresh = Filter
    frame.Open = function(choose)
        send = choose
        mode = 1
        filter.label:SetText(modes[mode])
        search:SetText("")
        Filter()
        frame:Show()
        search:SetFocus()
    end
    frame:Hide()
    return frame
end

function addon.OpenAbilityPicker(page, choose)
    if picker then picker:Hide() end
    if not page.abilityPicker then page.abilityPicker = BuildPicker(page) end
    picker = page.abilityPicker
    picker.Open(choose)
end

function addon.RefreshAbilityPicker()
    if picker and picker:IsVisible() then picker.Refresh() end
end
