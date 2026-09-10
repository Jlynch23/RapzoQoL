local addonName = ...
local RB = _G.RapzoBags or _G.RapzoQoL
if not RB then return end

-- CooldownPulse: aviso visual cuando un poder termina su cooldown.
-- Midnight / 12.1: no hacemos aritmetica con startTime/duration durante combate.
-- C_Spell.GetSpellCooldown().isActive es NeverSecret; detectamos la transicion
-- true -> false con un polling ligero. Esto tambien tolera resets y reducciones
-- dinamicas de cooldown sin intentar predecir el instante de finalizacion.
local CooldownPulse = {}
RB.CooldownPulse = CooldownPulse
RB:RegisterModule("cooldownPulse", CooldownPulse)

local BANK_PLAYER = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
local TYPE_SPELL = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1
local POLL_INTERVAL = 0.10
local DEFAULT_MIN_COOLDOWN = 8
local DEFAULT_ICON_SIZE = 96
local DEFAULT_Y = 145

local engine = CreateFrame("Frame")
local visual
local settingsPanel
local settingsCategory
local accumulator = 0
local catalog = {}
local states = {}
local initialized = false
local moverMode = false
local pulseElapsed = 0
local pulseDuration = 1.05

local function clamp(value, low, high)
    value = tonumber(value) or low
    if value < low then return low end
    if value > high then return high end
    return value
end

local function getSettings()
    local db = RB:EnsureDB()
    db.settings.cooldownPulse = type(db.settings.cooldownPulse) == "table" and db.settings.cooldownPulse or {}
    local s = db.settings.cooldownPulse
    if s.minCooldown == nil then s.minCooldown = DEFAULT_MIN_COOLDOWN end
    if s.iconSize == nil then s.iconSize = DEFAULT_ICON_SIZE end
    if s.onlyCombat == nil then s.onlyCombat = false end
    if s.showName == nil then s.showName = true end
    if s.sound == nil then s.sound = false end
    if s.x == nil then s.x = 0 end
    if s.y == nil then s.y = DEFAULT_Y end
    s.ignored = type(s.ignored) == "table" and s.ignored or {}
    s.minCooldown = clamp(s.minCooldown, 2, 120)
    s.iconSize = clamp(s.iconSize, 56, 180)
    return s
end

local function isEnabled()
    return RB:IsFeatureEnabled("cooldownPulse", true)
end

local function getSpellInfo(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and info then
            return info.name, info.iconID
        end
    end
    return nil
end

local function getBaseCooldown(spellID)
    if not (C_Spell and C_Spell.GetSpellBaseCooldown) then return nil end
    local ok, ms = pcall(C_Spell.GetSpellBaseCooldown, spellID)
    if ok and type(ms) == "number" and ms > 0 then
        return ms / 1000
    end
    return nil
end

local function getCooldownActive(spellID)
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
    if not ok or type(info) ~= "table" then return nil end
    if type(info.isActive) == "boolean" then
        return info.isActive
    end
    return nil
end

local function getAccent()
    if type(RB.GetAccentColor) == "function" then
        return RB:GetAccentColor()
    end
    return 0.22, 0.83, 0.98
end

local function createVisual()
    if visual then return visual end

    local f = CreateFrame("Frame", "RapzoQoLCooldownPulseFrame", UIParent, "BackdropTemplate")
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:EnableMouse(false)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2,
    })
    f:SetBackdropColor(0.015, 0.02, 0.03, 0.93)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
    icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.icon = icon

    local ready = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ready:SetPoint("BOTTOM", f, "TOP", 0, 8)
    ready:SetText("LISTO")
    f.ready = ready

    local name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("TOP", f, "BOTTOM", 0, -7)
    name:SetWidth(280)
    name:SetJustifyH("CENTER")
    f.nameText = name

    local mover = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mover:SetPoint("CENTER", f, "CENTER", 0, 0)
    mover:SetWidth(260)
    mover:SetText("MOVER\nCOOLDOWN PULSE")
    mover:Hide()
    f.moverText = mover

    f:SetScript("OnDragStart", function(self)
        if moverMode then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        if not moverMode then return end
        self:StopMovingOrSizing()
        local cx, cy = self:GetCenter()
        local px, py = UIParent:GetCenter()
        if cx and cy and px and py then
            local s = getSettings()
            s.x, s.y = cx - px, cy - py
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", s.x, s.y)
        end
    end)

    f:SetScript("OnUpdate", function(self, elapsed)
        if moverMode then
            self:SetAlpha(1)
            self:SetScale(1)
            return
        end

        pulseElapsed = pulseElapsed + elapsed
        local t = pulseElapsed
        if t >= pulseDuration then
            self:Hide()
            self:SetAlpha(1)
            self:SetScale(1)
            return
        end

        if t < 0.12 then
            local p = t / 0.12
            self:SetScale(0.68 + (0.42 * p))
            self:SetAlpha(clamp(p, 0, 1))
        elseif t < 0.22 then
            local p = (t - 0.12) / 0.10
            self:SetScale(1.10 - (0.10 * p))
            self:SetAlpha(1)
        elseif t > 0.70 then
            local p = (t - 0.70) / (pulseDuration - 0.70)
            self:SetScale(1)
            self:SetAlpha(1 - clamp(p, 0, 1))
        else
            self:SetScale(1)
            self:SetAlpha(1)
        end
    end)

    visual = f
    CooldownPulse:ApplyVisualSettings()
    f:Hide()
    return f
end

function CooldownPulse:ApplyVisualSettings()
    local f = visual or createVisual()
    local s = getSettings()
    local size = s.iconSize
    f:SetSize(size, size)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", s.x or 0, s.y or DEFAULT_Y)
    local r, g, b = getAccent()
    f:SetBackdropBorderColor(r, g, b, 0.95)
    f.ready:SetTextColor(r, g, b)
    f.nameText:SetShown(s.showName == true)
end

local function showPulse(entry, force)
    if not force then
        if not isEnabled() then return end
        local s = getSettings()
        if s.onlyCombat and not UnitAffectingCombat("player") then return end
        if s.ignored[entry.key] then return end
    end

    local f = createVisual()
    if moverMode then return end
    CooldownPulse:ApplyVisualSettings()
    f.icon:SetTexture(entry.icon or 134400)
    f.nameText:SetText(entry.name or ("Spell " .. tostring(entry.spellID or entry.key)))
    f.moverText:Hide()
    f.icon:Show()
    f.ready:SetText("LISTO")
    f.ready:Show()
    pulseElapsed = 0
    f:SetAlpha(0)
    f:SetScale(0.68)
    f:Show()
    f:Raise()

    local s = getSettings()
    if s.sound then
        local soundID = SOUNDKIT and SOUNDKIT.READY_CHECK or 8960
        pcall(PlaySound, soundID, "Master")
    end
end

local function clearCatalog()
    wipe(catalog)
    wipe(states)
end

function CooldownPulse:ScanSpells()
    clearCatalog()
    local s = getSettings()
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo and C_SpellBook.GetSpellBookItemInfo) then
        return 0
    end

    local numLines = C_SpellBook.GetNumSpellBookSkillLines() or 0
    local seen = {}

    for lineIndex = 1, numLines do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(lineIndex)
        if line and not line.shouldHide and not line.offSpecID then
            local first = (tonumber(line.itemIndexOffset) or 0) + 1
            local last = first + (tonumber(line.numSpellBookItems) or 0) - 1

            for slot = first, last do
                local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, slot, BANK_PLAYER)
                if ok and info and info.itemType == TYPE_SPELL and not info.isPassive and not info.isOffSpec then
                    local key = tonumber(info.actionID)
                    local spellID = tonumber(info.spellID) or key
                    if key and spellID and not seen[key] then
                        local baseCD = getBaseCooldown(spellID) or getBaseCooldown(key)
                        if baseCD and baseCD >= s.minCooldown then
                            local name, icon = getSpellInfo(spellID)
                            if name then
                                seen[key] = true
                                local entry = {
                                    key = key,
                                    spellID = spellID,
                                    name = name,
                                    icon = icon,
                                    baseCooldown = baseCD,
                                }
                                catalog[#catalog + 1] = entry
                                states[key] = getCooldownActive(spellID)
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(catalog, function(a, b)
        if a.baseCooldown == b.baseCooldown then
            return (a.name or "") < (b.name or "")
        end
        return a.baseCooldown < b.baseCooldown
    end)

    initialized = true
    self:RefreshSettingsPanel()
    return #catalog
end

local function pollCooldowns()
    if not initialized then return end
    local s = getSettings()

    for _, entry in ipairs(catalog) do
        if not s.ignored[entry.key] then
            local active = getCooldownActive(entry.spellID)
            if active ~= nil then
                local previous = states[entry.key]
                if previous == true and active == false then
                    showPulse(entry, false)
                end
                states[entry.key] = active
            end
        end
    end
end

function CooldownPulse:SetEnabled(enabled)
    RB:SetFeatureEnabled("cooldownPulse", enabled == true, true)
    if enabled then
        self:ScanSpells()
    elseif visual and not moverMode then
        visual:Hide()
    end
    self:RefreshSettingsPanel()
end

function CooldownPulse:SetMover(enabled)
    moverMode = enabled == true
    local f = createVisual()
    f:EnableMouse(moverMode)
    if moverMode then
        self:ApplyVisualSettings()
        f.icon:Hide()
        f.ready:Hide()
        f.nameText:Hide()
        f.moverText:Show()
        f:SetAlpha(1)
        f:SetScale(1)
        f:Show()
        f:Raise()
    else
        f.moverText:Hide()
        f.icon:Show()
        f.ready:Show()
        f.nameText:SetShown(getSettings().showName == true)
        f:Hide()
    end
    self:RefreshSettingsPanel()
end

function CooldownPulse:Test()
    local _, classFile = UnitClass("player")
    local testSpell = catalog[1]
    if not testSpell then
        testSpell = {
            key = 0,
            spellID = 0,
            name = (classFile or "RAPZO") .. " - Cooldown listo",
            icon = 134400,
        }
    end
    showPulse(testSpell, true)
end

local function resolveEntry(text)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    local id = tonumber(text)
    local lower = string.lower(text)
    for _, entry in ipairs(catalog) do
        if id and (entry.key == id or entry.spellID == id) then return entry end
        if not id and string.lower(entry.name or "") == lower then return entry end
    end
    return nil
end

function CooldownPulse:SetSpellIgnored(entry, ignored)
    if not entry then return false end
    local s = getSettings()
    if ignored then
        s.ignored[entry.key] = true
        states[entry.key] = nil
    else
        s.ignored[entry.key] = nil
        states[entry.key] = getCooldownActive(entry.spellID)
    end
    self:RefreshSettingsPanel()
    return true
end

function CooldownPulse:PrintStatus()
    local s = getSettings()
    local ignored = 0
    for _, entry in ipairs(catalog) do
        if s.ignored[entry.key] then ignored = ignored + 1 end
    end
    RB:Print(("Cooldown Pulse %s | %d detectados | %d ignorados | minimo %ss | icono %dpx | combate %s | sonido %s"):format(
        isEnabled() and "ON" or "OFF",
        #catalog,
        ignored,
        tostring(s.minCooldown),
        s.iconSize,
        s.onlyCombat and "solo" or "siempre",
        s.sound and "ON" or "OFF"
    ))
end

function CooldownPulse:PrintList()
    local s = getSettings()
    RB:Print("Poderes detectados por Cooldown Pulse:")
    for _, entry in ipairs(catalog) do
        DEFAULT_CHAT_FRAME:AddMessage(("  %s %s | ID %d | %.0fs"):format(
            s.ignored[entry.key] and "|cffef4444OFF|r" or "|cff38e66bON |r",
            entry.name or "?",
            entry.key,
            entry.baseCooldown or 0
        ))
    end
end

local function makeCheck(parent, label, x, y, getValue, setValue)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    check:SetSize(26, 26)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", check, "RIGHT", 5, 0)
    text:SetText(label)
    check.label = text
    check.refresh = function()
        check:SetChecked(getValue() == true)
    end
    check:SetScript("OnClick", function(self)
        setValue(self:GetChecked() == true)
        CooldownPulse:RefreshSettingsPanel()
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

function CooldownPulse:CreateSettingsPanel()
    if settingsPanel then return settingsPanel end

    local panel = CreateFrame("Frame", "RapzoQoLCooldownPulseSettingsPanel")
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -18)
    title:SetText("Cooldown Pulse")

    local intro = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    intro:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
    intro:SetJustifyH("LEFT")
    intro:SetText("Te avisa en pantalla justo cuando un poder termina su cooldown. Diseñado para las restricciones de combate de Midnight 12.1.")

    panel.checks = {}
    panel.checks[#panel.checks + 1] = makeCheck(panel, "Activar Cooldown Pulse", 22, -92,
        isEnabled,
        function(v) CooldownPulse:SetEnabled(v) end)
    panel.checks[#panel.checks + 1] = makeCheck(panel, "Avisar solo durante combate", 22, -126,
        function() return getSettings().onlyCombat end,
        function(v) getSettings().onlyCombat = v end)
    panel.checks[#panel.checks + 1] = makeCheck(panel, "Mostrar nombre del poder", 22, -160,
        function() return getSettings().showName end,
        function(v) getSettings().showName = v; CooldownPulse:ApplyVisualSettings() end)
    panel.checks[#panel.checks + 1] = makeCheck(panel, "Sonido al quedar listo", 22, -194,
        function() return getSettings().sound end,
        function(v) getSettings().sound = v end)

    local minLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    minLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -244)
    panel.minLabel = minLabel
    makeButton(panel, "-", 32, 250, -236, function()
        local s = getSettings(); s.minCooldown = clamp(s.minCooldown - 1, 2, 120)
        CooldownPulse:ScanSpells(); CooldownPulse:RefreshSettingsPanel()
    end)
    makeButton(panel, "+", 32, 288, -236, function()
        local s = getSettings(); s.minCooldown = clamp(s.minCooldown + 1, 2, 120)
        CooldownPulse:ScanSpells(); CooldownPulse:RefreshSettingsPanel()
    end)

    local sizeLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sizeLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -284)
    panel.sizeLabel = sizeLabel
    makeButton(panel, "-", 32, 250, -276, function()
        local s = getSettings(); s.iconSize = clamp(s.iconSize - 8, 56, 180)
        CooldownPulse:ApplyVisualSettings(); CooldownPulse:RefreshSettingsPanel()
    end)
    makeButton(panel, "+", 32, 288, -276, function()
        local s = getSettings(); s.iconSize = clamp(s.iconSize + 8, 56, 180)
        CooldownPulse:ApplyVisualSettings(); CooldownPulse:RefreshSettingsPanel()
    end)

    makeButton(panel, "Probar alerta", 140, 22, -328, function() CooldownPulse:Test() end)
    panel.moveButton = makeButton(panel, "Mover alerta", 140, 172, -328, function()
        CooldownPulse:SetMover(not moverMode)
    end)
    makeButton(panel, "Reescanear poderes", 165, 322, -328, function()
        CooldownPulse:ScanSpells()
        CooldownPulse:RefreshSettingsPanel()
    end)

    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -382)
    status:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
    status:SetJustifyH("LEFT")
    panel.statusText = status

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -430)
    hint:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("Control por poder: /rapzo pulse list  |  /rapzo pulse ignore <ID>  |  /rapzo pulse enable <ID>\nEl ID aparece en la lista. Por defecto se vigilan todos los poderes activos de la spec cuyo cooldown base supera el minimo configurado.")

    panel:SetScript("OnShow", function() CooldownPulse:RefreshSettingsPanel() end)
    settingsPanel = panel
    return panel
end

function CooldownPulse:RefreshSettingsPanel()
    if not settingsPanel then return end
    for _, check in ipairs(settingsPanel.checks or {}) do
        if check.refresh then check.refresh() end
    end
    local s = getSettings()
    if settingsPanel.minLabel then
        settingsPanel.minLabel:SetText(("Cooldown minimo: %d segundos"):format(s.minCooldown))
    end
    if settingsPanel.sizeLabel then
        settingsPanel.sizeLabel:SetText(("Tamano del icono: %d px"):format(s.iconSize))
    end
    if settingsPanel.moveButton then
        settingsPanel.moveButton:SetText(moverMode and "Fijar posicion" or "Mover alerta")
    end
    if settingsPanel.statusText then
        local ignored = 0
        for _, entry in ipairs(catalog) do
            if s.ignored[entry.key] then ignored = ignored + 1 end
        end
        settingsPanel.statusText:SetText(("Detectados: %d   |   Activos para avisar: %d   |   Ignorados: %d"):format(
            #catalog, math.max(0, #catalog - ignored), ignored))
    end
end

function CooldownPulse:RegisterSettings()
    if settingsCategory then return true end
    if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then return false end
    if not (RB.Config and RB.Config.RegisterBlizzardSettings) then return false end

    RB.Config:RegisterBlizzardSettings()
    local parent = RB.Config.settingsCategory
    if not parent then return false end

    local panel = self:CreateSettingsPanel()
    local ok, category = pcall(Settings.RegisterCanvasLayoutSubcategory, parent, panel, "Cooldown Pulse")
    if not ok or not category then return false end
    settingsCategory = category
    return true
end

function CooldownPulse:OpenSettings()
    self:RegisterSettings()
    if Settings and Settings.OpenToCategory and settingsCategory and settingsCategory.GetID then
        Settings.OpenToCategory(settingsCategory:GetID())
        return
    end
    if RB.Config and RB.Config.Show then
        RB.Config:Show()
    end
end

function CooldownPulse:HandleSlash(rest)
    rest = tostring(rest or "")
    local command, arg = rest:match("^%s*(%S*)%s*(.-)%s*$")
    command = string.lower(command or "")

    if command == "" or command == "config" then
        self:OpenSettings()
    elseif command == "status" then
        self:PrintStatus()
    elseif command == "on" then
        self:SetEnabled(true); self:PrintStatus()
    elseif command == "off" then
        self:SetEnabled(false); self:PrintStatus()
    elseif command == "test" then
        self:Test()
    elseif command == "move" or command == "unlock" then
        self:SetMover(not moverMode)
    elseif command == "list" then
        self:PrintList()
    elseif command == "ignore" or command == "disable" then
        local entry = resolveEntry(arg)
        if entry and self:SetSpellIgnored(entry, true) then
            RB:Print("Cooldown Pulse: " .. entry.name .. " ignorado.")
        else
            RB:Print("No encontre ese poder. Usa /rapzo pulse list para ver IDs.")
        end
    elseif command == "enable" then
        local entry = resolveEntry(arg)
        if entry and self:SetSpellIgnored(entry, false) then
            RB:Print("Cooldown Pulse: " .. entry.name .. " activado.")
        else
            RB:Print("No encontre ese poder. Usa /rapzo pulse list para ver IDs.")
        end
    elseif command == "reset" then
        wipe(getSettings().ignored)
        self:ScanSpells()
        RB:Print("Cooldown Pulse: lista de poderes restablecida.")
    elseif command == "combat" then
        local s = getSettings()
        local value = string.lower(arg or "")
        if value == "on" then s.onlyCombat = true
        elseif value == "off" then s.onlyCombat = false
        else s.onlyCombat = not s.onlyCombat end
        self:PrintStatus()
    elseif command == "sound" then
        local s = getSettings()
        local value = string.lower(arg or "")
        if value == "on" then s.sound = true
        elseif value == "off" then s.sound = false
        else s.sound = not s.sound end
        self:PrintStatus()
    elseif command == "min" then
        local value = tonumber(arg)
        if not value then
            RB:Print("Uso: /rapzo pulse min <segundos>")
        else
            getSettings().minCooldown = clamp(value, 2, 120)
            self:ScanSpells(); self:PrintStatus()
        end
    elseif command == "size" then
        local value = tonumber(arg)
        if not value then
            RB:Print("Uso: /rapzo pulse size <56-180>")
        else
            getSettings().iconSize = clamp(value, 56, 180)
            self:ApplyVisualSettings(); self:PrintStatus()
        end
    else
        self:PrintStatus()
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo pulse|r - abre la configuracion")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo pulse test|r - prueba la alerta")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo pulse list|r - lista poderes detectados e IDs")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo pulse ignore <ID>|r - no avisar ese poder")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo pulse enable <ID>|r - volver a avisar ese poder")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo pulse min <seg>|r - cooldown minimo")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo pulse move|r - mover/fijar el aviso")
    end
end

RB:RegisterCommand("pulse", function(rest) CooldownPulse:HandleSlash(rest) end,
    "/rapzo pulse [config|status|on|off|test|list|ignore|enable|min|size|move] - aviso de cooldown listo")

engine:SetScript("OnUpdate", function(_, elapsed)
    if not initialized or not isEnabled() then return end
    accumulator = accumulator + elapsed
    if accumulator < POLL_INTERVAL then return end
    accumulator = accumulator % POLL_INTERVAL
    pollCooldowns()
end)

local function scheduleScan(delay)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay or 0.15, function()
            if CooldownPulse then CooldownPulse:ScanSpells() end
        end)
    else
        CooldownPulse:ScanSpells()
    end
end

engine:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        getSettings()
        createVisual()
        scheduleScan(0.35)
        if C_Timer and C_Timer.After then
            C_Timer.After(0.60, function() CooldownPulse:RegisterSettings() end)
        else
            CooldownPulse:RegisterSettings()
        end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if not unit or unit == "player" then scheduleScan(0.25) end
    elseif event == "SPELLS_CHANGED" or event == "TRAIT_CONFIG_UPDATED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        scheduleScan(0.25)
    end
end)

for _, event in ipairs({
    "PLAYER_LOGIN",
    "SPELLS_CHANGED",
    "PLAYER_SPECIALIZATION_CHANGED",
    "TRAIT_CONFIG_UPDATED",
    "ACTIVE_TALENT_GROUP_CHANGED",
}) do
    RB:RegisterEventSafe(engine, event)
end
