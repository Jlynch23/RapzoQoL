local addonName = ...
local RB = _G.RapzoBags
if not RB then return end

local Collections = {}
RB.Collections = Collections
RB:RegisterModule("collections", Collections)
Collections.cache = {}
Collections.initialized = false

local function isSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

local function tooltipKnown(itemID)
    if not C_TooltipInfo or type(C_TooltipInfo.GetItemByID) ~= "function" then return false end
    local ok, info = pcall(C_TooltipInfo.GetItemByID, itemID)
    if not ok or type(info) ~= "table" or type(info.lines) ~= "table" then return false end
    for _, line in ipairs(info.lines) do
        if type(line) == "table" then
            -- En contenido restringido el texto puede ser secreto: no compararlo.
            local text = line.leftText
            if ITEM_SPELL_KNOWN and not isSecret(text) and text == ITEM_SPELL_KNOWN then return true end
        end
    end
    return false
end

-- Un objeto sin datos cacheados devuelve nil en GetMountFromItem/GetToyInfo/etc.
-- y se marcaria como "no coleccionable" para siempre. No se cachea hasta que
-- el cliente tenga la informacion.
local function isItemDataReady(itemID)
    if C_Item and type(C_Item.IsItemDataCachedByID) == "function" then
        local ok, cached = pcall(C_Item.IsItemDataCachedByID, itemID)
        if ok then return cached == true end
    end
    return true
end

local function getPetState(itemID)
    if not C_PetJournal or type(C_PetJournal.GetPetInfoByItemID) ~= "function" then return nil end
    local results = {pcall(C_PetJournal.GetPetInfoByItemID, itemID)}
    if not results[1] or results[2] == nil then return nil end
    local speciesID = results[14]
    if speciesID and type(C_PetJournal.GetNumCollectedInfo) == "function" then
        local ok, count = pcall(C_PetJournal.GetNumCollectedInfo, speciesID)
        if ok then return (tonumber(count) or 0) > 0, "Mascota" end
    end
    return false, "Mascota"
end

local function getMountState(itemID)
    if not C_MountJournal or type(C_MountJournal.GetMountFromItem) ~= "function" then return nil end
    local ok, mountID = pcall(C_MountJournal.GetMountFromItem, itemID)
    if not ok or not mountID then return nil end
    if type(C_MountJournal.GetMountInfoByID) ~= "function" then return false, "Montura" end
    local values = {pcall(C_MountJournal.GetMountInfoByID, mountID)}
    if not values[1] then return false, "Montura" end
    return values[12] == true, "Montura"
end

local function getToyState(itemID)
    if not C_ToyBox or type(C_ToyBox.GetToyInfo) ~= "function" then return nil end
    local ok, toyItemID = pcall(C_ToyBox.GetToyInfo, itemID)
    if not ok or not toyItemID then return nil end
    if type(PlayerHasToy) == "function" then
        local known, collected = pcall(PlayerHasToy, itemID)
        if known then return collected == true, "Juguete" end
    end
    return false, "Juguete"
end

local function getHeirloomState(itemID)
    if not C_Heirloom or type(C_Heirloom.IsItemHeirloom) ~= "function" then return nil end
    local ok, isHeirloom = pcall(C_Heirloom.IsItemHeirloom, itemID)
    if not ok or not isHeirloom then return nil end
    if type(C_Heirloom.PlayerHasHeirloom) == "function" then
        local known, collected = pcall(C_Heirloom.PlayerHasHeirloom, itemID)
        if known then return collected == true, "Reliquia" end
    end
    return false, "Reliquia"
end

local function getTransmogSetState(itemID)
    if not C_Item or type(C_Item.GetItemLearnTransmogSet) ~= "function" then return nil end
    local ok, setID = pcall(C_Item.GetItemLearnTransmogSet, itemID)
    if not ok or not setID then return nil end
    if not C_Transmog or type(C_Transmog.GetAllSetAppearancesByID) ~= "function" then return false, "Conjunto" end
    local got, appearances = pcall(C_Transmog.GetAllSetAppearancesByID, setID)
    if not got or type(appearances) ~= "table" or #appearances == 0 then return false, "Conjunto" end
    if not C_TransmogCollection or type(C_TransmogCollection.PlayerHasTransmog) ~= "function" then return false, "Conjunto" end
    for _, appearance in ipairs(appearances) do
        local appearanceItemID = type(appearance) == "table" and appearance.itemID or nil
        if appearanceItemID then
            local known, collected = pcall(C_TransmogCollection.PlayerHasTransmog, appearanceItemID)
            if not known or not collected then return false, "Conjunto" end
        end
    end
    return true, "Conjunto"
end

local function getTransmogState(itemID)
    if not C_TransmogCollection or type(C_TransmogCollection.GetItemInfo) ~= "function" then return nil end
    local ok, firstValue = pcall(C_TransmogCollection.GetItemInfo, itemID)
    if not ok or firstValue == nil then return nil end
    if type(C_TransmogCollection.PlayerHasTransmog) == "function" then
        local known, collected = pcall(C_TransmogCollection.PlayerHasTransmog, itemID)
        if known then return collected == true, "Apariencia" end
    end
    return false, "Apariencia"
end

local function getRecipeState(itemID)
    if not C_Item or type(C_Item.GetItemInfoInstant) ~= "function" then return nil end
    local values = {pcall(C_Item.GetItemInfoInstant, itemID)}
    if not values[1] then return nil end
    local classID = tonumber(values[7])
    if Enum and Enum.ItemClass and classID == Enum.ItemClass.Recipe then return tooltipKnown(itemID), "Receta" end
    if Enum and Enum.ItemClass and classID == Enum.ItemClass.Consumable and C_TooltipInfo and type(C_TooltipInfo.GetItemByID) == "function" then
        local ok, info = pcall(C_TooltipInfo.GetItemByID, itemID)
        if ok and type(info) == "table" and type(info.lines) == "table" then
            for _, line in ipairs(info.lines) do
                if type(line) == "table" and Enum.TooltipDataLineType and line.type == Enum.TooltipDataLineType.ItemSpellTriggerLearn then
                    return tooltipKnown(itemID), "Receta"
                end
            end
        end
    end
    return nil
end

local function getHousingState(itemID)
    if not C_HousingCatalog or type(C_HousingCatalog.GetCatalogEntryInfoByItem) ~= "function" then return nil end
    local ok, info = pcall(C_HousingCatalog.GetCatalogEntryInfoByItem, itemID)
    if not ok or type(info) ~= "table" then return nil end
    -- HousingCatalogEntryInfo (12.x) no tiene `quantity`: lo poseido es lo
    -- almacenado mas lo colocado. `quantity` se deja como fallback por si
    -- Blizzard lo anade en el futuro.
    local stored = tonumber(info.totalNumStored) or 0
    local placed = tonumber(info.totalNumPlaced) or 0
    local quantity = tonumber(info.quantity) or 0
    return (stored + placed + quantity) > 0, "Decoracion"
end

local detectors = {getToyState, getMountState, getPetState, getHeirloomState, getRecipeState, getTransmogSetState, getTransmogState, getHousingState}

function Collections:ClearCache()
    wipe(self.cache)
end

function Collections:InvalidateItem(itemID)
    itemID = tonumber(itemID)
    if itemID then self.cache[itemID] = nil end
end

function Collections:GetState(itemID)
    if not RB:IsFeatureEnabled("collections") then return false, nil end
    itemID = tonumber(itemID)
    if not itemID then return false, nil end
    local cached = self.cache[itemID]
    if type(cached) == "table" then return cached.collected == true, cached.kind or nil end
    local ready = isItemDataReady(itemID)
    for _, detector in ipairs(detectors) do
        local collected, kind = detector(itemID)
        if collected ~= nil then
            if ready then
                self.cache[itemID] = { collected = collected == true, kind = kind }
            end
            return collected == true, kind
        end
    end
    if tooltipKnown(itemID) then
        if ready then
            self.cache[itemID] = { collected = true, kind = "Aprendido" }
        end
        return true, "Aprendido"
    end
    if ready then
        self.cache[itemID] = { collected = false, kind = false }
    end
    return false, nil
end

function Collections:Initialize()
    if self.initialized then return end
    self.initialized = true
    local frame = CreateFrame("Frame")
    self.eventFrame = frame
    for _, event in ipairs({"TOYS_UPDATED", "PET_JOURNAL_LIST_UPDATE", "NEW_MOUNT_ADDED", "TRANSMOG_COLLECTION_UPDATED", "HEIRLOOMS_UPDATED", "NEW_RECIPE_LEARNED", "GET_ITEM_INFO_RECEIVED"}) do
        RB:RegisterEventSafe(frame, event)
    end
    frame:SetScript("OnEvent", function(_, event, arg1)
        if event == "GET_ITEM_INFO_RECEIVED" then
            -- Llega una vez por objeto: invalidar solo ese objeto, no todo el cache.
            Collections:InvalidateItem(arg1)
        else
            Collections:ClearCache()
        end
    end)
    RB:RegisterCommand("collections", function(rest)
        rest = string.lower(tostring(rest or ""))
        if rest == "on" then RB:SetFeatureEnabled("collections", true)
        elseif rest == "off" then RB:SetFeatureEnabled("collections", false)
        elseif rest == "clear" then Collections:ClearCache(); RB:Print("Cache de colecciones limpiada.")
        else RB:Print("Colecciones: " .. (RB:IsFeatureEnabled("collections") and "ON" or "OFF") .. " | Uso: /rapzo collections on|off|clear") end
    end, "/rapzo collections on|off - activa/desactiva deteccion de coleccionables")
end

Collections:Initialize()
