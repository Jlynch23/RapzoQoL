local addonName = ...
local RB = _G.RapzoBags
if not RB then return end


local Tooltip = {}
RB.Tooltip = Tooltip
RB:RegisterModule("tooltip", Tooltip)
Tooltip.initialized = false

local function isSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

local function extractItemID(tooltip, data)
    if type(data) == "table" and data.id and not isSecret(data.id) then
        local id = tonumber(data.id)
        if id then return id end
    end

    if tooltip and tooltip.GetItem then
        local ok, _, link = pcall(tooltip.GetItem, tooltip)
        if ok and link and not isSecret(link) then
            if C_Item and C_Item.GetItemInfoInstant then
                local success, itemID = pcall(C_Item.GetItemInfoInstant, link)
                if success and tonumber(itemID) then
                    return tonumber(itemID)
                end
            end
            if type(link) == "string" then
                return tonumber(string.match(link, "item:(%d+)"))
            end
        end
    end

    return nil
end

local function getClassColor(classFile)
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        return c.r or 1, c.g or 1, c.b or 1
    end
    return 0.8, 0.8, 0.8
end

local function locationText(entry)
    local parts = {}
    if (entry.bags or 0) > 0 then parts[#parts + 1] = "Bolsas: " .. entry.bags end
    if (entry.bank or 0) > 0 then parts[#parts + 1] = "Banco: " .. entry.bank end
    if (entry.equipped or 0) > 0 then parts[#parts + 1] = "Equipado: " .. entry.equipped end
    return table.concat(parts, "  ·  ")
end

local function isMerchantTooltip(tooltip)
    if not tooltip or type(tooltip.GetOwner) ~= "function" then
        return false
    end

    local ok, owner = pcall(tooltip.GetOwner, tooltip)
    if not ok or not owner then
        return false
    end

    local current = owner
    for _ = 1, 8 do
        if MerchantFrame and current == MerchantFrame then
            return true
        end
        if type(current.GetName) == "function" then
            local nameOk, name = pcall(current.GetName, current)
            if nameOk and type(name) == "string" and name:match("^MerchantItem%d+") then
                return true
            end
        end
        if type(current.GetParent) ~= "function" then break end
        local parentOk, parent = pcall(current.GetParent, current)
        if not parentOk or not parent or parent == current then break end
        current = parent
    end

    return false
end

local function getItemBindEnum(name, fallback)
    if Enum and Enum.ItemBind and tonumber(Enum.ItemBind[name]) ~= nil then
        return tonumber(Enum.ItemBind[name])
    end
    return fallback
end

local function isCharacterBoundMetadata(metadata)
    if not metadata then return false end
    local bindType = tonumber(metadata.bindType)
    if bindType == nil then return false end

    -- Static item metadata can safely identify Bind on Pickup and quest-bound
    -- items. Bind on Equip/Use items are deliberately excluded because a
    -- stored copy is not necessarily bound yet.
    return bindType == getItemBindEnum("OnAcquire", 1)
        or bindType == getItemBindEnum("Quest", 4)
end

local function currentCharacterFirst(characters)
    local ordered = {}
    local currentKey = RB.GetCharacterKey and RB:GetCharacterKey() or nil
    local currentEntry

    for _, entry in ipairs(characters or {}) do
        if currentKey and entry.key == currentKey then
            currentEntry = entry
        else
            ordered[#ordered + 1] = entry
        end
    end

    if currentEntry then
        table.insert(ordered, 1, currentEntry)
    end

    return ordered
end

local function addCharacterLine(tooltip, entry, showLocations)
    local r, g, b = getClassColor(entry.class)
    local right = tostring(entry.total)

    if showLocations then
        local locations = locationText(entry)
        if locations ~= "" then
            right = string.format("%d  |cff9ca3af%s|r", entry.total, locations)
        end
    end

    tooltip:AddDoubleLine(entry.name or entry.key, right, r, g, b, 1, 1, 1)
end

-- mUI adds its own blue/yellow item ID line to item tooltips and does not
-- currently expose a setting to disable only that line. When RapzoBags is
-- responsible for Item ID metadata, keep mUI's styling/NPC/spell IDs intact
-- but skip only mUI's item ID callback to avoid duplicate IDs.
local function shouldRapzoBagsOwnItemID()
    local db = RB:EnsureDB()
    return db
        and db.settings
        and RB:IsFeatureEnabled("tooltip")
        and db.settings.tooltip
        and db.settings.showItemID ~= false
end

local function patchMUIItemID()
    local mui = rawget(_G, "mUI")
    if not mui or type(mui.GetModule) ~= "function" then
        return false
    end

    local ok, style = pcall(mui.GetModule, mui, "mUI.Tooltips.Style", true)
    if not ok or not style or type(style.OnTooltipSetItem) ~= "function" then
        return false
    end

    if style.OnTooltipSetItem == style.__RapzoBagsOnTooltipSetItem then
        return true
    end

    local originalOnTooltipSetItem = style.OnTooltipSetItem
    local wrappedOnTooltipSetItem = function(self, tooltip)
        if shouldRapzoBagsOwnItemID() then
            return
        end
        return originalOnTooltipSetItem(self, tooltip)
    end

    style.__RapzoBagsOnTooltipSetItem = wrappedOnTooltipSetItem
    style.OnTooltipSetItem = wrappedOnTooltipSetItem
    return true
end

local muiCompatFrame = CreateFrame("Frame")
muiCompatFrame:RegisterEvent("ADDON_LOADED")
muiCompatFrame:RegisterEvent("PLAYER_LOGIN")
muiCompatFrame:SetScript("OnEvent", function(self, event)
    if patchMUIItemID() then
        self:UnregisterEvent("ADDON_LOADED")
    end

    if event == "PLAYER_LOGIN" then
        -- Re-apply after all addon initialization in case mUI rebuilt the
        -- tooltip module between ADDON_LOADED and PLAYER_LOGIN.
        patchMUIItemID()
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

patchMUIItemID()

function Tooltip:GetItemMetadata(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end

    local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if type(getItemInfo) ~= "function" then return nil end

    local values = {pcall(getItemInfo, itemID)}
    if not values[1] then return nil end

    -- pcall adds its success boolean at index 1, so every GetItemInfo return
    -- value is shifted by one in this table.
    local name = values[2]
    local itemType = values[7]
    local itemSubType = values[8]
    local itemStackCount = tonumber(values[9])
    local sellPrice = tonumber(values[12]) or 0
    local classID = tonumber(values[13])
    local subclassID = tonumber(values[14])
    local bindType = tonumber(values[15])
    local expacID = tonumber(values[16])
    local isCraftingReagent = values[18] == true

    if not name and C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end

    local expansionName
    if expacID ~= nil then
        expansionName = _G["EXPANSION_NAME" .. expacID] or ("Expansion " .. expacID)
    end

    local typeText = itemSubType or itemType
    if itemType and itemSubType and itemType ~= itemSubType then
        typeText = itemType .. " · " .. itemSubType
    end

    return {
        name = name,
        itemType = itemType,
        itemSubType = itemSubType,
        itemStackCount = itemStackCount,
        sellPrice = sellPrice,
        classID = classID,
        subclassID = subclassID,
        bindType = bindType,
        isCraftingReagent = isCraftingReagent,
        typeText = typeText,
        expacID = expacID,
        expansionName = expansionName,
    }
end

function Tooltip:GetExpansionInfo(itemID)
    local info = self:GetItemMetadata(itemID)
    if not info then return nil, nil end
    return info.expacID, info.expansionName
end

function Tooltip:AddItemInfo(tooltip, itemID)
    local db = RB:EnsureDB()
    if not RB:IsFeatureEnabled("tooltip") or not db.settings.tooltip then return end
    if isMerchantTooltip(tooltip) then return end

    local metadata = self:GetItemMetadata(itemID)
    local aggregate = RB:GetItemAggregate(itemID)
    local hasCounts = aggregate and aggregate.total and aggregate.total > 0
    local characterBound = isCharacterBoundMetadata(metadata)

    local showExpansion = db.settings.showItemExpansion ~= false and metadata and metadata.expansionName
    local showType = db.settings.showItemType ~= false and metadata and metadata.typeText
    local showID = db.settings.showItemID ~= false

    if not showExpansion and not showType and not showID and not hasCounts then
        return
    end

    tooltip:AddLine(" ")
    tooltip:AddLine("Rapzo QoL", 0.22, 0.74, 0.97)

    if showExpansion then
        tooltip:AddDoubleLine("Expansion", metadata.expansionName, 1.00, 0.82, 0.35, 0.95, 0.95, 0.95)
    end
    if showType then
        tooltip:AddDoubleLine("Tipo", metadata.typeText, 0.66, 0.80, 0.95, 0.90, 0.90, 0.90)
    end
    if showID then
        tooltip:AddDoubleLine("Item ID", tostring(itemID), 0.55, 0.60, 0.68, 0.80, 0.80, 0.80)
    end

    if not hasCounts then return end

    tooltip:AddLine(" ")

    if characterBound then
        -- A Bind on Pickup/quest item cannot be treated as one shared account
        -- stock pool. Keep the useful per-character data, put the current
        -- character first and avoid the misleading aggregate Total line.
        tooltip:AddLine("En tus personajes", 0.55, 0.82, 1.00)

        local configuredLimit = math.max(1, tonumber(db.settings.maxCharacters) or 12)
        local boundLimit = metadata and metadata.isCraftingReagent and 8 or 4
        local maxCharacters = math.min(configuredLimit, boundLimit)
        local characters = currentCharacterFirst(aggregate.characters)
        local shown = 0

        for _, entry in ipairs(characters) do
            if shown >= maxCharacters then break end
            shown = shown + 1
            addCharacterLine(tooltip, entry, db.settings.showLocations)
        end

        if #characters > shown then
            tooltip:AddDoubleLine("Otros personajes", "+" .. (#characters - shown), 0.65, 0.65, 0.65, 0.65, 0.65, 0.65)
        end

        if aggregate.accountBank > 0 then
            tooltip:AddDoubleLine("Banco de banda de guerra", tostring(aggregate.accountBank), 0.90, 0.77, 0.37, 1, 1, 1)
        end

        tooltip:AddLine("Ligado al personaje · las cantidades no se comparten", 0.72, 0.75, 0.80)
        return
    end

    tooltip:AddLine("En tu cuenta", 0.55, 0.82, 1.00)

    local maxCharacters = tonumber(db.settings.maxCharacters) or 12
    local shown = 0
    for _, entry in ipairs(aggregate.characters) do
        if shown >= maxCharacters then break end
        shown = shown + 1
        addCharacterLine(tooltip, entry, db.settings.showLocations)
    end

    if #aggregate.characters > shown then
        tooltip:AddDoubleLine("Otros personajes", "+" .. (#aggregate.characters - shown), 0.65, 0.65, 0.65, 0.65, 0.65, 0.65)
    end

    if aggregate.accountBank > 0 then
        tooltip:AddDoubleLine("Banco de banda de guerra", tostring(aggregate.accountBank), 0.90, 0.77, 0.37, 1, 1, 1)
    end

    if db.settings.showTotal then
        tooltip:AddDoubleLine("Total", tostring(aggregate.total), 0.22, 0.74, 0.97, 1, 1, 1)
    end
end

function Tooltip:Initialize()
    if self.initialized then return end
    self.initialized = true

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            local itemID = extractItemID(tooltip, data)
            if itemID then
                Tooltip:AddItemInfo(tooltip, itemID)
            end
        end)
    else
        RB:Print("El procesador moderno de tooltips no esta disponible en este cliente.")
    end
end


local function setBooleanSetting(setting, value, onText, offText, usage)
    value = string.lower(tostring(value or ""))
    local db = RB:EnsureDB()
    if value == "on" then
        db.settings[setting] = true
        if setting == "tooltip" then RB:SetFeatureEnabled("tooltip", true, true) end
        RB:Print(onText)
    elseif value == "off" then
        db.settings[setting] = false
        if setting == "tooltip" then RB:SetFeatureEnabled("tooltip", false, true) end
        RB:Print(offText)
    else
        RB:Print(usage)
    end
end

RB:RegisterCommand("tooltip", function(rest)
    setBooleanSetting("tooltip", rest, "Tooltips activados.", "Tooltips desactivados.", "Uso: /rapzo tooltip on|off")
end, "/rapzo tooltip on|off - activa/desactiva el tooltip avanzado")
RB:RegisterCommand("expansion", function(rest)
    setBooleanSetting("showItemExpansion", rest, "Expansion activada.", "Expansion desactivada.", "Uso: /rapzo expansion on|off")
end, "/rapzo expansion on|off - muestra/oculta la expansion")
RB:RegisterCommand("expa", RB.commands.expansion)
RB:RegisterCommand("itemtype", function(rest)
    setBooleanSetting("showItemType", rest, "Tipo de objeto activado.", "Tipo de objeto desactivado.", "Uso: /rapzo itemtype on|off")
end, "/rapzo itemtype on|off - muestra/oculta el tipo del objeto")
RB:RegisterCommand("tipo", RB.commands.itemtype)
RB:RegisterCommand("itemid", function(rest)
    setBooleanSetting("showItemID", rest, "Item ID activado.", "Item ID desactivado.", "Uso: /rapzo itemid on|off")
end, "/rapzo itemid on|off - muestra/oculta el Item ID")
RB:RegisterCommand("id", RB.commands.itemid)
RB:RegisterCommand("locations", function(rest)
    setBooleanSetting("showLocations", rest, "Ubicaciones detalladas activadas.", "Ubicaciones detalladas desactivadas.", "Uso: /rapzo locations on|off")
end, "/rapzo locations on|off - muestra/oculta ubicaciones detalladas")

Tooltip:Initialize()
