local addonName = ...
local RB = _G.RapzoBags
if not RB then return end


local Search = {}
RB.Search = Search
RB:RegisterModule("search", Search)
Search.initialized = false
Search.frame = nil
Search.selectedItemID = nil

local MAX_RESULTS = 250
local ROW_HEIGHT = 42

local function lowerSafe(value)
    if type(value) ~= "string" then return "" end
    return string.lower(value)
end

local function trim(value)
    value = tostring(value or "")
    value = value:gsub("^%s+", "")
    value = value:gsub("%s+$", "")
    return value
end

local function formatMoney(value)
    value = tonumber(value) or 0
    local formatter = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    if type(formatter) == "function" then
        local ok, text = pcall(formatter, value)
        if ok and text then return text end
    end
    return tostring(value)
end

local function getItemInfo(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end

    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if type(getInfo) ~= "function" then return nil end

    local values = {pcall(getInfo, itemID)}
    if not values[1] then return nil end

    local name = values[2]
    local link = values[3]
    local quality = values[4]
    local itemType = values[7]
    local itemSubType = values[8]
    local icon = values[11]
    local expacID = tonumber(values[16])

    if not name and C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end

    return {
        name = name,
        link = link,
        quality = quality,
        itemType = itemType,
        itemSubType = itemSubType,
        icon = icon,
        expacID = expacID,
    }
end

local function itemDisplayName(link, itemID)
    local info = getItemInfo(itemID)
    if info and info.name then
        return info.name, info.link or link, info
    end

    if type(link) == "string" then
        local name = string.match(link, "%[(.-)%]")
        if name and name ~= "" then return name, link, info end
    end
    return "Item " .. tostring(itemID), link, info
end

local function getClassHex(classFile)
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        if c.colorStr then return c.colorStr end
        return string.format("ff%02x%02x%02x", math.floor((c.r or 1) * 255 + 0.5), math.floor((c.g or 1) * 255 + 0.5), math.floor((c.b or 1) * 255 + 0.5))
    end
    return "ffffffff"
end

local function locationLong(entry)
    local parts = {}
    if (entry.bags or 0) > 0 then parts[#parts + 1] = string.format("Bolsas %d", entry.bags) end
    if (entry.bank or 0) > 0 then parts[#parts + 1] = string.format("Banco %d", entry.bank) end
    if (entry.equipped or 0) > 0 then parts[#parts + 1] = string.format("Equipado %d", entry.equipped) end
    return table.concat(parts, "  ·  ")
end

function Search:GetMatches(query)
    query = trim(lowerSafe(query))
    local numericQuery = tonumber(query)
    local matches = {}

    for _, itemID in ipairs(RB:GetAllKnownItemIDs()) do
        local storedLink = RB:GetKnownItemLink(itemID)
        local display, link, info = itemDisplayName(storedLink, itemID)
        local matched = false

        if numericQuery then
            matched = itemID == numericQuery
        elseif query == "" then
            matched = true
        else
            matched = string.find(lowerSafe(display), query, 1, true) ~= nil
                or string.find(tostring(itemID), query, 1, true) ~= nil
        end

        if matched then
            local aggregate = RB:GetItemAggregate(itemID)
            matches[#matches + 1] = {
                itemID = itemID,
                link = link or storedLink,
                name = display,
                icon = info and info.icon,
                total = aggregate and aggregate.total or 0,
            }
        end
    end

    table.sort(matches, function(a, b)
        if a.total ~= b.total then
            return a.total > b.total
        end
        if a.name == b.name then
            return a.itemID < b.itemID
        end
        return a.name < b.name
    end)

    return matches
end

function Search:CreateResultRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT - 2)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
    row:SetPoint("RIGHT", parent, "RIGHT", -4, 0)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.10, index % 2 == 0 and 0.46 or 0.28)
    row.bg = bg

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(0.15, 0.55, 0.85, 0.16)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("LEFT", row, "LEFT", 5, 0)
    icon:SetTexture(134400)
    row.icon = icon

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -3)
    name:SetPoint("RIGHT", row, "RIGHT", -48, 0)
    name:SetJustifyH("LEFT")
    name:SetText("Item")
    row.itemName = name

    local id = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    id:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 2)
    id:SetJustifyH("LEFT")
    row.itemIDText = id

    local count = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    count:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    count:SetJustifyH("RIGHT")
    row.count = count

    row:SetScript("OnClick", function(self)
        if self.itemID then
            Search:SelectItem(self.itemID)
        end
    end)

    row:SetScript("OnEnter", function(self)
        if self.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.link)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return row
end

function Search:CreateFrame()
    if self.frame then
        return self.frame
    end

    local frame = CreateFrame("Frame", "RapzoQoLSearchFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(760, 520)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 6, 0)
    frame.title:SetText("Rapzo QoL - Buscador global")

    local edit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    edit:SetSize(450, 28)
    edit:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -42)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(80)
    edit:SetTextInsets(6, 6, 0, 0)
    frame.edit = edit

    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(104, 26)
    button:SetPoint("LEFT", edit, "RIGHT", 10, 0)
    button:SetText("Buscar")
    frame.searchButton = button

    local countLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countLabel:SetPoint("LEFT", button, "RIGHT", 12, 0)
    countLabel:SetTextColor(0.55, 0.75, 0.95)
    countLabel:SetText("0 resultados")
    frame.countLabel = countLabel

    local leftPanel = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    leftPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -78)
    leftPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 14)
    leftPanel:SetWidth(330)
    frame.leftPanel = leftPanel

    local rightPanel = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 8, 0)
    rightPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)
    frame.rightPanel = rightPanel

    local scroll = CreateFrame("ScrollFrame", "RapzoQoLSearchScrollFrame", leftPanel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 5, -6)
    scroll:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -27, 6)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(296, 1)
    scroll:SetScrollChild(child)
    frame.scroll = scroll
    frame.scrollChild = child
    frame.resultRows = {}

    local detailIcon = rightPanel:CreateTexture(nil, "ARTWORK")
    detailIcon:SetSize(48, 48)
    detailIcon:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 14, -14)
    detailIcon:SetTexture(134400)
    frame.detailIcon = detailIcon

    local detailName = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    detailName:SetPoint("TOPLEFT", detailIcon, "TOPRIGHT", 12, -2)
    detailName:SetPoint("RIGHT", rightPanel, "RIGHT", -14, 0)
    detailName:SetJustifyH("LEFT")
    detailName:SetText("Selecciona un objeto")
    frame.detailName = detailName

    local detailMeta = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detailMeta:SetPoint("TOPLEFT", detailName, "BOTTOMLEFT", 0, -5)
    detailMeta:SetPoint("RIGHT", rightPanel, "RIGHT", -14, 0)
    detailMeta:SetJustifyH("LEFT")
    detailMeta:SetText("Busca un material, equipo o item por nombre o ID.")
    frame.detailMeta = detailMeta

    local divider = rightPanel:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 12, -76)
    divider:SetPoint("RIGHT", rightPanel, "RIGHT", -12, 0)
    divider:SetColorTexture(0.45, 0.55, 0.65, 0.35)

    local detailOutput = CreateFrame("ScrollingMessageFrame", nil, rightPanel)
    detailOutput:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 14, -88)
    detailOutput:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -14, 14)
    detailOutput:SetFontObject(GameFontHighlightSmall)
    detailOutput:SetJustifyH("LEFT")
    detailOutput:SetFading(false)
    detailOutput:SetMaxLines(100)
    detailOutput:EnableMouseWheel(true)
    detailOutput:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)
    frame.detailOutput = detailOutput

    local function runSearch()
        Search:RenderSearch(edit:GetText() or "")
    end

    button:SetScript("OnClick", runSearch)
    edit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        runSearch()
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    frame:Hide()
    self.frame = frame
    return frame
end

function Search:SelectItem(itemID)
    itemID = tonumber(itemID)
    if not itemID then return end

    local frame = self:CreateFrame()
    local aggregate = RB:GetItemAggregate(itemID)
    local link = RB:GetKnownItemLink(itemID)
    local name, resolvedLink, info = itemDisplayName(link, itemID)
    link = resolvedLink or link
    info = info or getItemInfo(itemID) or {}

    self.selectedItemID = itemID
    frame.detailName:SetText(link or name)
    frame.detailIcon:SetTexture(info.icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)) or 134400)

    local metadata = {}
    if info.expacID ~= nil then
        metadata[#metadata + 1] = _G["EXPANSION_NAME" .. info.expacID] or ("Expansion " .. info.expacID)
    end
    local typeText = info.itemSubType or info.itemType
    if info.itemType and info.itemSubType and info.itemType ~= info.itemSubType then
        typeText = info.itemType .. " · " .. info.itemSubType
    end
    if typeText then metadata[#metadata + 1] = typeText end
    metadata[#metadata + 1] = "ID " .. itemID
    frame.detailMeta:SetText(table.concat(metadata, "   |   "))

    local output = frame.detailOutput
    output:Clear()
    output:AddMessage("|cff38bdf8UBICACIONES EN TU CUENTA|r")
    output:AddMessage(" ")

    if not aggregate or (aggregate.total or 0) <= 0 then
        output:AddMessage("No hay cantidades guardadas para este objeto.")
        return
    end

    for _, entry in ipairs(aggregate.characters or {}) do
        local loc = locationLong(entry)
        local color = getClassHex(entry.class)
        local realmSuffix = entry.realm and entry.realm ~= RB:GetRealmNameSafe() and ("-" .. entry.realm) or ""
        output:AddMessage(string.format("|c%s%s%s|r    |cffffffff%d|r", color, entry.name or entry.key, realmSuffix, entry.total or 0))
        if loc ~= "" then
            output:AddMessage("   |cff9ca3af" .. loc .. "|r")
        end
        output:AddMessage(" ")
    end

    if (aggregate.accountBank or 0) > 0 then
        output:AddMessage(string.format("|cffe7c75fBanco de banda de guerra|r    |cffffffff%d|r", aggregate.accountBank))
        output:AddMessage(" ")
    end

    output:AddMessage(string.format("|cff38bdf8TOTAL|r    |cffffffff%d|r", aggregate.total or 0))
end

function Search:RenderSearch(query)
    local frame = self:CreateFrame()
    local matches = self:GetMatches(query)
    local visibleCount = math.min(#matches, MAX_RESULTS)

    frame.countLabel:SetText(string.format("%d resultado%s", #matches, #matches == 1 and "" or "s"))

    for i = 1, visibleCount do
        local row = frame.resultRows[i]
        if not row then
            row = self:CreateResultRow(frame.scrollChild, i)
            frame.resultRows[i] = row
        end

        local result = matches[i]
        row.itemID = result.itemID
        row.link = result.link
        row.itemName:SetText(result.link or result.name)
        row.itemIDText:SetText("ID " .. result.itemID)
        row.count:SetText("|cff38bdf8x" .. tostring(result.total) .. "|r")
        local icon = result.icon
        if not icon and C_Item and type(C_Item.GetItemIconByID) == "function" then
            local ok, value = pcall(C_Item.GetItemIconByID, result.itemID)
            if ok then icon = value end
        end
        row.icon:SetTexture(icon or 134400)
        row:Show()
    end

    for i = visibleCount + 1, #frame.resultRows do
        frame.resultRows[i]:Hide()
    end

    frame.scrollChild:SetHeight(math.max(1, visibleCount * ROW_HEIGHT))
    frame.scroll:SetVerticalScroll(0)

    if #matches == 0 then
        frame.detailName:SetText("Sin resultados")
        frame.detailMeta:SetText("No encontre objetos guardados con ese criterio.")
        frame.detailIcon:SetTexture(134400)
        frame.detailOutput:Clear()
    elseif matches[1] then
        self:SelectItem(matches[1].itemID)
    end
end

function Search:Show(query)
    if not RB:IsFeatureEnabled("search") then
        RB:Print("El modulo Search esta desactivado en Rapzo QoL Config.")
        return
    end
    local frame = self:CreateFrame()
    frame:Show()
    frame:Raise()
    if query and trim(query) ~= "" then
        frame.edit:SetText(query)
        self:RenderSearch(query)
    else
        frame.edit:SetFocus()
        self:RenderSearch(frame.edit:GetText() or "")
    end
end

function Search:ShowGold()
    local db = RB:EnsureDB()
    RB:Print("Oro guardado por personaje:")
    local entries = {}
    for key, character in pairs(db.characters) do
        entries[#entries + 1] = {
            key = key,
            name = character.name or key,
            money = tonumber(character.money) or 0,
        }
    end
    table.sort(entries, function(a, b) return a.money > b.money end)
    for _, entry in ipairs(entries) do
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s: %s", entry.name, formatMoney(entry.money)))
    end
    DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cff38bdf8Total:|r %s", formatMoney(RB:GetTotalMoney())))
end


function Search:Initialize()
    if self.initialized then return end
    self.initialized = true

    RB:RegisterCommand("search", function(rest) Search:Show(rest) end, "/rapzo search <texto> - busca en todos tus personajes y bancos")
    RB:RegisterCommand("find", function(rest) Search:Show(rest) end)
    RB:RegisterCommand("gold", function() Search:ShowGold() end, "/rapzo gold - muestra el oro guardado por personaje")

    RB:SetDefaultAction(function()
        if RB:IsFeatureEnabled("search") then Search:Show() else RB:PrintHelp() end
    end)
end

Search:Initialize()
