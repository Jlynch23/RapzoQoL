local _, RB = ...

local Scanner = {}
RB.Scanner = Scanner

Scanner.frame = CreateFrame("Frame")
Scanner.bankOpen = false
Scanner.initialized = false

local function addItem(bucket, itemID, count, link)
    itemID = tonumber(itemID)
    count = tonumber(count) or 1
    if not itemID or count <= 0 then
        return
    end

    local entry = bucket[itemID]
    if type(entry) ~= "table" then
        entry = { count = 0 }
        bucket[itemID] = entry
    end

    entry.count = (tonumber(entry.count) or 0) + count
    if link and not entry.link then
        entry.link = link
    end
end

local function safeContainerSlots(bagID)
    if not C_Container or not C_Container.GetContainerNumSlots then
        return 0
    end
    local ok, slots = pcall(C_Container.GetContainerNumSlots, bagID)
    if not ok then
        return 0
    end
    return tonumber(slots) or 0
end

local function safeContainerInfo(bagID, slot)
    if not C_Container or not C_Container.GetContainerItemInfo then
        return nil
    end
    local ok, info = pcall(C_Container.GetContainerItemInfo, bagID, slot)
    if not ok then
        return nil
    end
    return info
end

local function safeContainerLink(bagID, slot)
    if not C_Container or not C_Container.GetContainerItemLink then
        return nil
    end
    local ok, link = pcall(C_Container.GetContainerItemLink, bagID, slot)
    if ok then
        return link
    end
    return nil
end

local function itemIDFromInfo(info, bagID, slot)
    if type(info) == "table" and tonumber(info.itemID) then
        return tonumber(info.itemID)
    end
    if C_Container and C_Container.GetContainerItemID then
        local ok, itemID = pcall(C_Container.GetContainerItemID, bagID, slot)
        if ok then return tonumber(itemID) end
    end
    return nil
end

local function countFromInfo(info)
    if type(info) ~= "table" then
        return 1
    end
    return tonumber(info.stackCount) or tonumber(info.count) or 1
end

local function scanBagIDs(bagIDs)
    local bucket = {}
    local containersWithSlots = 0

    for _, bagID in ipairs(bagIDs) do
        local slots = safeContainerSlots(bagID)
        if slots > 0 then
            containersWithSlots = containersWithSlots + 1
            for slot = 1, slots do
                local info = safeContainerInfo(bagID, slot)
                local itemID = itemIDFromInfo(info, bagID, slot)
                if itemID then
                    local link = safeContainerLink(bagID, slot)
                    addItem(bucket, itemID, countFromInfo(info), link)
                end
            end
        end
    end

    return bucket, containersWithSlots
end

local function uniqueInsert(target, seen, value)
    value = tonumber(value)
    if value and not seen[value] then
        seen[value] = true
        target[#target + 1] = value
    end
end

function Scanner:GetBagIndexes()
    local bagIDs, seen = {}, {}

    if Enum and type(Enum.BagIndex) == "table" then
        for name, value in pairs(Enum.BagIndex) do
            if name == "Backpack" or name == "ReagentBag" or string.match(name, "^Bag_%d+$") then
                uniqueInsert(bagIDs, seen, value)
            end
        end
    end

    if #bagIDs == 0 then
        for bagID = 0, 5 do
            uniqueInsert(bagIDs, seen, bagID)
        end
    end

    table.sort(bagIDs)
    return bagIDs
end

function Scanner:GetBankIndexes()
    local characterBank, accountBank = {}, {}
    local seenCharacter, seenAccount = {}, {}

    if Enum and type(Enum.BagIndex) == "table" then
        for name, value in pairs(Enum.BagIndex) do
            local lower = string.lower(name)
            if string.find(lower, "account", 1, true) or string.find(lower, "warband", 1, true) then
                uniqueInsert(accountBank, seenAccount, value)
            elseif string.find(lower, "bank", 1, true) then
                uniqueInsert(characterBank, seenCharacter, value)
            end
        end
    end

    -- Fallback solo si el enum no existe. Enum.BagIndex en 12.x: CharacterBankTab_1..6 = 6..11,
    -- AccountBankTab_1..5 = 12..16 (Keyring=-1, Characterbanktab=-2, Accountbanktab=-3).
    if #characterBank == 0 then
        for bagID = 6, 11 do
            uniqueInsert(characterBank, seenCharacter, bagID)
        end
    end
    if #accountBank == 0 then
        for bagID = 12, 16 do
            uniqueInsert(accountBank, seenAccount, bagID)
        end
    end

    table.sort(characterBank)
    table.sort(accountBank)
    return characterBank, accountBank
end

function Scanner:ScanInventory()
    local character = RB:GetCurrentCharacter()
    local bucket = scanBagIDs(self:GetBagIndexes())
    character.bags = bucket
    RB:TouchCharacter()
end

function Scanner:ScanEquipment()
    local character = RB:GetCurrentCharacter()
    local bucket = {}

    if GetInventoryItemID then
        for slot = 1, 19 do
            local itemID = GetInventoryItemID("player", slot)
            if itemID then
                local link = GetInventoryItemLink and GetInventoryItemLink("player", slot) or nil
                addItem(bucket, itemID, 1, link)
            end
        end
    end

    character.equipped = bucket
    RB:TouchCharacter()
end

function Scanner:ScanBanks()
    -- Con el banco cerrado los contenedores pueden seguir reportando slots pero
    -- sin objetos: sobrescribir aqui borraria el banco guardado.
    if not self.bankOpen then return end

    local characterBankIDs, accountBankIDs = self:GetBankIndexes()

    local characterBucket, characterContainers = scanBagIDs(characterBankIDs)
    if characterContainers > 0 then
        local character = RB:GetCurrentCharacter()
        character.bank = characterBucket
        character.bankLastSeen = time and time() or 0
    end

    local accountBucket, accountContainers = scanBagIDs(accountBankIDs)
    if accountContainers > 0 then
        local db = RB:EnsureDB()
        db.account.bank = accountBucket
        db.account.bankLastSeen = time and time() or 0
    end

    RB:TouchCharacter()
end

function Scanner:ScanAll(includeBanks)
    self:ScanInventory()
    self:ScanEquipment()
    if includeBanks or self.bankOpen then
        self:ScanBanks()
    end
end

-- Un solo escaneo diferido por rafaga de eventos (PLAYERBANKSLOTS_CHANGED llega
-- por ranura). El banco se re-comprueba al disparar: si se cerro en la ventana,
-- no se toca lo guardado.
function Scanner:ScheduleScan(includeBanks)
    if includeBanks then self.pendingBanks = true end
    if self.scanPending then return end

    local function run()
        local banks = Scanner.pendingBanks
        Scanner.scanPending = false
        Scanner.pendingBanks = false
        Scanner:ScanAll(banks and Scanner.bankOpen)
    end

    if C_Timer and C_Timer.After then
        self.scanPending = true
        C_Timer.After(0.15, run)
    else
        run()
    end
end

function Scanner:Initialize()
    if self.initialized then
        return
    end
    self.initialized = true

    -- Eventos reales de 12.x (BankDocumentation). El banco de banda de guerra
    -- usa el mismo BANKFRAME_OPENED/CLOSED; BANK_TABS_CHANGED cubre pestanas nuevas.
    local events = {
        "BAG_UPDATE_DELAYED",
        "PLAYER_EQUIPMENT_CHANGED",
        "BANKFRAME_OPENED",
        "BANKFRAME_CLOSED",
        "PLAYERBANKSLOTS_CHANGED",
        "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED",
        "BANK_TABS_CHANGED",
        "BANK_TAB_SETTINGS_UPDATED",
    }

    for _, event in ipairs(events) do
        RB:RegisterEventSafe(self.frame, event)
    end

    self.frame:SetScript("OnEvent", function(_, event)
        if event == "BANKFRAME_OPENED" then
            Scanner.bankOpen = true
            Scanner:ScheduleScan(true)
        elseif event == "BANKFRAME_CLOSED" then
            Scanner.bankOpen = false
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            Scanner:ScanEquipment()
        elseif event == "BAG_UPDATE_DELAYED" then
            Scanner:ScheduleScan(Scanner.bankOpen)
        else
            if Scanner.bankOpen then
                Scanner:ScheduleScan(true)
            end
        end
    end)
    -- El primer escaneo lo dispara Core en PLAYER_LOGIN (reino y bolsas ya fiables).
end
