local addonName = ...
local RB = _G.RapzoBags or _G.RapzoQoL
if not RB then return end

-- CombatText: personaliza las fuentes y fisica del texto de combate de Blizzard.
-- Implementacion propia de Rapzo QoL, sin dependencias obligatorias de Ace3.
local CombatText = {}
RB.CombatText = CombatText
RB:RegisterModule("combatText", CombatText)

local DEFAULT_WORLD_FONT = "Friz Quadrata"
local DEFAULT_WORLD_PATH = "Fonts\\FRIZQT__.TTF"
local DEFAULT_UI_FONT = "Friz Quadrata"
local DEFAULT_UI_PATH = "Fonts\\FRIZQT__.TTF"

local BUILTIN_FONTS = {
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    { name = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
    { name = "Skurri", path = "Fonts\\SKURRI.TTF" },
}

local WORLD_CVARS = {
    "WorldTextScale",
    "WorldTextScale_v2",
    "WorldTextGravity",
    "WorldTextGravity_v2",
    "WorldTextRampDuration",
    "WorldTextRampDuration_v2",
}

local UI_FONT_OBJECTS = {
    { key = "CombatTextFont", object = function() return _G.CombatTextFont end },
    { key = "DamageNumberFont", object = function() return _G.DamageNumberFont end },
    { key = "WorldFont", object = function() return _G.WorldFont end },
}

local original = {
    captured = false,
    damageTextFont = nil,
    cvars = {},
    uiFonts = {},
}

local fontCatalog = {}
local fontIndexByName = {}
local settingsPanel
local settingsCategory
local lsmCallbackRegistered = false

local function clamp(value, low, high)
    value = tonumber(value) or low
    if value < low then return low end
    if value > high then return high end
    return value
end

local function round(value, digits)
    local mul = 10 ^ (digits or 0)
    return math.floor((value * mul) + 0.5) / mul
end

local function getLSM()
    if not _G.LibStub then return nil end
    local ok, lib = pcall(_G.LibStub, "LibSharedMedia-3.0", true)
    if ok then return lib end
    return nil
end

local function getSettings()
    local db = RB:EnsureDB()
    db.settings.combatText = type(db.settings.combatText) == "table" and db.settings.combatText or {}
    local s = db.settings.combatText

    if s.worldEnabled == nil then s.worldEnabled = true end
    if s.uiEnabled == nil then s.uiEnabled = false end
    if s.worldFont == nil then s.worldFont = DEFAULT_WORLD_FONT end
    if s.worldFontPath == nil then s.worldFontPath = DEFAULT_WORLD_PATH end
    if s.worldScale == nil then s.worldScale = 1.0 end
    if s.worldGravity == nil then s.worldGravity = 0.5 end
    if s.worldDuration == nil then s.worldDuration = 1.0 end
    if s.uiFont == nil then s.uiFont = DEFAULT_UI_FONT end
    if s.uiFontPath == nil then s.uiFontPath = DEFAULT_UI_PATH end
    if s.uiSize == nil then s.uiSize = 16 end
    if s.uiOutline == nil then s.uiOutline = "OUTLINE" end
    if s.uiMonochrome == nil then s.uiMonochrome = false end
    if s.uiShadowOffset == nil then s.uiShadowOffset = 1 end

    s.worldScale = clamp(s.worldScale, 0.5, 5.0)
    s.worldGravity = clamp(s.worldGravity, -10, 10)
    s.worldDuration = clamp(s.worldDuration, 0.1, 3.0)
    s.uiSize = clamp(s.uiSize, 8, 48)
    s.uiShadowOffset = clamp(s.uiShadowOffset, 0, 10)
    return s
end

local function isEnabled()
    -- OFF por defecto para no pelear con NiceDamage/ElvUI si siguen instalados.
    return RB:IsFeatureEnabled("combatText", false)
end

local function setCVarSafe(name, value)
    if not SetCVar then return false end
    return pcall(SetCVar, name, tostring(value))
end

local function getCVarSafe(name)
    if not GetCVar then return nil end
    local ok, value = pcall(GetCVar, name)
    if ok then return value end
    return nil
end

local function captureOriginal()
    if original.captured then return end
    original.captured = true
    original.damageTextFont = _G.DAMAGE_TEXT_FONT

    for _, name in ipairs(WORLD_CVARS) do
        original.cvars[name] = getCVarSafe(name)
    end

    for _, info in ipairs(UI_FONT_OBJECTS) do
        local obj = info.object()
        if obj and obj.GetFont then
            local ok, path, size, flags = pcall(obj.GetFont, obj)
            if ok and path then
                local entry = { path = path, size = size, flags = flags }
                if obj.GetShadowOffset then
                    local okShadow, x, y = pcall(obj.GetShadowOffset, obj)
                    if okShadow then entry.shadowX, entry.shadowY = x, y end
                end
                if obj.GetShadowColor then
                    local okColor, r, g, b, a = pcall(obj.GetShadowColor, obj)
                    if okColor then
                        entry.shadowR, entry.shadowG, entry.shadowB, entry.shadowA = r, g, b, a
                    end
                end
                original.uiFonts[info.key] = entry
            end
        end
    end
end

local function addFont(name, path, source)
    name = tostring(name or "")
    path = tostring(path or "")
    if name == "" or path == "" or fontIndexByName[name] then return end
    fontCatalog[#fontCatalog + 1] = { name = name, path = path, source = source or "Blizzard" }
    fontIndexByName[name] = #fontCatalog
end

function CombatText:RebuildFontCatalog()
    wipe(fontCatalog)
    wipe(fontIndexByName)

    for _, font in ipairs(BUILTIN_FONTS) do
        addFont(font.name, font.path, "Blizzard")
    end

    local lsm = getLSM()
    if lsm and lsm.List and lsm.Fetch then
        local ok, names = pcall(lsm.List, lsm, "font")
        if ok and type(names) == "table" then
            local copy = {}
            for _, name in ipairs(names) do copy[#copy + 1] = name end
            table.sort(copy, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
            for _, name in ipairs(copy) do
                local okPath, path = pcall(lsm.Fetch, lsm, "font", name, true)
                if okPath and type(path) == "string" and path ~= "" then
                    addFont(name, path, "SharedMedia")
                end
            end
        end
    end

    self:RefreshSettingsPanel()
end

local function resolveFont(name, fallbackPath)
    local index = fontIndexByName[name]
    if index and fontCatalog[index] then
        return fontCatalog[index].path, fontCatalog[index]
    end
    if fallbackPath and fallbackPath ~= "" then
        return fallbackPath, { name = name or "Personalizada", path = fallbackPath, source = "Guardada" }
    end
    return DEFAULT_WORLD_PATH, { name = DEFAULT_WORLD_FONT, path = DEFAULT_WORLD_PATH, source = "Blizzard" }
end

local function buildFontFlags(outline, monochrome)
    local flags = tostring(outline or "")
    if monochrome then
        if flags == "" then flags = "MONOCHROME" else flags = flags .. ",MONOCHROME" end
    end
    return flags
end

local function restoreWorldText()
    if original.damageTextFont then _G.DAMAGE_TEXT_FONT = original.damageTextFont end
    for _, name in ipairs(WORLD_CVARS) do
        local value = original.cvars[name]
        if value ~= nil then setCVarSafe(name, value) end
    end
end

local function restoreUIFontObject(key, obj)
    local entry = original.uiFonts[key]
    if not entry or not obj then return end
    if obj.SetFont and entry.path then
        pcall(obj.SetFont, obj, entry.path, entry.size or 16, entry.flags or "")
    end
    if obj.SetShadowOffset and entry.shadowX ~= nil and entry.shadowY ~= nil then
        pcall(obj.SetShadowOffset, obj, entry.shadowX, entry.shadowY)
    end
    if obj.SetShadowColor and entry.shadowR ~= nil then
        pcall(obj.SetShadowColor, obj,
            entry.shadowR or 0, entry.shadowG or 0, entry.shadowB or 0, entry.shadowA or 1)
    end
end

local function restoreUIText()
    for _, info in ipairs(UI_FONT_OBJECTS) do
        restoreUIFontObject(info.key, info.object())
    end
end

function CombatText:RestoreOriginal()
    captureOriginal()
    restoreWorldText()
    restoreUIText()
end

function CombatText:ApplySystemFonts(quiet)
    captureOriginal()
    if #fontCatalog == 0 then self:RebuildFontCatalog() end

    if not isEnabled() then
        self:RestoreOriginal()
        if not quiet then
            RB:Print("Combat Text desactivado; restaurados los ajustes capturados al iniciar sesion.")
        end
        return
    end

    local s = getSettings()
    if s.worldEnabled then
        local worldPath, worldEntry = resolveFont(s.worldFont, s.worldFontPath)
        s.worldFontPath = worldPath
        if worldEntry and worldEntry.name then s.worldFont = worldEntry.name end
        _G.DAMAGE_TEXT_FONT = worldPath

        for _, suffix in ipairs({ "", "_v2" }) do
            setCVarSafe("WorldTextScale" .. suffix, round(s.worldScale, 2))
            setCVarSafe("WorldTextGravity" .. suffix, round(s.worldGravity, 2))
            setCVarSafe("WorldTextRampDuration" .. suffix, round(s.worldDuration, 2))
        end
    else
        restoreWorldText()
    end

    if s.uiEnabled then
        local uiPath, uiEntry = resolveFont(s.uiFont, s.uiFontPath)
        s.uiFontPath = uiPath
        if uiEntry and uiEntry.name then s.uiFont = uiEntry.name end
        local flags = buildFontFlags(s.uiOutline, s.uiMonochrome)

        for _, info in ipairs(UI_FONT_OBJECTS) do
            local obj = info.object()
            if obj and obj.SetFont then
                pcall(obj.SetFont, obj, uiPath, s.uiSize, flags)
                if obj.SetShadowOffset then
                    pcall(obj.SetShadowOffset, obj, s.uiShadowOffset, -s.uiShadowOffset)
                end
                if obj.SetShadowColor then
                    pcall(obj.SetShadowColor, obj, 0, 0, 0, 1)
                end
            end
        end
    else
        restoreUIText()
    end

    if not quiet then
        RB:Print("Combat Text aplicado. Escala/gravedad/duracion cambian al instante; cambiar la fuente 3D requiere salir a seleccion de personaje y volver a entrar.")
    end
    self:RefreshSettingsPanel()
end

function CombatText:SetEnabled(enabled)
    RB:SetFeatureEnabled("combatText", enabled, true)
    self:ApplySystemFonts(true)
    self:RefreshSettingsPanel()
end

local function cycleFont(settingName, pathSettingName, direction)
    if #fontCatalog == 0 then CombatText:RebuildFontCatalog() end
    if #fontCatalog == 0 then return end
    local s = getSettings()
    local current = fontIndexByName[s[settingName]] or 1
    local nextIndex = current + (direction or 1)
    if nextIndex < 1 then nextIndex = #fontCatalog end
    if nextIndex > #fontCatalog then nextIndex = 1 end
    local entry = fontCatalog[nextIndex]
    s[settingName], s[pathSettingName] = entry.name, entry.path
    CombatText:ApplySystemFonts(true)
end

function CombatText:CycleWorldFont(direction)
    cycleFont("worldFont", "worldFontPath", direction)
end

function CombatText:CycleUIFont(direction)
    cycleFont("uiFont", "uiFontPath", direction)
end

function CombatText:ResetDefaults()
    local s = getSettings()
    s.worldEnabled = true
    s.uiEnabled = false
    s.worldFont = DEFAULT_WORLD_FONT
    s.worldFontPath = DEFAULT_WORLD_PATH
    s.worldScale = 1.0
    s.worldGravity = 0.5
    s.worldDuration = 1.0
    s.uiFont = DEFAULT_UI_FONT
    s.uiFontPath = DEFAULT_UI_PATH
    s.uiSize = 16
    s.uiOutline = "OUTLINE"
    s.uiMonochrome = false
    s.uiShadowOffset = 1
    self:ApplySystemFonts(true)
    RB:Print("Combat Text restablecido a los valores de Rapzo QoL.")
end

function CombatText:PrintStatus()
    local s = getSettings()
    RB:Print(("Combat Text %s | dano 3D %s | fuente %s | escala %.1f | gravedad %.1f | duracion %.1f | UI %s"):format(
        isEnabled() and "ON" or "OFF",
        s.worldEnabled and "ON" or "OFF",
        tostring(s.worldFont),
        s.worldScale,
        s.worldGravity,
        s.worldDuration,
        s.uiEnabled and "ON" or "OFF"))
end

local function makeCheck(parent, label, x, y, getValue, setValue)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    check:SetSize(26, 26)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", check, "RIGHT", 5, 0)
    text:SetText(label)
    check.refresh = function() check:SetChecked(getValue() == true) end
    check:SetScript("OnClick", function(self)
        setValue(self:GetChecked() == true)
        CombatText:ApplySystemFonts(true)
        CombatText:RefreshSettingsPanel()
    end)
    return check
end

local function makeButton(parent, text, width, x, y, callback)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 26)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetText(text)
    button:SetScript("OnClick", callback)
    return button
end

local function makeValueRow(panel, y, minusCallback, plusCallback)
    local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, y)
    makeButton(panel, "-", 32, 300, y + 8, function()
        minusCallback()
        CombatText:RefreshSettingsPanel()
    end)
    makeButton(panel, "+", 32, 338, y + 8, function()
        plusCallback()
        CombatText:RefreshSettingsPanel()
    end)
    return text
end

function CombatText:CreateSettingsPanel()
    if settingsPanel then return settingsPanel end
    local panel = CreateFrame("Frame", "RapzoQoLCombatTextSettingsPanel")

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -18)
    title:SetText("Combat Text")

    local intro = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    intro:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
    intro:SetJustifyH("LEFT")
    intro:SetText("Personaliza los numeros de dano/heal de Blizzard: fuente, escala y animacion. Las fuentes de SharedMedia aparecen automaticamente.")

    local warning = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    warning:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -72)
    warning:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
    warning:SetJustifyH("LEFT")
    warning:SetText("|cffff5555Importante:|r cambiar la fuente del dano 3D requiere salir a seleccion de personaje y volver a entrar. Escala, gravedad y duracion son instantaneas.")

    panel.checks = {}
    panel.checks[#panel.checks + 1] = makeCheck(panel, "Activar Combat Text", 22, -116,
        isEnabled, function(v) CombatText:SetEnabled(v) end)
    panel.checks[#panel.checks + 1] = makeCheck(panel, "Modificar dano/heal 3D", 22, -150,
        function() return getSettings().worldEnabled end,
        function(v) getSettings().worldEnabled = v end)
    panel.checks[#panel.checks + 1] = makeCheck(panel, "Modificar Scrolling Combat Text", 280, -150,
        function() return getSettings().uiEnabled end,
        function(v) getSettings().uiEnabled = v end)

    local worldTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    worldTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -196)
    worldTitle:SetText("Dano / Healing sobre unidades")

    panel.worldFontLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.worldFontLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -226)
    makeButton(panel, "<", 32, 300, -234, function()
        CombatText:CycleWorldFont(-1); CombatText:RefreshSettingsPanel()
    end)
    makeButton(panel, ">", 32, 338, -234, function()
        CombatText:CycleWorldFont(1); CombatText:RefreshSettingsPanel()
    end)

    panel.scaleLabel = makeValueRow(panel, -270,
        function() local s=getSettings(); s.worldScale=clamp(round(s.worldScale-0.1,1),0.5,5); CombatText:ApplySystemFonts(true) end,
        function() local s=getSettings(); s.worldScale=clamp(round(s.worldScale+0.1,1),0.5,5); CombatText:ApplySystemFonts(true) end)
    panel.gravityLabel = makeValueRow(panel, -308,
        function() local s=getSettings(); s.worldGravity=clamp(round(s.worldGravity-0.5,1),-10,10); CombatText:ApplySystemFonts(true) end,
        function() local s=getSettings(); s.worldGravity=clamp(round(s.worldGravity+0.5,1),-10,10); CombatText:ApplySystemFonts(true) end)
    panel.durationLabel = makeValueRow(panel, -346,
        function() local s=getSettings(); s.worldDuration=clamp(round(s.worldDuration-0.1,1),0.1,3); CombatText:ApplySystemFonts(true) end,
        function() local s=getSettings(); s.worldDuration=clamp(round(s.worldDuration+0.1,1),0.1,3); CombatText:ApplySystemFonts(true) end)

    local uiTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    uiTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -396)
    uiTitle:SetText("Scrolling Combat Text")

    panel.uiFontLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.uiFontLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -426)
    makeButton(panel, "<", 32, 300, -434, function()
        CombatText:CycleUIFont(-1); CombatText:RefreshSettingsPanel()
    end)
    makeButton(panel, ">", 32, 338, -434, function()
        CombatText:CycleUIFont(1); CombatText:RefreshSettingsPanel()
    end)

    panel.uiSizeLabel = makeValueRow(panel, -470,
        function() local s=getSettings(); s.uiSize=clamp(s.uiSize-1,8,48); CombatText:ApplySystemFonts(true) end,
        function() local s=getSettings(); s.uiSize=clamp(s.uiSize+1,8,48); CombatText:ApplySystemFonts(true) end)

    panel.outlineButton = makeButton(panel, "Outline", 160, 24, -514, function()
        local s = getSettings()
        if s.uiOutline == "" then s.uiOutline = "OUTLINE"
        elseif s.uiOutline == "OUTLINE" then s.uiOutline = "THICKOUTLINE"
        else s.uiOutline = "" end
        CombatText:ApplySystemFonts(true)
        CombatText:RefreshSettingsPanel()
    end)

    panel.checks[#panel.checks + 1] = makeCheck(panel, "Monochrome", 205, -514,
        function() return getSettings().uiMonochrome end,
        function(v) getSettings().uiMonochrome = v end)

    panel.shadowLabel = makeValueRow(panel, -556,
        function() local s=getSettings(); s.uiShadowOffset=clamp(s.uiShadowOffset-1,0,10); CombatText:ApplySystemFonts(true) end,
        function() local s=getSettings(); s.uiShadowOffset=clamp(s.uiShadowOffset+1,0,10); CombatText:ApplySystemFonts(true) end)

    makeButton(panel, "Aplicar", 120, 24, -610, function() CombatText:ApplySystemFonts(false) end)
    makeButton(panel, "Valores Rapzo", 140, 154, -610, function()
        CombatText:ResetDefaults(); CombatText:RefreshSettingsPanel()
    end)
    makeButton(panel, "Restaurar sesion", 150, 304, -610, function()
        CombatText:RestoreOriginal()
        RB:Print("Combat Text: restaurados temporalmente los valores capturados al iniciar sesion.")
    end)

    panel.statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.statusText:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -650)
    panel.statusText:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
    panel.statusText:SetJustifyH("LEFT")

    panel:SetScript("OnShow", function()
        CombatText:RebuildFontCatalog()
        CombatText:RefreshSettingsPanel()
    end)

    settingsPanel = panel
    return panel
end

function CombatText:RefreshSettingsPanel()
    if not settingsPanel then return end
    local s = getSettings()
    for _, check in ipairs(settingsPanel.checks or {}) do
        if check.refresh then check.refresh() end
    end

    if settingsPanel.worldFontLabel then
        local _, entry = resolveFont(s.worldFont, s.worldFontPath)
        settingsPanel.worldFontLabel:SetText(("Fuente 3D: %s%s"):format(
            tostring(s.worldFont),
            entry and entry.source and ("  |cff888888(" .. entry.source .. ")|r") or ""))
    end
    if settingsPanel.scaleLabel then settingsPanel.scaleLabel:SetText(("Escala: %.1f"):format(s.worldScale)) end
    if settingsPanel.gravityLabel then settingsPanel.gravityLabel:SetText(("Gravedad: %.1f"):format(s.worldGravity)) end
    if settingsPanel.durationLabel then settingsPanel.durationLabel:SetText(("Duracion: %.1f s"):format(s.worldDuration)) end
    if settingsPanel.uiFontLabel then settingsPanel.uiFontLabel:SetText("Fuente UI: " .. tostring(s.uiFont)) end
    if settingsPanel.uiSizeLabel then settingsPanel.uiSizeLabel:SetText(("Tamano UI: %d"):format(s.uiSize)) end
    if settingsPanel.outlineButton then
        local label = s.uiOutline == "" and "Outline: Ninguno"
            or (s.uiOutline == "THICKOUTLINE" and "Outline: Grueso" or "Outline: Fino")
        settingsPanel.outlineButton:SetText(label)
    end
    if settingsPanel.shadowLabel then settingsPanel.shadowLabel:SetText(("Sombra UI: %d px"):format(s.uiShadowOffset)) end
    if settingsPanel.statusText then
        settingsPanel.statusText:SetText(("Fuentes disponibles: %d. Comando rapido: /rapzo damage"):format(#fontCatalog))
    end
end

function CombatText:RegisterSettings()
    if settingsCategory then return true end
    if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then return false end
    if not (RB.Config and RB.Config.RegisterBlizzardSettings) then return false end

    RB.Config:RegisterBlizzardSettings()
    local parent = RB.Config.settingsCategory
    if not parent then return false end

    local panel = self:CreateSettingsPanel()
    local ok, category = pcall(Settings.RegisterCanvasLayoutSubcategory, parent, panel, "Combat Text")
    if not ok or not category then return false end
    settingsCategory = category
    return true
end

function CombatText:OpenSettings()
    self:RegisterSettings()
    if Settings and Settings.OpenToCategory and settingsCategory and settingsCategory.GetID then
        Settings.OpenToCategory(settingsCategory:GetID())
        return
    end
    if RB.Config and RB.Config.Show then RB.Config:Show() end
end

function CombatText:HandleSlash(rest)
    rest = tostring(rest or "")
    local command, arg = rest:match("^%s*(%S*)%s*(.-)%s*$")
    command = string.lower(command or "")
    arg = tostring(arg or "")

    if command == "" or command == "config" then
        self:OpenSettings()
    elseif command == "status" then
        self:PrintStatus()
    elseif command == "on" then
        self:SetEnabled(true); self:PrintStatus()
    elseif command == "off" then
        self:SetEnabled(false); self:PrintStatus()
    elseif command == "apply" then
        self:ApplySystemFonts(false)
    elseif command == "reset" then
        self:ResetDefaults()
    elseif command == "restore" then
        self:RestoreOriginal(); RB:Print("Combat Text: valores de sesion restaurados.")
    elseif command == "scale" then
        local value = tonumber(arg)
        if not value then RB:Print("Uso: /rapzo damage scale <0.5-5>") return end
        getSettings().worldScale = clamp(value, 0.5, 5)
        self:ApplySystemFonts(true); self:PrintStatus()
    elseif command == "gravity" then
        local value = tonumber(arg)
        if not value then RB:Print("Uso: /rapzo damage gravity <-10 a 10>") return end
        getSettings().worldGravity = clamp(value, -10, 10)
        self:ApplySystemFonts(true); self:PrintStatus()
    elseif command == "duration" then
        local value = tonumber(arg)
        if not value then RB:Print("Uso: /rapzo damage duration <0.1-3>") return end
        getSettings().worldDuration = clamp(value, 0.1, 3)
        self:ApplySystemFonts(true); self:PrintStatus()
    elseif command == "font" then
        local direction = string.lower(arg)
        self:CycleWorldFont(direction == "prev" and -1 or 1)
        self:PrintStatus()
    else
        self:PrintStatus()
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo damage|r - abre la configuracion")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo damage on|off|r - activa/desactiva")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo damage font [next|prev]|r - cambia la fuente 3D")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo damage scale <0.5-5>|r")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo damage gravity <-10 a 10>|r")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo damage duration <0.1-3>|r")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo damage restore|r - restaura los valores capturados al login")
    end
end

RB:RegisterCommand("damage", function(rest) CombatText:HandleSlash(rest) end,
    "/rapzo damage [config|status|on|off|font|scale|gravity|duration|restore] - personaliza el texto de combate")
RB:RegisterCommand("combattext", function(rest) CombatText:HandleSlash(rest) end)

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        captureOriginal()
        CombatText:RebuildFontCatalog()
        if isEnabled() then CombatText:ApplySystemFonts(true) end
        if C_Timer and C_Timer.After then
            C_Timer.After(0.75, function() CombatText:RegisterSettings() end)
        else
            CombatText:RegisterSettings()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if isEnabled() then CombatText:ApplySystemFonts(true) end
    end
end)
RB:RegisterEventSafe(eventFrame, "PLAYER_LOGIN")
RB:RegisterEventSafe(eventFrame, "PLAYER_ENTERING_WORLD")

local lsm = getLSM()
if lsm and lsm.RegisterCallback and not lsmCallbackRegistered then
    local ok = pcall(lsm.RegisterCallback, CombatText, "LibSharedMedia_Registered", function()
        CombatText:RebuildFontCatalog()
        if isEnabled() then CombatText:ApplySystemFonts(true) end
    end)
    lsmCallbackRegistered = ok and true or false
end
