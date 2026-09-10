local addonName = ...
local RB = _G.RapzoBags
if not RB then return end

local HUD = {}
RB.HUD = HUD
RB:RegisterModule("hud", HUD)

HUD.initialized = false
HUD.eventFrame = nil
HUD.cursorFrame = nil
HUD.unitDisplays = {}
HUD.config = nil

local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local CURSOR_ATLAS = "GarrLanding-CircleGlow"

local COLORS = {
    player = { 0.92, 0.66, 0.10 },
    target = { 0.92, 0.30, 0.09 },
    focus  = { 0.12, 0.72, 0.95 },
    border = { 0.10, 0.78, 0.96 },
    dark   = { 0.015, 0.020, 0.028 },
    power  = { 0.22, 0.28, 0.38 },
}
-- Compartido con HUDStyles para que V1 restaure exactamente los colores base.
HUD.COLORS = COLORS

local function isSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

local function safeCall(func, ...)
    if type(func) ~= "function" then return false end
    return pcall(func, ...)
end

local function getAccentColor()
    if type(RB.GetAccentColor) == "function" then
        local r, g, b = RB:GetAccentColor()
        return {r, g, b}
    end
    return COLORS.border
end

local function getUnitClassColor(unit, fallback, requirePlayer)
    fallback = fallback or { 0.92, 0.66, 0.10 }

    if requirePlayer and type(UnitIsPlayer) == "function" then
        local okPlayer, isPlayer = pcall(UnitIsPlayer, unit)
        if not okPlayer or isSecret(isPlayer) or isPlayer ~= true then
            return fallback
        end
    end

    if type(UnitClass) ~= "function" or type(RAID_CLASS_COLORS) ~= "table" then
        return fallback
    end

    local okClass, _, classFile = pcall(UnitClass, unit)
    if not okClass or not classFile or isSecret(classFile) then
        return fallback
    end

    local classColor = RAID_CLASS_COLORS[classFile]
    if not classColor then
        return fallback
    end

    return {
        classColor.r or fallback[1],
        classColor.g or fallback[2],
        classColor.b or fallback[3],
    }
end

local function getConfig()
    local db = RB:EnsureDB()
    db.settings.hud = type(db.settings.hud) == "table" and db.settings.hud or {}
    local cfg = db.settings.hud

    -- Separation v1: HUD is only the internal container. Cursor, minimap and
    -- Rapzo unit frames keep their own switches and never depend on a master
    -- visual toggle.
    if cfg.separationVersion ~= 1 then
        local legacyEnabled = cfg.enabled
        if legacyEnabled == nil then
            legacyEnabled = RB:IsFeatureEnabled("hud")
        end

        -- Preserve the old master-OFF intent for unit frames only. Cursor and
        -- minimap retain their own existing choices.
        if cfg.unitFrames == nil or legacyEnabled == false then
            cfg.unitFrames = legacyEnabled ~= false
        end
        cfg.separationVersion = 1
    end

    if cfg.cursor == nil then cfg.cursor = true end
    if cfg.squareMinimap == nil then cfg.squareMinimap = true end
    if cfg.unitFrames == nil then cfg.unitFrames = true end
    if cfg.cursorSize == nil then cfg.cursorSize = 52 end
    if cfg.cursorVisualVersion ~= 3 then
        -- V3 is intentionally compact: the previous 74 px ring covered too
        -- much of the world around the pointer. Migrate existing users once.
        cfg.cursorSize = math.min(56, tonumber(cfg.cursorSize) or 52)
        cfg.cursorVisualVersion = 3
    end

    cfg.cursorSize = math.max(36, math.min(96, tonumber(cfg.cursorSize) or 52))

    -- cfg.enabled belonged to the old master toggle. Keep the module container
    -- loaded so its independent parts can continue working.
    cfg.enabled = nil
    RB:SetFeatureEnabled("hud", true, true)
    HUD.config = cfg
    return cfg
end

function HUD:IsEnabled()
    -- Compatibility name used by HUD frame helpers. From separation v1 this
    -- means "Rapzo unit frames enabled", not a master switch for minimap/cursor.
    local cfg = self.config or getConfig()
    return cfg.unitFrames ~= false
end

-- Preserve whatever alpha Blizzard/mUI had before Rapzo QoL hides native art.
-- This makes the unit-frame toggle fully reversible without requiring /reload.
local nativeRegionAlpha = setmetatable({}, { __mode = "k" })

local function hideNativeRegion(region)
    if not region or type(region.SetAlpha) ~= "function" then return end

    if nativeRegionAlpha[region] == nil then
        local alpha = 1
        if type(region.GetAlpha) == "function" then
            local ok, value = pcall(region.GetAlpha, region)
            if ok and type(value) == "number" then
                alpha = value
            end
        end
        nativeRegionAlpha[region] = alpha
    end

    safeCall(region.SetAlpha, region, 0)
end

local function restoreNativeRegion(region)
    if not region or type(region.SetAlpha) ~= "function" then return end

    local alpha = nativeRegionAlpha[region]
    if alpha == nil then return end

    safeCall(region.SetAlpha, region, alpha)
    nativeRegionAlpha[region] = nil
end

local function setSecretSafeText(fontString, value)
    if not fontString then return end

    if isSecret(value) then
        -- FontString:SetText can consume secret strings directly.
        fontString:SetText(value)
        return
    end

    fontString:SetText(value or "")
end

local function createEdges(parent, color, alpha, thickness)
    local edges = {}
    thickness = thickness or 1
    alpha = alpha or 0.72

    for i = 1, 4 do
        local tex = parent:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(color[1], color[2], color[3], alpha)
        edges[i] = tex
    end

    edges[1]:SetPoint("TOPLEFT", parent, "TOPLEFT", -1, 1)
    edges[1]:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 1, 1)
    edges[1]:SetHeight(thickness)

    edges[2]:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -1, -1)
    edges[2]:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 1, -1)
    edges[2]:SetHeight(thickness)

    edges[3]:SetPoint("TOPLEFT", parent, "TOPLEFT", -1, 1)
    edges[3]:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -1, -1)
    edges[3]:SetWidth(thickness)

    edges[4]:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 1, 1)
    edges[4]:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 1, -1)
    edges[4]:SetWidth(thickness)

    return edges
end

local function createBar(parent, height, color)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(WHITE_TEXTURE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetHeight(height)
    bar:SetStatusBarColor(color[1], color[2], color[3])

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetColorTexture(COLORS.dark[1], COLORS.dark[2], COLORS.dark[3], 0.96)

    local edges = createEdges(bar, color, 0.60, 1)
    bar.RapzoQoLBackground = bg
    bar.RapzoQoLEdges = edges
    return bar
end

local function hidePlayerStaticArt()
    local frame = _G.PlayerFrame
    local container = frame and frame.PlayerFrameContainer
    if container then
        hideNativeRegion(container.PlayerPortrait)
        hideNativeRegion(container.PlayerPortraitMask)
        hideNativeRegion(container.FrameTexture)
        hideNativeRegion(container.VehicleFrameTexture)
        hideNativeRegion(container.AlternatePowerFrameTexture)
        hideNativeRegion(container.FrameFlash)
    end

    local content = frame and frame.PlayerFrameContent
    local main = content and content.PlayerFrameContentMain
    if main then
        hideNativeRegion(_G.PlayerName or main.PlayerName)
        hideNativeRegion(_G.PlayerLevelText or main.PlayerLevelText)

        local healthContainer = main.HealthBarsContainer
        if healthContainer then
            hideNativeRegion(healthContainer)
        end

        local manaArea = main.ManaBarArea
        if manaArea and manaArea.ManaBar then
            hideNativeRegion(manaArea.ManaBar)
        end
    end

    -- Solo el arte ligado al portrait. Marcador de raid, lider, rol y grupo
    -- siguen visibles; AttackIcon/CornerIcon/RestLoop los gestiona HUDFixes.
    local contextual = content and content.PlayerFrameContentContextual
    if contextual then
        hideNativeRegion(contextual.PrestigePortrait)
        hideNativeRegion(contextual.PrestigeBadge)
        hideNativeRegion(contextual.PVPIcon)
    end
end

local function restorePlayerStaticArt()
    local frame = _G.PlayerFrame
    local container = frame and frame.PlayerFrameContainer
    if container then
        restoreNativeRegion(container.PlayerPortrait)
        restoreNativeRegion(container.PlayerPortraitMask)
        restoreNativeRegion(container.FrameTexture)
        restoreNativeRegion(container.VehicleFrameTexture)
        restoreNativeRegion(container.AlternatePowerFrameTexture)
        restoreNativeRegion(container.FrameFlash)
    end

    local content = frame and frame.PlayerFrameContent
    local main = content and content.PlayerFrameContentMain
    if main then
        restoreNativeRegion(_G.PlayerName or main.PlayerName)
        restoreNativeRegion(_G.PlayerLevelText or main.PlayerLevelText)
        restoreNativeRegion(main.HealthBarsContainer)

        local manaArea = main.ManaBarArea
        if manaArea then
            restoreNativeRegion(manaArea.ManaBar)
        end
    end

    local contextual = content and content.PlayerFrameContentContextual
    if contextual then
        restoreNativeRegion(contextual.PrestigePortrait)
        restoreNativeRegion(contextual.PrestigeBadge)
        restoreNativeRegion(contextual.PVPIcon)
        -- Compatibilidad con versiones que ocultaban el contenedor entero.
        restoreNativeRegion(contextual)
    end
end

local function hideTargetStaticArt(frame)
    if not frame then return end

    local container = frame.TargetFrameContainer
    if container then
        hideNativeRegion(container.Portrait)
        hideNativeRegion(container.PortraitMask)
        hideNativeRegion(container.FrameTexture)
        hideNativeRegion(container.Flash)
        hideNativeRegion(container.BossPortraitFrameTexture)
    end

    local content = frame.TargetFrameContent
    local main = content and content.TargetFrameContentMain
    if main then
        hideNativeRegion(main.ReputationColor)
        hideNativeRegion(main.Name)
        hideNativeRegion(main.LevelText)
        hideNativeRegion(main.HealthBarsContainer)
        hideNativeRegion(main.ManaBar)
    end

    local contextual = content and content.TargetFrameContentContextual
    if contextual then
        -- Keep auras and the raid marker functional/visible.
        hideNativeRegion(contextual.PvpIcon)
        hideNativeRegion(contextual.PrestigePortrait)
        hideNativeRegion(contextual.PrestigeBadge)
        hideNativeRegion(contextual.PetBattleIcon)
        hideNativeRegion(contextual.BossIcon)
        hideNativeRegion(contextual.QuestIcon)
    end
end

local function restoreTargetStaticArt(frame)
    if not frame then return end

    local container = frame.TargetFrameContainer
    if container then
        restoreNativeRegion(container.Portrait)
        restoreNativeRegion(container.PortraitMask)
        restoreNativeRegion(container.FrameTexture)
        restoreNativeRegion(container.Flash)
        restoreNativeRegion(container.BossPortraitFrameTexture)
    end

    local content = frame.TargetFrameContent
    local main = content and content.TargetFrameContentMain
    if main then
        restoreNativeRegion(main.ReputationColor)
        restoreNativeRegion(main.Name)
        restoreNativeRegion(main.LevelText)
        restoreNativeRegion(main.HealthBarsContainer)
        restoreNativeRegion(main.ManaBar)
    end

    local contextual = content and content.TargetFrameContentContextual
    if contextual then
        restoreNativeRegion(contextual.PvpIcon)
        restoreNativeRegion(contextual.PrestigePortrait)
        restoreNativeRegion(contextual.PrestigeBadge)
        restoreNativeRegion(contextual.PetBattleIcon)
        restoreNativeRegion(contextual.BossIcon)
        restoreNativeRegion(contextual.QuestIcon)
    end
end

local function restoreNativeUnitArt()
    restorePlayerStaticArt()
    restoreTargetStaticArt(_G.TargetFrame)
    restoreTargetStaticArt(_G.FocusFrame)
end

local function reapplyNativeArtHiding(frame)
    if not frame then return end

    local cfg = HUD.config or getConfig()
    if not HUD:IsEnabled() or cfg.unitFrames == false then
        return
    end

    if frame == _G.PlayerFrame then
        hidePlayerStaticArt()
        return
    end

    if frame == _G.TargetFrame or frame == _G.FocusFrame then
        hideTargetStaticArt(frame)
    end
end

local function createUnitDisplay(unit, nativeFrame, color)
    if HUD.unitDisplays[unit] then
        return HUD.unitDisplays[unit]
    end
    if not nativeFrame then return nil end

    -- This frame is owned entirely by RapzoBags. It is only anchored to the
    -- Blizzard frame; it never writes fields into protected Blizzard bars.
    local display = CreateFrame("Frame", nil, UIParent)
    display:SetSize(240, 64)

    if unit == "player" then
        display:SetPoint("TOPLEFT", nativeFrame, "TOPLEFT", -2, -18)
    else
        display:SetPoint("TOPRIGHT", nativeFrame, "TOPRIGHT", 2, -18)
    end

    -- BACKGROUND keeps this panel visible over the 3D world while Blizzard's
    -- native LOW-strata auras/click frames remain above it.
    display:SetFrameStrata("BACKGROUND")
    display:SetFrameLevel(50)
    display:EnableMouse(false)

    local panel = display:CreateTexture(nil, "BACKGROUND")
    panel:SetPoint("TOPLEFT", display, "TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", display, "BOTTOMRIGHT", 0, 0)
    panel:SetColorTexture(0.005, 0.009, 0.015, 0.93)
    display.panel = panel

    local accent = display:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", display, "TOPLEFT", 0, 0)
    accent:SetPoint("TOPRIGHT", display, "TOPRIGHT", 0, 0)
    accent:SetHeight(2)
    accent:SetColorTexture(color[1], color[2], color[3], 0.95)

    local displayEdges = createEdges(display, color, 0.30, 1)

    local name = display:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("TOPLEFT", display, "TOPLEFT", 6, -8)
    name:SetPoint("RIGHT", display, "RIGHT", -6, 0)
    name:SetHeight(14)
    name:SetJustifyH("LEFT")
    name:SetTextColor(0.94, 0.96, 1.00)

    local levelText = display:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    levelText:SetPoint("TOPRIGHT", display, "TOPRIGHT", -2, -8)
    levelText:SetJustifyH("RIGHT")
    levelText:SetTextColor(1.00, 0.82, 0.15)
    levelText:SetShadowColor(0, 0, 0, 1)
    levelText:SetShadowOffset(1, -1)

    local health = createBar(display, 24, color)
    health:SetPoint("TOPLEFT", display, "TOPLEFT", 6, -25)
    health:SetPoint("RIGHT", display, "RIGHT", -6, 0)

    local healthPercentText = health:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    healthPercentText:SetPoint("LEFT", health, "LEFT", 7, 0)
    healthPercentText:SetJustifyH("LEFT")
    healthPercentText:SetTextColor(0.98, 0.98, 0.98)
    healthPercentText:SetShadowColor(0, 0, 0, 1)
    healthPercentText:SetShadowOffset(1, -1)

    local healthValueText = health:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    healthValueText:SetPoint("RIGHT", health, "RIGHT", -7, 0)
    healthValueText:SetJustifyH("RIGHT")
    healthValueText:SetTextColor(0.98, 0.98, 0.98)
    healthValueText:SetShadowColor(0, 0, 0, 1)
    healthValueText:SetShadowOffset(1, -1)

    local power = createBar(display, 10, COLORS.power)
    power:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -4)
    power:SetPoint("RIGHT", health, "RIGHT", 0, 0)

    local powerValueText = power:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    powerValueText:SetPoint("RIGHT", power, "RIGHT", -5, 0)
    powerValueText:SetJustifyH("RIGHT")
    powerValueText:SetTextColor(0.92, 0.94, 0.98)
    powerValueText:SetShadowColor(0, 0, 0, 1)
    powerValueText:SetShadowOffset(1, -1)

    local unitTag = display:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    unitTag:SetPoint("TOPRIGHT", display, "TOPRIGHT", -6, -8)
    unitTag:SetText(string.upper(unit))
    unitTag:SetTextColor(color[1], color[2], color[3])

    display.unit = unit
    display.nativeFrame = nativeFrame
    display.health = health
    display.healthPercentText = healthPercentText
    display.healthValueText = healthValueText
    display.power = power
    display.powerValueText = powerValueText
    display.nameText = name
    display.levelText = levelText
    display.unitTag = unitTag
    display.accent = accent
    display.edges = displayEdges
    display.color = color

    HUD.unitDisplays[unit] = display
    return display
end

local function applyDisplayColor(display, color)
    if not display or not color then return end

    display.color = color
    display.health:SetStatusBarColor(color[1], color[2], color[3])

    if display.accent then
        display.accent:SetColorTexture(color[1], color[2], color[3], 0.95)
    end

    if display.unitTag then
        display.unitTag:SetTextColor(color[1], color[2], color[3])
    end

    for _, edge in ipairs(display.edges or {}) do
        edge:SetColorTexture(color[1], color[2], color[3], 0.30)
    end

    -- Style 2 uses neutral/black borders only. The class/reaction color
    -- belongs to the health fill, never to the frame outline. Style 1 pinta
    -- los bordes con el color de la unidad aqui (y no en cada relayout).
    if type(HUD.GetStyle) == "function" and HUD:GetStyle() == 2 then
        for _, edge in ipairs(display.health and display.health.RapzoQoLEdges or {}) do
            edge:SetColorTexture(0.01, 0.01, 0.01, 1)
        end
        for _, edge in ipairs(display.power and display.power.RapzoQoLEdges or {}) do
            edge:SetColorTexture(0.01, 0.01, 0.01, 1)
        end
    else
        for _, edge in ipairs(display.health and display.health.RapzoQoLEdges or {}) do
            edge:SetColorTexture(color[1], color[2], color[3], 0.60)
        end
        for _, edge in ipairs(display.power and display.power.RapzoQoLEdges or {}) do
            edge:SetColorTexture(COLORS.power[1], COLORS.power[2], COLORS.power[3], 0.60)
        end
    end
end

local function formatCompactNumber(value)
    value = tonumber(value)
    if not value then return "" end

    local absValue = math.abs(value)
    if absValue >= 1000000000 then
        return string.format("%.2fB", value / 1000000000)
    elseif absValue >= 1000000 then
        return string.format("%.2fM", value / 1000000)
    elseif absValue >= 1000 then
        return string.format("%.1fK", value / 1000)
    end
    return tostring(math.floor(value + 0.5))
end

local function updateUnitDisplay(display)
    if not display or not display.nativeFrame then return end

    local unit = display.unit

    -- Rapzo QoL owns the custom unit-frame visibility. Do not mirror
    -- Blizzard/mUI's native TargetFrame/FocusFrame visibility because another
    -- UI addon may intentionally hide those frames while the unit still exists.
    -- Player is always present; target/focus are driven by UnitExists instead.
    if unit ~= "player" then
        local exists = type(UnitExists) == "function" and UnitExists(unit)
        if not exists then
            display:Hide()
            return
        end
    end

    display:Show()

    local fallback = COLORS[unit] or COLORS.target
    local color
    if unit == "player" then
        color = getUnitClassColor(unit, fallback, false)
    else
        color = getUnitClassColor(unit, fallback, true)
    end
    applyDisplayColor(display, color)

    local name = UnitName and UnitName(unit)
    setSecretSafeText(display.nameText, name)

    if display.levelText and type(UnitLevel) == "function" then
        local okLevel, level = pcall(UnitLevel, unit)
        if okLevel and not isSecret(level) then
            level = tonumber(level)
            if level then
                display.levelText:SetText(level < 0 and "??" or tostring(math.floor(level)))
            else
                display.levelText:SetText("")
            end
        else
            display.levelText:SetText("")
        end
    end

    -- Midnight secret-safe path: do not inspect, compare, stringify, divide or
    -- branch on health/power values. StatusBar consumes them directly C-side.
    if UnitHealthMax and UnitHealth then
        local maxHealth = UnitHealthMax(unit)
        local health = UnitHealth(unit)
        display.health:SetMinMaxValues(0, maxHealth)
        display.health:SetValue(health)

        if not isSecret(health) and not isSecret(maxHealth) then
            local h = tonumber(health)
            local hm = tonumber(maxHealth)
            if h and hm and hm > 0 then
                if display.healthPercentText then
                    display.healthPercentText:SetText(string.format("%d%%", math.floor((h / hm) * 100 + 0.5)))
                end
                if display.healthValueText then
                    display.healthValueText:SetText(formatCompactNumber(h))
                end
            end
        else
            if display.healthPercentText then display.healthPercentText:SetText("") end
            if display.healthValueText then display.healthValueText:SetText("") end
        end
    end

    if UnitPowerMax and UnitPower then
        local maxPower = UnitPowerMax(unit)
        local power = UnitPower(unit)
        display.power:SetMinMaxValues(0, maxPower)
        display.power:SetValue(power)

        if display.powerValueText then
            if not isSecret(power) then
                local numericPower = tonumber(power)
                display.powerValueText:SetText(numericPower and tostring(math.floor(numericPower + 0.5)) or "")
            else
                display.powerValueText:SetText("")
            end
        end
    end
end

function HUD:CreateUnitDisplays()
    local cfg = getConfig()
    if not self:IsEnabled() or not cfg.unitFrames then return end
    -- Crear frames propios y cambiar alpha de regiones nativas esta permitido en
    -- combate; sin guard, `/rapzo hud frames on` en combate no deja arte nativo visible.

    if _G.PlayerFrame then
        hidePlayerStaticArt()
        createUnitDisplay("player", _G.PlayerFrame, getUnitClassColor("player", COLORS.player, false))
    end

    if _G.TargetFrame then
        hideTargetStaticArt(_G.TargetFrame)
        createUnitDisplay("target", _G.TargetFrame, getUnitClassColor("target", COLORS.target, true))
    end

    if _G.FocusFrame then
        hideTargetStaticArt(_G.FocusFrame)
        createUnitDisplay("focus", _G.FocusFrame, getUnitClassColor("focus", COLORS.focus, true))
    end
end

function HUD:UpdateUnitFrames(unit)
    local cfg = self.config or getConfig()
    if not self:IsEnabled() or not cfg.unitFrames then return end

    if unit then
        local display = self.unitDisplays[unit]
        if display then updateUnitDisplay(display) end
        return
    end

    updateUnitDisplay(self.unitDisplays.player)
    updateUnitDisplay(self.unitDisplays.target)
    updateUnitDisplay(self.unitDisplays.focus)
end

function HUD:StyleUnitFrames()
    local cfg = getConfig()
    if not self:IsEnabled() or not cfg.unitFrames then return end

    if type(InCombatLockdown) ~= "function" or not InCombatLockdown() then
        self:CreateUnitDisplays()
    end
    self:UpdateUnitFrames()
end

function HUD:CreateCursorRing()
    if self.cursorFrame then return self.cursorFrame end

    local frame = CreateFrame("Frame", "RapzoQoLCursorRing", UIParent)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(10000)
    frame:EnableMouse(false)

    local shadow = frame:CreateTexture(nil, "OVERLAY")
    shadow:SetPoint("CENTER", frame, "CENTER", 0, 0)
    shadow:SetSize(1, 1)

    local shadowAtlasOK = false
    if type(shadow.SetAtlas) == "function" then
        shadowAtlasOK = pcall(shadow.SetAtlas, shadow, CURSOR_ATLAS, false)
    end
    if not shadowAtlasOK then
        shadow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    end
    shadow:SetBlendMode("BLEND")
    shadow:SetVertexColor(0.00, 0.00, 0.00, 0.92)
    frame.shadow = shadow

    local outer = frame:CreateTexture(nil, "OVERLAY")
    outer:SetPoint("CENTER", frame, "CENTER", 0, 0)
    outer:SetSize(1, 1)

    local atlasOK = false
    if type(outer.SetAtlas) == "function" then
        atlasOK = pcall(outer.SetAtlas, outer, CURSOR_ATLAS, false)
    end
    if not atlasOK then
        outer:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    end

    outer:SetBlendMode("ADD")
    local accent = getAccentColor()
    outer:SetVertexColor(accent[1], accent[2], accent[3], 1.00)
    frame.outer = outer

    local core = frame:CreateTexture(nil, "OVERLAY")
    core:SetTexture(WHITE_TEXTURE)
    core:SetSize(5, 5)
    core:SetPoint("CENTER", frame, "CENTER", 0, 0)
    core:SetVertexColor(1.00, 1.00, 1.00, 0.95)
    frame.core = core

    local coreShadow = frame:CreateTexture(nil, "ARTWORK")
    coreShadow:SetTexture(WHITE_TEXTURE)
    coreShadow:SetSize(9, 9)
    coreShadow:SetPoint("CENTER", core, "CENTER", 0, 0)
    coreShadow:SetVertexColor(0.00, 0.00, 0.00, 0.85)
    frame.coreShadow = coreShadow

    frame:SetScript("OnUpdate", function(self)
        local cfg = HUD.config or getConfig()
        if not cfg.cursor then
            self:Hide()
            return
        end

        local scale = UIParent:GetEffectiveScale()
        local x, y = GetCursorPosition()
        if not x or not y or not scale or scale == 0 then return end

        -- El tamano solo cambia con /rapzo hud cursorsize: no hay que hacer
        -- tres SetSize por frame.
        local size = tonumber(cfg.cursorSize) or 52
        if self.appliedSize ~= size then
            self.appliedSize = size
            self:SetSize(size, size)
            if self.shadow then self.shadow:SetSize(size + 16, size + 16) end
            if self.outer then self.outer:SetSize(size, size) end
        end

        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
        if not self:IsShown() then self:Show() end
    end)

    self.cursorFrame = frame
    return frame
end

-- Forma del minimapa para los botones de addons. LibDBIcon (y otros addons)
-- llaman a la global GetMinimapShape() al colocar cada boton; sin ella asumen
-- ROUND y los botones orbitan un circulo aunque el minimapa sea cuadrado.
-- Se define solo mientras el minimapa cuadrado esta activo y se devuelve la
-- funcion anterior (de otro addon o nil) al apagarlo.
local function squareMinimapShape()
    return "SQUARE"
end
local previousMinimapShape
local minimapShapeOwned = false

local function getLibDBIcon()
    if type(_G.LibStub) ~= "function" then return nil end
    local ok, lib = pcall(_G.LibStub, "LibDBIcon-1.0", true)
    if ok and type(lib) == "table" then return lib end
    return nil
end

-- SetButtonRadius recoloca todos los botones registrados con la forma actual.
local function refreshMinimapButtons()
    local lib = getLibDBIcon()
    if not lib or type(lib.SetButtonRadius) ~= "function" then return end
    local radius = tonumber(lib.radius) or 5
    safeCall(lib.SetButtonRadius, lib, radius)
end

local function applyMinimapShape(square)
    if square then
        if _G.GetMinimapShape ~= squareMinimapShape then
            previousMinimapShape = _G.GetMinimapShape
            _G.GetMinimapShape = squareMinimapShape
            minimapShapeOwned = true
        end
    elseif minimapShapeOwned then
        if _G.GetMinimapShape == squareMinimapShape then
            _G.GetMinimapShape = previousMinimapShape
        end
        minimapShapeOwned = false
        previousMinimapShape = nil
    else
        return
    end
    refreshMinimapButtons()
end

function HUD:RefreshMinimapButtons()
    refreshMinimapButtons()
end

function HUD:StyleMinimap()
    local cfg = getConfig()
    if not _G.Minimap then return end
    if not cfg.squareMinimap then
        self:RestoreMinimapArt()
        return
    end

    safeCall(_G.Minimap.SetMaskTexture, _G.Minimap, WHITE_TEXTURE)
    applyMinimapShape(true)

    -- Rapzo QoL keeps the minimap square but completely borderless. The
    -- original alphas are snapshotted so the toggle restores the native art
    -- without a /reload (only the square mask itself needs one).
    hideNativeRegion(_G.MinimapCompassTexture)
    if _G.MinimapBackdrop then
        hideNativeRegion(_G.MinimapBackdrop.StaticOverlayTexture)
    end
    hideNativeRegion(_G.MinimapBorder)
    hideNativeRegion(_G.MinimapBorderTop)
    hideNativeRegion(_G.MiniMapTrackingBorder)
end

function HUD:RestoreMinimapArt()
    applyMinimapShape(false)
    restoreNativeRegion(_G.MinimapCompassTexture)
    if _G.MinimapBackdrop then
        restoreNativeRegion(_G.MinimapBackdrop.StaticOverlayTexture)
    end
    restoreNativeRegion(_G.MinimapBorder)
    restoreNativeRegion(_G.MinimapBorderTop)
    restoreNativeRegion(_G.MiniMapTrackingBorder)
end

function HUD:ApplyTheme()
    local accent = getAccentColor()

    if self.cursorFrame and self.cursorFrame.outer then
        self.cursorFrame.outer:SetVertexColor(accent[1], accent[2], accent[3], 1.00)
    end
end

function HUD:Apply()
    local cfg = getConfig()

    -- Every visual component is independent. Applying one must never gate the
    -- other two.
    if cfg.cursor then
        local cursor = self:CreateCursorRing()
        if cursor and not cursor:IsShown() then cursor:Show() end
    elseif self.cursorFrame then
        self.cursorFrame:Hide()
    end

    if cfg.squareMinimap then
        self:StyleMinimap()
    else
        self:RestoreMinimapArt()
    end

    if cfg.unitFrames then
        self:StyleUnitFrames()
    else
        for _, display in pairs(self.unitDisplays) do
            display:Hide()
        end
        restoreNativeUnitArt()
    end

    self:ApplyTheme()
end

function HUD:SetEnabled(enabled)
    -- Legacy API: "HUD on/off" now controls Rapzo unit frames only.
    return self:SetPart("frames", enabled)
end

function HUD:SetPart(part, enabled)
    local cfg = getConfig()

    if part == "cursor" then
        cfg.cursor = enabled and true or false
        if not cfg.cursor and self.cursorFrame then self.cursorFrame:Hide() end
        RB:Print("Aro del mouse: " .. (cfg.cursor and "ON" or "OFF"))
    elseif part == "minimap" then
        cfg.squareMinimap = enabled and true or false
        if not cfg.squareMinimap then
            self:RestoreMinimapArt()
            RB:Print("Minimapa Rapzo: OFF. Bordes y brujula restaurados; la mascara cuadrada necesita /reload.")
        else
            RB:Print("Minimapa Rapzo: ON")
        end
    elseif part == "frames" then
        cfg.unitFrames = enabled and true or false
        if not cfg.unitFrames then
            for _, display in pairs(self.unitDisplays) do display:Hide() end
            restoreNativeUnitArt()
            RB:Print("Unit frames Rapzo OFF; Player/Target/Focus nativos restaurados.")
        else
            RB:Print("Unit frames Rapzo: ON")
        end
    else
        return false
    end

    -- Apply on both ON and OFF so the other independent components keep their
    -- requested state and frame restoration happens immediately.
    self:Apply()
    return true
end

function HUD:HandleSlash(rest)
    rest = tostring(rest or "")
    -- Tolerate leading/trailing whitespace and extra tokens.
    local part = rest:match("^%s*(%S+)") or "status"
    local value = rest:match("^%s*%S+%s+(%S+)") or ""
    part = string.lower(part)
    value = string.lower(value)

    if part == "on" then
        self:SetEnabled(true)
        return
    elseif part == "off" then
        self:SetEnabled(false)
        return
    elseif part == "debug" then
        local cfg = getConfig()
        local loaded = true
        if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
            local okLoaded, value = pcall(C_AddOns.IsAddOnLoaded, "RapzoQoL")
            if okLoaded then loaded = value and true or false end
        end

        RB:Print(string.format(
            "HUD DEBUG | addon:%s frames:%s cursor:%s minimap:%s displays:%s",
            loaded and "LOADED" or "NO",
            cfg.unitFrames and "ON" or "OFF",
            cfg.cursor and "ON" or "OFF",
            cfg.squareMinimap and "ON" or "OFF",
            (self.unitDisplays.player or self.unitDisplays.target or self.unitDisplays.focus) and "CREADOS" or "NO"
        ))
        return
    elseif part == "status" or part == "" then
        local cfg = getConfig()
        RB:Print(string.format(
            "Rapzo visual | frames:%s | minimapa:%s | cursor:%s",
            cfg.unitFrames and "ON" or "OFF",
            cfg.squareMinimap and "ON" or "OFF",
            cfg.cursor and "ON" or "OFF"
        ))
        return
    end

    if part == "cursorsize" or (part == "cursor" and value:match("^%d+$")) then
        local cfg = getConfig()
        local requested = tonumber(value)
        if not requested then
            RB:Print("Uso: /rapzo hud cursorsize 36-96")
            return
        end
        cfg.cursorSize = math.max(36, math.min(96, requested))
        self:Apply()
        RB:Print("Cursor HUD: " .. tostring(cfg.cursorSize) .. " px")
        return
    end

    if part == "cursor" or part == "minimap" or part == "frames" then
        if value ~= "on" and value ~= "off" then
            RB:Print("Uso: /rapzo hud " .. part .. " on|off")
            return
        end

        self:SetPart(part, value == "on")
        return
    end

    RB:Print("Uso: /rapzo hud [status|debug|frames on|off|minimap on|off|cursor on|off|cursorsize 36-96]")
end

function HUD:ScheduleApply(delay)
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay or 0, function()
            HUD:Apply()
        end)
    else
        self:Apply()
    end
end

function HUD:Initialize()
    if self.initialized then return end
    self.initialized = true

    getConfig()
    self:CreateCursorRing()

    local events = CreateFrame("Frame")
    self.eventFrame = events

    local function register(event)
        pcall(events.RegisterEvent, events, event)
    end

    local function registerUnit(event)
        if type(RB.RegisterUnitEventSafe) == "function" then
            RB:RegisterUnitEventSafe(events, event, "player", "target", "focus")
        else
            register(event)
        end
    end

    register("ADDON_LOADED")
    register("PLAYER_LOGIN")
    register("PLAYER_ENTERING_WORLD")
    register("PLAYER_REGEN_ENABLED")
    register("PLAYER_TARGET_CHANGED")
    register("PLAYER_FOCUS_CHANGED")
    registerUnit("UNIT_HEALTH")
    registerUnit("UNIT_MAXHEALTH")
    registerUnit("UNIT_POWER_UPDATE")
    registerUnit("UNIT_MAXPOWER")
    registerUnit("UNIT_DISPLAYPOWER")
    registerUnit("UNIT_NAME_UPDATE")

    events:SetScript("OnEvent", function(_, event, unit)
        if event == "ADDON_LOADED" then
            -- This file runs before the SavedVariables load, so the initial
            -- getConfig() worked on a placeholder table. Re-read the real one.
            if unit == RB.coreAddonName then
                getConfig()
            end
            return
        end

        if event == "PLAYER_REGEN_ENABLED" then
            reapplyNativeArtHiding(_G.PlayerFrame)
            reapplyNativeArtHiding(_G.TargetFrame)
            reapplyNativeArtHiding(_G.FocusFrame)
            HUD:StyleUnitFrames()
            return
        end

        if event == "PLAYER_TARGET_CHANGED" then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    reapplyNativeArtHiding(_G.TargetFrame)
                    HUD:UpdateUnitFrames("target")
                end)
            else
                reapplyNativeArtHiding(_G.TargetFrame)
                HUD:UpdateUnitFrames("target")
            end
            return
        elseif event == "PLAYER_FOCUS_CHANGED" then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    reapplyNativeArtHiding(_G.FocusFrame)
                    HUD:UpdateUnitFrames("focus")
                end)
            else
                reapplyNativeArtHiding(_G.FocusFrame)
                HUD:UpdateUnitFrames("focus")
            end
            return
        elseif event == "UNIT_HEALTH"
            or event == "UNIT_MAXHEALTH"
            or event == "UNIT_POWER_UPDATE"
            or event == "UNIT_MAXPOWER"
            or event == "UNIT_DISPLAYPOWER"
            or event == "UNIT_NAME_UPDATE"
        then
            if unit == "player" or unit == "target" or unit == "focus" then
                HUD:UpdateUnitFrames(unit)
            end
            return
        end

        HUD:ScheduleApply(event == "PLAYER_ENTERING_WORLD" and 0.5 or 0.05)
        if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
            HUD:ScheduleApply(2.0)
            -- Los addons que registran botones despues de nosotros ya ven la
            -- forma cuadrada; los que lo hicieron antes se recolocan aqui.
            if C_Timer and C_Timer.After then
                C_Timer.After(3.0, function()
                    local current = HUD.config or getConfig()
                    if current.squareMinimap then refreshMinimapButtons() end
                end)
            end
        end
    end)

    if type(hooksecurefunc) == "function" and type(TargetFrameMixin) == "table" and type(TargetFrameMixin.Update) == "function" then
        hooksecurefunc(TargetFrameMixin, "Update", function(frame)
            if frame == _G.TargetFrame or frame == _G.FocusFrame then
                reapplyNativeArtHiding(frame)
            end
        end)
    end

    self:ScheduleApply(0.5)
end

RB:RegisterCommand("hud", function(rest) HUD:HandleSlash(rest) end, "/rapzo hud - cursor, minimapa y unit frames")

local initOK, initError = pcall(function()
    HUD:Initialize()
end)

if not initOK then
    RB:Print("HUD no pudo inicializar: " .. tostring(initError))
end
