local addonName = ...
local RB = _G.RapzoBags
if not RB then return end

-- ReflectHerald: anuncia el hechizo devuelto por Spell Reflection.
-- Nota Midnight: el combat log esta restringido para addons. En este cliente el
-- REGISTRO de COMBAT_LOG_EVENT_UNFILTERED es una accion bloqueada: no lanza error
-- de Lua (el pcall no lo ve), el juego la bloquea y avisa con el popup de taint.
-- Por eso escuchamos ADDON_ACTION_BLOCKED/FORBIDDEN, recordamos el bloqueo en la DB
-- (settings.reflectHerald.cleuBlocked) y no reintentamos en logins siguientes.
local ReflectHerald = {}
RB.ReflectHerald = ReflectHerald
RB:RegisterModule("reflectHerald", ReflectHerald)

local frame = CreateFrame("Frame")
local playerGUID
local sessionReflects = {}   -- [spellName] = count
local sessionTotal = 0
local combatLogAvailable = false
local combatLogAttemptAt

local function getSettings()
    local db = RB:EnsureDB()
    if type(db.settings.reflectHerald) ~= "table" then
        db.settings.reflectHerald = {}
    end
    local settings = db.settings.reflectHerald
    if settings.party == nil then settings.party = true end
    return settings
end

local function announce(spellName, srcName)
    local line = ("Reflejado: %s%s"):format(spellName or "?", srcName and (" (de " .. srcName .. ")") or "")
    -- aviso grande en pantalla, SIN codigos de color: el RaidNotice ya colorea solo
    -- y hay clientes que no reconocen la cadena si va con |cff...|r incrustado
    local shown = false
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] then
        shown = pcall(RaidNotice_AddMessage, RaidWarningFrame, line, ChatTypeInfo["RAID_WARNING"])
    end
    if not shown and UIErrorsFrame and UIErrorsFrame.AddMessage then
        -- plan B: la linea amarilla central de la UI, presente en todos los clientes
        pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, line, 0.5, 0.7, 0.91)
    end
    RB:Print(line)
    -- aviso corto al grupo (en ingles), si esta activado
    if getSettings().party and IsInGroup() then
        local chan = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or "PARTY"
        local epic = ("Reflected %s - FOR THE ALLIANCE!"):format(spellName or "the cast")
        pcall(SendChatMessage, epic, chan)
    end
end

local function onCombatLogEvent()
    if not RB:IsFeatureEnabled("reflectHerald") then return end
    -- todo defensivo: en contenido restringido los valores pueden ser secretos
    pcall(function()
        local _, sub, _, _, srcName, _, _, dstGUID, _, _, _, _, spellName, _, missType =
            CombatLogGetCurrentEventInfo()
        if sub == "SPELL_MISSED" and missType == "REFLECT" and dstGUID == playerGUID then
            sessionTotal = sessionTotal + 1
            local key = tostring(spellName or "Desconocido")
            sessionReflects[key] = (sessionReflects[key] or 0) + 1
            announce(spellName, srcName)
        end
    end)
end

local function markCombatLogBlocked()
    combatLogAvailable = false
    combatLogAttemptAt = nil
    local settings = getSettings()
    if not settings.cleuBlocked then
        settings.cleuBlocked = true
        RB:Print("ReflectHerald: el cliente bloquea el combat log para addons (popup de taint). No se reintentara en proximos logins; el modo test sigue disponible. Tras un parche prueba /rapzo reflect retry.")
    end
end

local function tryRegisterCombatLog()
    local settings = getSettings()
    if settings.cleuBlocked then
        combatLogAvailable = false
        return
    end
    if combatLogAvailable then return end
    combatLogAttemptAt = GetTime()
    -- si el cliente bloquea la accion, no hay error de Lua: llega como
    -- ADDON_ACTION_BLOCKED/FORBIDDEN y lo maneja el OnEvent de abajo
    local ok = RB:RegisterEventSafe(frame, "COMBAT_LOG_EVENT_UNFILTERED")
    combatLogAvailable = ok and true or false
    if not combatLogAvailable then
        RB:Print("ReflectHerald: este cliente no expone el combat log a addons; solo funcionara el modo test.")
    end
end

local function onActionBlocked(blockedAddon, blockedFunction)
    -- nos atribuimos cualquier bloqueo del addon en la ventana corta tras nuestro intento:
    -- NO filtrar por nombre de funcion: el evento puede llegar atribuido a pcall()
    -- (la pila del taint.log llega encabezada por pcall) y no a RegisterEvent.
    -- La ventana es corta (1.5 s): el bloqueo llega en el mismo frame o el siguiente,
    -- y en PLAYER_LOGIN el HUD/Vendor tambien pueden provocar bloqueos propios.
    if not combatLogAttemptAt then return end
    if blockedAddon ~= addonName then return end
    if (GetTime() - combatLogAttemptAt) > 1.5 then return end
    -- se guarda la funcion bloqueada para poder afinar con el proximo taint.log
    if blockedFunction ~= nil and not (type(issecretvalue) == "function" and issecretvalue(blockedFunction)) then
        getSettings().lastBlockedFunction = tostring(blockedFunction)
    end
    markCombatLogBlocked()
end

function ReflectHerald:SetEnabled(enabled)
    RB:SetFeatureEnabled("reflectHerald", enabled and true or false, true)
    if enabled then tryRegisterCombatLog() end
end

frame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "PLAYER_LOGIN" then
        playerGUID = UnitGUID("player")
        getSettings()
        if RB:IsFeatureEnabled("reflectHerald") then
            tryRegisterCombatLog()
        end
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        onActionBlocked(arg1, arg2)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        onCombatLogEvent()
    end
end)
RB:RegisterEventSafe(frame, "PLAYER_LOGIN")
RB:RegisterEventSafe(frame, "ADDON_ACTION_BLOCKED")
RB:RegisterEventSafe(frame, "ADDON_ACTION_FORBIDDEN")

local function combatLogStateText()
    if combatLogAvailable then return "combat log OK" end
    if getSettings().cleuBlocked then return "combat log BLOQUEADO por el cliente (/rapzo reflect retry)" end
    return "combat log inactivo"
end

local function printStatus()
    local settings = getSettings()
    RB:Print(("ReflectHerald %s - anuncio al grupo %s - reflects esta sesion: %d - %s"):format(
        RB:IsFeatureEnabled("reflectHerald") and "ON" or "OFF",
        settings.party and "ON" or "OFF",
        sessionTotal,
        combatLogStateText()))
end

function ReflectHerald:HandleSlash(rest)
    rest = string.lower(tostring(rest or ""))
    local command, arg = rest:match("^%s*(%S*)%s*(%S*)")
    command = command or ""
    if command == "on" then
        self:SetEnabled(true)
        RB:Print("ReflectHerald: ON")
    elseif command == "off" then
        self:SetEnabled(false)
        RB:Print("ReflectHerald: OFF")
    elseif command == "party" then
        local settings = getSettings()
        if arg == "on" then
            settings.party = true
        elseif arg == "off" then
            settings.party = false
        else
            settings.party = not settings.party
        end
        RB:Print("ReflectHerald: anuncio al grupo " .. (settings.party and "ON" or "OFF"))
    elseif command == "test" then
        announce("Frostbolt", "Dummy")
    elseif command == "retry" then
        local settings = getSettings()
        settings.cleuBlocked = nil
        combatLogAvailable = false
        RB:Print("ReflectHerald: reintentando registrar el combat log...")
        tryRegisterCombatLog()
        -- el bloqueo llega como evento asincrono un instante despues del intento:
        -- esperar antes de cantar el estado, para no anunciar un OK prematuro
        if C_Timer and C_Timer.After then
            C_Timer.After(2, printStatus)
        else
            printStatus()
        end
    elseif command == "stats" then
        RB:Print("ReflectHerald: reflects esta sesion: " .. sessionTotal)
        for name, count in pairs(sessionReflects) do
            DEFAULT_CHAT_FRAME:AddMessage(("   %s x%d"):format(name, count))
        end
    elseif command == "status" or command == "" then
        printStatus()
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo reflect on|r / |cff38bdf8off|r - activa o desactiva el modulo")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo reflect party [on|off]|r - anuncio al grupo")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo reflect test|r - simula un reflejo")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo reflect stats|r - resumen de la sesion")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo reflect retry|r - reintenta el combat log tras un parche")
    else
        printStatus()
    end
end

RB:RegisterCommand("reflect", function(rest) ReflectHerald:HandleSlash(rest) end,
    "/rapzo reflect [status|on|off|party|test|stats|retry] - anuncios de Spell Reflection")

-- Alias rapido heredado del addon ReflectHerald original.
SLASH_RAPZOQOLREFLECT1 = "/rh"
SlashCmdList.RAPZOQOLREFLECT = function(message)
    ReflectHerald:HandleSlash(message)
end
