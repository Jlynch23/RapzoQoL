local addonName, private = ...

local RB = private or _G.RapzoQoL or _G.RapzoBags or {}
_G.RapzoQoL = RB
_G.RapzoBags = RB -- compatibilidad con datos/modulos anteriores

RB.name = "RapzoQoL"
RB.coreAddonName = addonName or "RapzoQoL"
RB.version = "3.0.0-alpha5"
RB.prefix = "|cff38bdf8Rapzo QoL|r"
RB.modules = RB.modules or {}
RB.commands = RB.commands or {}
RB.helpLines = RB.helpLines or {}

local DEFAULT_ACCENT = { r = 0.22, g = 0.83, b = 0.98 }

local eventFrame = CreateFrame("Frame")
RB.eventFrame = eventFrame

local function safeCall(func, ...)
    if type(func) ~= "function" then
        return false
    end
    return pcall(func, ...)
end

function RB:Print(message)
    -- tostring() sobre un valor secreto lanza error en 12.x.
    if type(issecretvalue) == "function" and issecretvalue(message) then
        message = "<valor secreto>"
    end
    DEFAULT_CHAT_FRAME:AddMessage(string.format("%s: %s", self.prefix, tostring(message)))
end

function RB:RegisterEventSafe(frame, event)
    if not frame or type(event) ~= "string" then
        return false
    end
    return pcall(frame.RegisterEvent, frame, event)
end

-- UNIT_* solo para las unidades indicadas (player/target/focus): en raid o M+
-- el evento sin filtro llega por cada unidad visible y se descarta en Lua.
-- Si el cliente no acepta la firma, cae al registro normal.
-- RegisterUnitEvent admite dos unidades por frame: a partir de la tercera se
-- usan frames auxiliares que reenvian al OnEvent del frame principal (se lee en
-- el momento del evento, asi da igual si SetScript se llama despues).
function RB:RegisterUnitEventSafe(frame, event, ...)
    if not frame or type(event) ~= "string" then
        return false
    end
    local count = select("#", ...)
    if type(frame.RegisterUnitEvent) ~= "function" or count == 0 then
        return pcall(frame.RegisterEvent, frame, event)
    end

    local units = { ... }
    local ok = pcall(frame.RegisterUnitEvent, frame, event, units[1], units[2])
    if not ok then
        return pcall(frame.RegisterEvent, frame, event)
    end

    local index = 3
    local helperIndex = 1
    while index <= count do
        frame.RapzoQoLUnitHelpers = frame.RapzoQoLUnitHelpers or {}
        local helper = frame.RapzoQoLUnitHelpers[helperIndex]
        if not helper then
            helper = CreateFrame("Frame")
            helper:SetScript("OnEvent", function(_, ...)
                local handler = frame:GetScript("OnEvent")
                if type(handler) == "function" then handler(frame, ...) end
            end)
            frame.RapzoQoLUnitHelpers[helperIndex] = helper
        end
        local okHelper = pcall(helper.RegisterUnitEvent, helper, event, units[index], units[index + 1])
        if not okHelper then
            return pcall(frame.RegisterEvent, frame, event)
        end
        index = index + 2
        helperIndex = helperIndex + 1
    end
    return true
end

-- Misma normalizacion que GetNormalizedRealmName(): sin espacios, guiones ni
-- apostrofes. GetNormalizedRealmName() puede devolver nil antes de PLAYER_LOGIN y
-- el fallback GetRealmName() ("Quel'Thalas", "Tol Barad") generaba una clave de
-- personaje distinta -> personaje fantasma duplicado en la DB.
local function normalizeRealm(realm)
    realm = tostring(realm or "")
    realm = realm:gsub("[%s%-']", "")
    return realm
end

function RB:GetRealmNameSafe()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then
        realm = GetRealmName and GetRealmName() or "UnknownRealm"
    end
    return normalizeRealm(realm)
end

function RB:GetPlayerNameSafe()
    local name = UnitName and UnitName("player")
    return name or "UnknownCharacter"
end

function RB:GetCharacterKey()
    return string.format("%s-%s", self:GetPlayerNameSafe(), self:GetRealmNameSafe())
end

function RB:EnsureDB()
    if type(RapzoBagsDB) ~= "table" then
        RapzoBagsDB = {}
    end

    local db = RapzoBagsDB
    db.schema = 5
    db.characters = type(db.characters) == "table" and db.characters or {}
    db.account = type(db.account) == "table" and db.account or {}
    db.account.bank = type(db.account.bank) == "table" and db.account.bank or {}
    db.settings = type(db.settings) == "table" and db.settings or {}
    db.settings.modules = type(db.settings.modules) == "table" and db.settings.modules or {}
    db.settings.theme = type(db.settings.theme) == "table" and db.settings.theme or {}
    db.settings.theme.accent = type(db.settings.theme.accent) == "table" and db.settings.theme.accent or {
        r = DEFAULT_ACCENT.r,
        g = DEFAULT_ACCENT.g,
        b = DEFAULT_ACCENT.b,
    }

    -- Migracion desde RapzoBags 2.x: conserva tus preferencias existentes.
    if db.settings.tooltip == nil then db.settings.tooltip = true end
    if db.settings.showTotal == nil then db.settings.showTotal = true end
    if db.settings.showLocations == nil then db.settings.showLocations = true end
    if db.settings.maxCharacters == nil then db.settings.maxCharacters = 12 end
    if db.settings.showItemExpansion == nil then db.settings.showItemExpansion = true end
    if db.settings.showItemType == nil then db.settings.showItemType = true end
    if db.settings.showItemID == nil then db.settings.showItemID = true end

    local modules = db.settings.modules
    if modules.tooltip == nil then modules.tooltip = db.settings.tooltip ~= false end
    if modules.search == nil then modules.search = true end
    if modules.vendor == nil then modules.vendor = true end
    if modules.collections == nil then modules.collections = true end
    if modules.afk == nil then modules.afk = true end
    if modules.hud == nil then modules.hud = true end
    if modules.expansionFilters == nil then modules.expansionFilters = true end
    if modules.reflectHerald == nil then modules.reflectHerald = true end
    if modules.cooldownPulse == nil then modules.cooldownPulse = true end
    if modules.combatText == nil then modules.combatText = false end
    if modules.config == nil then modules.config = true end

    self.db = db
    if not self.characterKeysMigrated then
        self.characterKeysMigrated = true
        self:MigrateCharacterKeys()
    end
    return db
end

-- Fusiona claves "Nombre-Reino Con Espacios" (creadas por versiones anteriores
-- antes de PLAYER_LOGIN) con la clave normalizada "Nombre-ReinoConEspacios".
-- Solo corre una vez por sesion; no reemplaza datos existentes, solo rellena.
function RB:MigrateCharacterKeys()
    local db = self.db
    if type(db) ~= "table" or type(db.characters) ~= "table" then return end

    local renames = {}
    for key, character in pairs(db.characters) do
        if type(character) == "table" then
            local name = character.name or key:match("^(.-)%-") or key
            local realm = character.realm or key:match("%-(.*)$") or ""
            local canonical = string.format("%s-%s", name, normalizeRealm(realm))
            if canonical ~= key then
                renames[#renames + 1] = { from = key, to = canonical }
            end
        end
    end

    for _, rename in ipairs(renames) do
        local ghost = db.characters[rename.from]
        local target = db.characters[rename.to]
        if type(target) ~= "table" then
            ghost.key = rename.to
            ghost.realm = normalizeRealm(ghost.realm)
            db.characters[rename.to] = ghost
        else
            -- La clave canonica ya existe: conservar el mas reciente y rellenar
            -- huecos con el fantasma (que normalmente solo tiene oro y lastSeen).
            for _, bucketName in ipairs({"bags", "equipped", "bank"}) do
                local targetBucket = type(target[bucketName]) == "table" and target[bucketName] or nil
                local ghostBucket = type(ghost[bucketName]) == "table" and ghost[bucketName] or nil
                if ghostBucket and (not targetBucket or next(targetBucket) == nil) and next(ghostBucket) ~= nil then
                    target[bucketName] = ghostBucket
                end
            end
            if (tonumber(ghost.lastSeen) or 0) > (tonumber(target.lastSeen) or 0) then
                target.lastSeen = ghost.lastSeen
                target.money = ghost.money or target.money
            end
            target.class = target.class or ghost.class
            target.faction = target.faction or ghost.faction
        end
        db.characters[rename.from] = nil
    end
end

function RB:IsFeatureEnabled(key, defaultValue)
    local db = self:EnsureDB()
    local value = db.settings.modules[key]
    if value == nil then
        if defaultValue == nil then defaultValue = true end
        value = defaultValue and true or false
        db.settings.modules[key] = value
    end
    return value == true
end

function RB:SetFeatureEnabled(key, enabled, quiet)
    local db = self:EnsureDB()
    db.settings.modules[key] = enabled and true or false
    if key == "tooltip" then db.settings.tooltip = enabled and true or false end
    if not quiet then
        self:Print(string.format("Modulo %s: %s", tostring(key), enabled and "ON" or "OFF"))
    end
end

local function clamp01(value)
    value = tonumber(value) or 0
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

function RB:GetAccentColor()
    local accent = self:EnsureDB().settings.theme.accent
    return clamp01(accent.r or DEFAULT_ACCENT.r),
        clamp01(accent.g or DEFAULT_ACCENT.g),
        clamp01(accent.b or DEFAULT_ACCENT.b)
end

function RB:ColorToHex(r, g, b)
    r, g, b = clamp01(r), clamp01(g), clamp01(b)
    return string.format("%02X%02X%02X", math.floor((r * 255) + 0.5), math.floor((g * 255) + 0.5), math.floor((b * 255) + 0.5))
end

function RB:RefreshPrefix()
    local r, g, b = self:GetAccentColor()
    self.prefix = "|cff" .. self:ColorToHex(r, g, b) .. "Rapzo QoL|r"
end

function RB:ApplyTheme()
    self:RefreshPrefix()
    for _, module in pairs(self.modules or {}) do
        if module and type(module.ApplyTheme) == "function" then
            pcall(module.ApplyTheme, module)
        end
    end
end

function RB:SetAccentColor(r, g, b, quiet)
    local accent = self:EnsureDB().settings.theme.accent
    accent.r, accent.g, accent.b = clamp01(r), clamp01(g), clamp01(b)
    self:ApplyTheme()
    if not quiet then
        self:Print("Accent Color: #" .. self:ColorToHex(accent.r, accent.g, accent.b))
    end
end

function RB:ResetAccentColor(quiet)
    self:SetAccentColor(DEFAULT_ACCENT.r, DEFAULT_ACCENT.g, DEFAULT_ACCENT.b, true)
    if not quiet then
        self:Print("Accent Color restablecido: #" .. self:ColorToHex(DEFAULT_ACCENT.r, DEFAULT_ACCENT.g, DEFAULT_ACCENT.b))
    end
end

function RB:RegisterModule(key, module)
    if not key or not module then return end
    self.modules[key] = module
    self[key:gsub("^%l", string.upper)] = module
end

function RB:IsModulePresent(key)
    return self.modules[key] ~= nil
end

function RB:RegisterCommand(name, handler, helpText)
    name = string.lower(tostring(name or ""))
    if name == "" or type(handler) ~= "function" then return end
    self.commands[name] = handler
    if helpText then self.helpLines[name] = helpText end
end

function RB:SetDefaultAction(handler)
    if type(handler) == "function" then
        self.defaultAction = handler
    end
end

function RB:PrintHelp()
    self:Print("Comandos disponibles:")
    DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo|r - abre el buscador si el modulo Search esta activo")
    DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo scan|r - reescanea bolsas y equipo")
    DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo status|r - resumen de la base local")
    DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo modules|r - estado de los modulos")
    DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo reset confirm|r - borra la base local")
    local keys = {}
    for name in pairs(self.helpLines) do keys[#keys + 1] = name end
    table.sort(keys)
    for _, name in ipairs(keys) do
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8" .. self.helpLines[name] .. "|r")
    end
end

function RB:GetCurrentCharacter()
    local db = self:EnsureDB()
    local key = self:GetCharacterKey()
    local character = db.characters[key]

    if type(character) ~= "table" then
        character = {
            key = key,
            name = self:GetPlayerNameSafe(),
            realm = self:GetRealmNameSafe(),
            bags = {},
            equipped = {},
            bank = {},
            money = 0,
            lastSeen = 0,
        }
        db.characters[key] = character
    end

    character.key = key
    character.name = self:GetPlayerNameSafe()
    character.realm = self:GetRealmNameSafe()
    character.bags = type(character.bags) == "table" and character.bags or {}
    character.equipped = type(character.equipped) == "table" and character.equipped or {}
    character.bank = type(character.bank) == "table" and character.bank or {}

    if UnitClass then
        local _, classFile = UnitClass("player")
        character.class = classFile or character.class
    end
    if UnitFactionGroup then
        character.faction = UnitFactionGroup("player") or character.faction
    end

    return character
end

function RB:TouchCharacter()
    local character = self:GetCurrentCharacter()
    character.lastSeen = time and time() or 0
    if GetMoney then
        character.money = GetMoney() or character.money or 0
    end
end

function RB:ApplyBagDirection()
    if not C_Container then return end
    if C_Container.SetSortBagsRightToLeft then safeCall(C_Container.SetSortBagsRightToLeft, false) end
    if C_Container.SetInsertItemsLeftToRight then safeCall(C_Container.SetInsertItemsLeftToRight, false) end
end

function RB:ApplyBagDirectionDelayed()
    self:ApplyBagDirection()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function() RB:ApplyBagDirection() end)
        C_Timer.After(2, function() RB:ApplyBagDirection() end)
    end
end

local function getStoredCount(locationTable, itemID)
    if type(locationTable) ~= "table" then return 0 end
    local entry = locationTable[itemID]
    if type(entry) == "table" then return tonumber(entry.count) or 0 end
    return tonumber(entry) or 0
end

function RB:GetItemAggregate(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end

    local db = self:EnsureDB()
    local result = { itemID = itemID, characters = {}, accountBank = 0, total = 0 }

    for key, character in pairs(db.characters) do
        if type(character) == "table" then
            local bags = getStoredCount(character.bags, itemID)
            local equipped = getStoredCount(character.equipped, itemID)
            local bank = getStoredCount(character.bank, itemID)
            local subtotal = bags + equipped + bank
            if subtotal > 0 then
                result.characters[#result.characters + 1] = {
                    key = key,
                    name = character.name or key,
                    realm = character.realm,
                    class = character.class,
                    bags = bags,
                    equipped = equipped,
                    bank = bank,
                    total = subtotal,
                    lastSeen = character.lastSeen or 0,
                }
                result.total = result.total + subtotal
            end
        end
    end

    result.accountBank = getStoredCount(db.account.bank, itemID)
    result.total = result.total + result.accountBank

    table.sort(result.characters, function(a, b)
        if a.total == b.total then return (a.name or "") < (b.name or "") end
        return a.total > b.total
    end)

    return result
end

function RB:GetKnownItemLink(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local db = self:EnsureDB()
    for _, character in pairs(db.characters) do
        for _, bucketName in ipairs({"bags", "equipped", "bank"}) do
            local bucket = character[bucketName]
            local entry = type(bucket) == "table" and bucket[itemID]
            if type(entry) == "table" and entry.link then return entry.link end
        end
    end
    local accountEntry = db.account.bank[itemID]
    if type(accountEntry) == "table" and accountEntry.link then return accountEntry.link end
    return nil
end

function RB:GetAllKnownItemIDs()
    local ids, seen = {}, {}
    local db = self:EnsureDB()
    local function absorb(bucket)
        if type(bucket) ~= "table" then return end
        for itemID in pairs(bucket) do
            itemID = tonumber(itemID)
            if itemID and not seen[itemID] then
                seen[itemID] = true
                ids[#ids + 1] = itemID
            end
        end
    end
    for _, character in pairs(db.characters) do
        absorb(character.bags); absorb(character.equipped); absorb(character.bank)
    end
    absorb(db.account.bank)
    table.sort(ids)
    return ids
end

function RB:GetTotalMoney()
    local total = 0
    local db = self:EnsureDB()
    for _, character in pairs(db.characters) do total = total + (tonumber(character.money) or 0) end
    return total
end

function RB:ShowStatus()
    local db = self:EnsureDB()
    local characterCount = 0
    for _ in pairs(db.characters) do characterCount = characterCount + 1 end
    self:Print(string.format("v%s | %d personaje(s) | %d objeto(s) unicos", self.version, characterCount, #self:GetAllKnownItemIDs()))
end

-- Lista canonica de modulos con toggle. Config y ShowModules la comparten.
RB.moduleKeys = {
    "tooltip", "search", "vendor", "collections", "afk", "hud",
    "expansionFilters", "reflectHerald", "cooldownPulse", "combatText", "config",
}

function RB:ShowModules()
    local labels = self.moduleKeys
    self:Print("Modulos internos de Rapzo QoL:")
    for _, key in ipairs(labels) do
        local present = self:IsModulePresent(key)
        local enabled = self:IsFeatureEnabled(key)
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  %-12s  addon:%s  funcion:%s", key, present and "|cff38e66bCARGADO|r" or "|cffef4444NO|r", enabled and "|cff38e66bON|r" or "|cffef4444OFF|r"))
    end
end

function RB:Initialize()
    -- ADDON_LOADED: solo preparar DB y eventos. El personaje y el primer escaneo
    -- se hacen en PLAYER_LOGIN, cuando reino y contenedores ya son fiables.
    self:EnsureDB()
    self:RefreshPrefix()
    self:ApplyBagDirectionDelayed()
    if self.Scanner and self.Scanner.Initialize then self.Scanner:Initialize() end
end

RB:RegisterCommand("scan", function()
    if RB.Scanner then
        RB.Scanner:ScanAll(RB.Scanner.bankOpen)
        RB:Print("Escaneo actualizado.")
    end
end)
RB:RegisterCommand("status", function() RB:ShowStatus() end)
RB:RegisterCommand("modules", function() RB:ShowModules() end)
RB:RegisterCommand("color", function(rest)
    rest = tostring(rest or ""):gsub("%s+", "")
    if rest == "" then
        local r, g, b = RB:GetAccentColor()
        RB:Print("Accent Color actual: #" .. RB:ColorToHex(r, g, b) .. " | usa /rapzo color #RRGGBB o /rapzo color reset")
        return
    end

    if string.lower(rest) == "reset" then
        RB:ResetAccentColor(false)
        return
    end

    local hex = rest:gsub("^#", "")
    if not hex:match("^[%x][%x][%x][%x][%x][%x]$") then
        RB:Print("Uso: /rapzo color #RRGGBB | /rapzo color reset")
        return
    end

    local r = tonumber(hex:sub(1, 2), 16) / 255
    local g = tonumber(hex:sub(3, 4), 16) / 255
    local b = tonumber(hex:sub(5, 6), 16) / 255
    RB:SetAccentColor(r, g, b, false)
end, "/rapzo color #RRGGBB|reset - cambia el Accent Color")
RB:RegisterCommand("help", function() RB:PrintHelp() end)
RB:RegisterCommand("ayuda", function() RB:PrintHelp() end)
RB:RegisterCommand("reset", function(rest)
    if string.lower(tostring(rest or "")) ~= "confirm" then
        RB:Print("Uso: /rapzo reset confirm")
        return
    end
    RapzoBagsDB = nil
    RB.db = nil
    RB:EnsureDB(); RB:TouchCharacter()
    if RB.Scanner then RB.Scanner:ScanAll(RB.Scanner.bankOpen) end
    -- Los modulos guardan referencias a las tablas antiguas de settings; sin
    -- recargar seguirian escribiendo en tablas huerfanas.
    RB:Print("Base de datos reiniciada. Recargando la interfaz...")
    if type(ReloadUI) == "function" then ReloadUI() end
end)

SLASH_RAPZOQOL1 = "/rapzo"
SLASH_RAPZOQOL2 = "/rqol"
SLASH_RAPZOQOL3 = "/rbags"
SLASH_RAPZOQOL4 = "/rapzobags"
SlashCmdList.RAPZOQOL = function(message)
    message = tostring(message or "")
    local command, rest = message:match("^(%S*)%s*(.-)$")
    command = string.lower(command or "")
    if command == "" then
        if type(RB.defaultAction) == "function" then RB.defaultAction() else RB:PrintHelp() end
        return
    end
    local handler = RB.commands[command]
    if handler then handler(rest or "") else RB:PrintHelp() end
end

-- Alias rapido para recargar la interfaz.
-- /rl se comporta como /reload, pero queda registrado por Rapzo QoL.
SLASH_RAPZOQOLRELOAD1 = "/rl"
SlashCmdList.RAPZOQOLRELOAD = function()
    if type(ReloadUI) == "function" then
        ReloadUI()
    end
end

RB:RegisterEventSafe(eventFrame, "ADDON_LOADED")
RB:RegisterEventSafe(eventFrame, "PLAYER_LOGIN")
RB:RegisterEventSafe(eventFrame, "PLAYER_ENTERING_WORLD")
RB:RegisterEventSafe(eventFrame, "PLAYER_MONEY")

local initialized = false
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon ~= RB.coreAddonName then return end
        if not initialized then initialized = true; RB:Initialize() end
    elseif event == "PLAYER_LOGIN" then
        RB:EnsureDB(); RB:TouchCharacter(); RB:ApplyBagDirectionDelayed()
        if RB.Scanner and RB.Scanner.ScanAll then RB.Scanner:ScanAll(false) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReload = ...
        -- Login y /reload ya pasaron por PLAYER_LOGIN; solo cambios de mundo.
        if not isInitialLogin and not isReload then
            RB:TouchCharacter()
            if RB.Scanner and RB.Scanner.ScheduleScan then RB.Scanner:ScheduleScan(false) end
        end
    elseif event == "PLAYER_MONEY" then
        RB:TouchCharacter()
    end
end)
