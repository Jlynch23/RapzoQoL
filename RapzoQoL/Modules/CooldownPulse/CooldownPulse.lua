local addonName = ...
local RB = _G.RapzoBags or _G.RapzoQoL
if not RB then return end

-- CooldownPulse: aviso visual cuando un poder vuelve a estar disponible.
-- WoW 12.1 / Midnight: los numeros exactos del cooldown pueden ser Secret Values
-- durante combate. El motor no depende de ellos: observa isActive/isOnGCD y mide
-- con GetTime() el tiempo real que una habilidad permanecio en cooldown.
local CooldownPulse = {}
RB.CooldownPulse = CooldownPulse
RB:RegisterModule("cooldownPulse", CooldownPulse)

local BANK_PLAYER = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
local TYPE_SPELL = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1
local POLL_INTERVAL = 0.10
local MIN_REAL_COOLDOWN = 1.50
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
local lastScanReason = "sin escanear"
local scanSerial = 0

local issecretvalue = _G.issecretvalue

local function clamp(value, low, high)
    value = tonumber(value) or low
    if value < low then return low end
    if value > high then return high end
    return value
end

local function plain(value)
    if value == nil then return nil end
    if issecretvalue and issecretvalue(value) then return nil end
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
    s.learned = type(s.learned) == "table" and s.learned or {}
    s.minCooldown = clamp(s.minCooldown, 2, 120)
    s.iconSize = clamp(s.iconSize, 56, 180)
    return s
end

local function getLearnedStore()
    local s = getSettings()
    local key = RB.GetCharacterKey and RB:GetCharacterKey() or "character"
    s.learned[key] = type(s.learned[key]) == "table" and s.learned[key] or {}
    return s.learned[key]
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

-- Solo se conserva como dato informativo para el panel. En 12.1 NO se usa para
-- decidir si una habilidad entra al catalogo ni si debe disparar una alerta.
local function getBaseCooldownHint(spellID)
    if not (C_Spell and C_Spell.GetSpellBaseCooldown) then return nil end
    local ok, ms = pcall(C_Spell.GetSpellBaseCooldown, spellID)
    ms = ok and plain(ms) or nil
    if type(ms) == "number" and ms > 0 then
        return ms / 1000
    end
    return nil
end

-- Returns active, onGCD, readableDuration.
local function readCooldown(spellID)
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
    if not ok or type(info) ~= "table" then return nil end

    -- isActive/isOnGCD son NeverSecret en 12.x. Los numeros se aceptan solo si
    -- realmente son valores Lua legibles.
    local active = info.isActive and true or false
    local onGCD = info.isOnGCD and true or false
    local duration = plain(info.duration)
    if type(duration) ~= "number" then duration = nil end
    return active, onGCD, duration
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
    name:SetWidth(300)
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

local function getCoreLineNames()
    local names = {}
    local className = UnitClass and UnitClass("player")
    if className and className ~= "" then names[className] = true end

    local specIndex
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
        local ok, value = pcall(C_SpecializationInfo.GetSpecialization)
        if ok then specIndex = value end
    elseif GetSpecialization then
        local ok, value = pcall(GetSpecialization)
        if ok then specIndex = value end
    end

    if specIndex then
        local specName
        if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
            local ok, _, name = pcall(C_SpecializationInfo.GetSpecializationInfo, specIndex)
            if ok then specName = name end
        elseif GetSpecializationInfo then
            local ok, _, name = pcall(GetSpecializationInfo, specIndex)
            if ok then specName = name end
        end
        if specName and specName ~= "" then names[specName] = true end
    end

    return names
end

local function clearCatalog()
    wipe(catalog)
    wipe(states)
end

local function addSpell(seen, info, group)
    if not info or info.itemType ~= TYPE_SPELL or info.isPassive or info.isOffSpec then return end

    local key = tonumber(info.actionID) or tonumber(info.spellID)
    local spellID = tonumber(info.spellID) or key
    if not key or not spellID or seen[key] then return end

    local name = info.name
    local icon = info.iconID
    if not name or name == "" or not icon then
        local apiName, apiIcon = getSpellInfo(spellID)
        name = name or apiName
        icon = icon or apiIcon
    end
    if not name or name == "" then return end

    seen[key] = true
    local active, onGCD = readCooldown(spellID)
    local running = active == true and onGCD ~= true
    catalog[#catalog + 1] = {
        key = key,
        spellID = spellID,
        name = name,
        icon = icon,
        group = group or "Spells",
        baseCooldownHint = getBaseCooldownHint(spellID) or getBaseCooldownHint(key),
    }

    -- Si escaneamos mientras el poder ya estaba en cooldown, no conocemos su inicio.
    -- Lo dejamos marcado como activo pero sin startedAt para que no genere un falso
    -- aviso al terminar. La siguiente activacion ya queda medida de punta a punta.
    states[key] = {
        on = running,
        startedAt = nil,
    }
end

local function scanLines(coreOnly)
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines
        and C_SpellBook.GetSpellBookSkillLineInfo and C_SpellBook.GetSpellBookItemInfo) then
        lastScanReason = "API C_SpellBook no disponible"
        return 0
    end

    local numLines = C_SpellBook.GetNumSpellBookSkillLines() or 0
    if numLines <= 0 then
        lastScanReason = "spellbook aun no estaba listo"
        return 0
    end

    local coreNames = getCoreLineNames()
    local seen = {}

    for lineIndex = 1, numLines do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(lineIndex)
        -- IMPORTANTE: Lua considera 0 como true. Algunos clientes usan offSpecID=0
        -- para una linea utilizable; por eso `not line.offSpecID` descartaba todo.
        local usable = line and not line.shouldHide and (line.offSpecID == nil or line.offSpecID == 0)
        if usable and coreOnly and not coreNames[line.name or ""] then
            usable = false
        end

        if usable then
            local first = (tonumber(line.itemIndexOffset) or 0) + 1
            local count = tonumber(line.numSpellBookItems) or 0
            local last = first + count - 1

            for slot = first, last do
                local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, slot, BANK_PLAYER)
                if ok then addSpell(seen, info, line.name) end
            end
        end
    end

    return #catalog
end

function CooldownPulse:ScanSpells(verbose)
    clearCatalog()

    local count = scanLines(true)
    if count == 0 then
        -- Fallback defensivo para clientes/localizaciones donde el nombre de la
        -- linea de clase/spec no coincide con lo que devuelve UnitClass/spec info.
        clearCatalog()
        count = scanLines(false)
    end

    table.sort(catalog, function(a, b)
        if a.group ~= b.group then return tostring(a.group) < tostring(b.group) end
        return tostring(a.name) < tostring(b.name)
    end)

    initialized = true
    if count > 0 then
        lastScanReason = ("%d poderes activos encontrados"):format(count)
    elseif lastScanReason == "sin escanear" then
        lastScanReason = "0 poderes encontrados"
    end

    self:RefreshSettingsPanel()
    if verbose then
        if count > 0 then
            RB:Print(("Cooldown Pulse: %d poderes detectados."):format(count))
        else
            RB:Print("Cooldown Pulse: no pude leer el spellbook todavia; reintentare automaticamente.")
        end
    end
    return count
end

local function learnedDuration(entry)
    return tonumber(getLearnedStore()[entry.key])
end

local function learnDuration(entry, elapsed)
    if not entry or not elapsed or elapsed < MIN_REAL_COOLDOWN then return end
    local store = getLearnedStore()
    local known = tonumber(store[entry.key])
    if not known or elapsed > known then
        store[entry.key] = math.floor((elapsed * 10) + 0.5) / 10
    end
end

local function handleEntry(entry, now)
    local active, onGCD = readCooldown(entry.spellID)
    if active == nil then return end

    local running = active and not onGCD
    local st = states[entry.key]
    if type(st) ~= "table" then
        st = { on = running, startedAt = nil }
        states[entry.key] = st
        return
    end

    if running then
        if not st.on then
            st.on = true
            st.startedAt = now
        end
        return
    end

    if st.on then
        st.on = false
        local startedAt = st.startedAt
        st.startedAt = nil

        -- Si estaba activo desde antes del escaneo no sabemos cuanto duro realmente;
        -- esa primera finalizacion se usa solo para sincronizar el estado.
        if not startedAt then return end

        local elapsed = now - startedAt
        if elapsed < MIN_REAL_COOLDOWN then return end
        learnDuration(entry, elapsed)

        local known = learnedDuration(entry) or elapsed
        if math.max(elapsed, known) >= getSettings().minCooldown then
            showPulse(entry, false)
        end
    end
end

local function pollCooldowns()
    if not initialized then return end
    local s = getSettings()
    local now = GetTime()

    for _, entry in ipairs(catalog) do
        if not s.ignored[entry.key] then
            handleEntry(entry, now)
        end
    end
end

function CooldownPulse:SetEnabled(enabled)
    RB:SetFeatureEnabled("cooldownPulse", enabled == true, true)
    if enabled then
        self:ScanSpells(false)
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
        local active, onGCD = readCooldown(entry.spellID)
        states[entry.key] = { on = active == true and onGCD ~= true, startedAt = nil }
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
    if #catalog == 0 then RB:Print("Escaneo: " .. tostring(lastScanReason)) end
end

function CooldownPulse:PrintList()
    local s = getSettings()
    local learned = getLearnedStore()
    RB:Print(("Poderes detectados por Cooldown Pulse: %d"):format(#catalog))
    if #catalog == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("  |cffef4444Ninguno.|r Usa /rapzo pulse scan para reintentar.")
        return
    end

    for _, entry in ipairs(catalog) do
        local known = tonumber(learned[entry.key])
        local length = known and (("%.1fs aprendido"):format(known)) or "duracion por aprender"
        DEFAULT_CHAT_FRAME:AddMessage(("  %s %s | ID %d | %s"):format(
            s.ignored[entry.key] and "|cffef4444OFF|r" or "|cff38e66bON |r",
            entry.name or "?",
            entry.key,
            length
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

local function ensureSpellRow(index)
    local panel = settingsPanel
    if not panel or not panel.spellChild then return nil end
    panel.spellRows = panel.spellRows or {}
    if panel.spellRows[index] then return panel.spellRows[index] end

    local row = CreateFrame("Frame", nil, panel.spellChild)
    row:SetHeight(28)
    row:SetPoint("TOPLEFT", panel.spellChild, "TOPLEFT", 0, -((index - 1) * 28))
    row:SetPoint("RIGHT", panel.spellChild, "RIGHT", -4, 0)

    local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    check:SetPoint("LEFT", row, "LEFT", 0, 0)
    check:SetSize(24, 24)
    row.check = check

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("LEFT", check, "RIGHT", 2, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("LEFT", icon, "RIGHT", 7, 0)
    name:SetWidth(245)
    name:SetJustifyH("LEFT")
    row.nameText = name

    local meta = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    meta:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    meta:SetWidth(160)
    meta:SetJustifyH("RIGHT")
    row.metaText = meta

    check:SetScript("OnClick", function(self)
        local entry = row.entry
        if not entry then return end
        local enabled = self:GetChecked() == true
        CooldownPulse:SetSpellIgnored(entry, not enabled)
    end)

    panel.spellRows[index] = row
    return row
end

function CooldownPulse:RefreshSpellRows()
    if not settingsPanel or not settingsPanel.spellChild then return end
    local s = getSettings()
    local learned = getLearnedStore()
    local r, g, b = getAccent()

    settingsPanel.spellChild:SetHeight(math.max(1, #catalog * 28))
    for i, entry in ipairs(catalog) do
        local row = ensureSpellRow(i)
        row.entry = entry
        row.icon:SetTexture(entry.icon or 134400)
        row.check:SetChecked(not s.ignored[entry.key])
        row.nameText:SetText(entry.name or "?")
        if s.ignored[entry.key] then
            row.nameText:SetTextColor(0.55, 0.55, 0.55)
        else
            row.nameText:SetTextColor(r, g, b)
        end

        local known = tonumber(learned[entry.key])
        if known then
            row.metaText:SetText(("ID %d · %.1fs"):format(entry.key, known))
        else
            row.metaText:SetText(("ID %d · aprendiendo"):format(entry.key))
        end
        row:Show()
    end

    for i = #catalog + 1, #(settingsPanel.spellRows or {}) do
        settingsPanel.spellRows[i]:Hide()
    end

    if settingsPanel.emptyText then
        settingsPanel.emptyText:SetShown(#catalog == 0)
        if #catalog == 0 then
            settingsPanel.emptyText:SetText("No se detectaron poderes todavia. Pulsa Reescanear poderes.")
        end
    end
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
    intro:SetText("Te avisa justo cuando una habilidad vuelve a estar lista. El motor mide el cooldown real y no depende de los valores numericos secretos de Midnight 12.1.")

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
        CooldownPulse:RefreshSettingsPanel()
    end)
    makeButton(panel, "+", 32, 288, -236, function()
        local s = getSettings(); s.minCooldown = clamp(s.minCooldown + 1, 2, 120)
        CooldownPulse:RefreshSettingsPanel()
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
        CooldownPulse:ScanSpells(true)
    end)

    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -374)
    status:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
    status:SetJustifyH("LEFT")
    panel.statusText = status

    local spellsTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    spellsTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -410)
    spellsTitle:SetText("Poderes de tu clase / especializacion")

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -436)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -46, 52)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(470)
    child:SetHeight(1)
    scroll:SetScrollChild(child)
    panel.spellScroll = scroll
    panel.spellChild = child
    panel.spellRows = {}

    local empty = child:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOPLEFT", child, "TOPLEFT", 6, -8)
    empty:SetWidth(430)
    empty:SetJustifyH("LEFT")
    panel.emptyText = empty

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 24, 18)
    hint:SetText("Marca/desmarca poderes directamente. La duracion se aprende al usarlos; el minimo se aplica al cooldown real medido.")

    panel:SetScript("OnShow", function()
        CooldownPulse:ScanSpells(false)
        CooldownPulse:RefreshSettingsPanel()
    end)
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
        settingsPanel.minLabel:SetText(("Cooldown minimo real: %d segundos"):format(s.minCooldown))
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
        settingsPanel.statusText:SetText(("Detectados: %d   |   Seleccionados: %d   |   %s"):format(
            #catalog, math.max(0, #catalog - ignored), tostring(lastScanReason)))
    end
    self:RefreshSpellRows()
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
    elseif command == "scan" then
        self:ScanSpells(true)
        self:PrintStatus()
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
        self:ScanSpells(false)
        RB:Print("Cooldown Pulse: todos los poderes volvieron a estar seleccionados.")
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
            self:RefreshSettingsPanel(); self:PrintStatus()
        end
    elseif command == "size" then
        local value = tonumber(arg)
        if not value then
            RB:Print("Uso: /rapzo pulse size <56-180>")
        else
            getSettings().iconSize = clamp(value, 56, 180)
            self:ApplyVisualSettings(); self:RefreshSettingsPanel(); self:PrintStatus()
        end
    else
        self:PrintStatus()
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo pulse|r - abre la configuracion")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo pulse scan|r - fuerza un nuevo escaneo")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo pulse test|r - prueba la alerta")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo pulse list|r - lista poderes detectados e IDs")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo pulse ignore <ID>|r - no avisar ese poder")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo pulse enable <ID>|r - volver a avisar ese poder")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo pulse min <seg>|r - cooldown minimo real")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff38bdf8/rapzo pulse move|r - mover/fijar el aviso")
    end
end

RB:RegisterCommand("pulse", function(rest) CooldownPulse:HandleSlash(rest) end,
    "/rapzo pulse [config|status|on|off|scan|test|list|ignore|enable|min|size|move] - aviso de cooldown listo")

engine:SetScript("OnUpdate", function(_, elapsed)
    if not initialized or not isEnabled() then return end
    accumulator = accumulator + elapsed
    if accumulator < POLL_INTERVAL then return end
    accumulator = accumulator % POLL_INTERVAL
    pollCooldowns()
end)

local function scheduleScan(delay, retries)
    scanSerial = scanSerial + 1
    local serial = scanSerial
    retries = tonumber(retries) or 0

    local function run()
        if serial ~= scanSerial then return end
        local count = CooldownPulse:ScanSpells(false)
        if count == 0 and retries > 0 and C_Timer and C_Timer.After then
            retries = retries - 1
            C_Timer.After(0.75, run)
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(delay or 0.15, run)
    else
        run()
    end
end

engine:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        getSettings()
        createVisual()
        scheduleScan(0.35, 3)
        if C_Timer and C_Timer.After then
            C_Timer.After(0.70, function() CooldownPulse:RegisterSettings() end)
        else
            CooldownPulse:RegisterSettings()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        scheduleScan(0.50, 2)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if not unit or unit == "player" then scheduleScan(0.30, 2) end
    elseif event == "SPELLS_CHANGED" or event == "TRAIT_CONFIG_UPDATED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        scheduleScan(0.25, 2)
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        -- isOnGCD esta documentado como especialmente fiable al responder a este
        -- evento, asi que hacemos una lectura inmediata ademas del polling de 0.1 s.
        if initialized and isEnabled() then pollCooldowns() end
    end
end)

for _, event in ipairs({
    "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD",
    "SPELLS_CHANGED",
    "SPELL_UPDATE_COOLDOWN",
    "PLAYER_SPECIALIZATION_CHANGED",
    "TRAIT_CONFIG_UPDATED",
    "ACTIVE_TALENT_GROUP_CHANGED",
}) do
    RB:RegisterEventSafe(engine, event)
end
