local addonName = ...
local RB = _G.RapzoQoL or _G.RapzoBags
if not RB or not RB.HUD then return end

local HUD = RB.HUD
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local STYLE_CURRENT = 1
local STYLE_ICON = 2
local STYLE2_WIDTH = 150
local STYLE2_HEIGHT = 43
local STYLE2_DEFAULT_SCALE = 1.50
local STYLE2_MIN_SCALE = 0.50
local STYLE2_MAX_SCALE = 2.50
local STYLE2_EDGE = 0
local STYLE2_CONTENT = 0
local STYLE2_AURA = 16
local STYLE2_AURA_WIDTH = STYLE2_WIDTH
local STYLE2_AURA_Y = 18
local STYLE2_DEFAULT_AURA_SCALE = 1.00
local STYLE2_MIN_AURA_SCALE = 0.75
local STYLE2_MAX_AURA_SCALE = 1.75
local STYLE2_MIN_AURA_X = -150
local STYLE2_MAX_AURA_X = 150
local STYLE2_MIN_AURA_Y = -60
local STYLE2_MAX_AURA_Y = 100

local function isSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

local function safeCall(func, ...)
    if type(func) ~= "function" then return false end
    return pcall(func, ...)
end

-- When the Rapzo unit frames are toggled off, the style/castbar pipeline must
-- stay inert: no restyling per unit event and no cast bar creation.
local function hudFramesActive()
    local cfg = HUD.config
    if cfg and cfg.unitFrames == false then
        return false
    end
    if type(HUD.IsEnabled) == "function" and not HUD:IsEnabled() then
        return false
    end
    return true
end

local function getConfig()
    local db = RB:EnsureDB()
    db.settings.hud = type(db.settings.hud) == "table" and db.settings.hud or {}
    local cfg = db.settings.hud
    local style = tonumber(cfg.style)
    if style ~= STYLE_CURRENT and style ~= STYLE_ICON then
        style = STYLE_CURRENT
    end
    cfg.style = style

    local frameScale = tonumber(cfg.frameScale)
    if not frameScale then frameScale = STYLE2_DEFAULT_SCALE end
    frameScale = math.max(STYLE2_MIN_SCALE, math.min(STYLE2_MAX_SCALE, frameScale))
    cfg.frameScale = frameScale

    local auraScale = tonumber(cfg.auraScale)
    if not auraScale then auraScale = STYLE2_DEFAULT_AURA_SCALE end
    auraScale = math.max(STYLE2_MIN_AURA_SCALE, math.min(STYLE2_MAX_AURA_SCALE, auraScale))
    cfg.auraScale = auraScale

    cfg.auraOffsetX = math.max(STYLE2_MIN_AURA_X, math.min(STYLE2_MAX_AURA_X, tonumber(cfg.auraOffsetX) or 0))
    cfg.auraOffsetY = math.max(STYLE2_MIN_AURA_Y, math.min(STYLE2_MAX_AURA_Y, tonumber(cfg.auraOffsetY) or 0))

    HUD.config = cfg
    return cfg
end

-- Lecturas baratas: HUD.config ya esta validado tras el primer getConfig();
-- estas funciones se llaman muchas veces por relayout y no deben pasar por
-- EnsureDB cada vez.
function HUD:GetStyle()
    local cfg = HUD.config
    if cfg and cfg.style then return cfg.style end
    return getConfig().style
end

function HUD:GetFrameScale()
    local cfg = HUD.config
    if cfg and cfg.frameScale then return cfg.frameScale end
    return getConfig().frameScale
end

function HUD:GetAuraScale()
    local cfg = HUD.config
    if cfg and cfg.auraScale then return cfg.auraScale end
    return getConfig().auraScale
end

function HUD:GetAuraOffset()
    local cfg = HUD.config
    if not (cfg and cfg.auraOffsetX and cfg.auraOffsetY) then cfg = getConfig() end
    return cfg.auraOffsetX, cfg.auraOffsetY
end

function HUD:SetAuraOffset(x, y, silent)
    x, y = tonumber(x), tonumber(y)
    if not x or not y then return false end

    x = math.max(STYLE2_MIN_AURA_X, math.min(STYLE2_MAX_AURA_X, x))
    y = math.max(STYLE2_MIN_AURA_Y, math.min(STYLE2_MAX_AURA_Y, y))
    local cfg = getConfig()
    cfg.auraOffsetX, cfg.auraOffsetY = x, y

    for _, display in pairs(self.unitDisplays or {}) do
        for _, container in pairs({display and display.RapzoQoLPlayerAuras, display and display.RapzoQoLTargetAuras}) do
            if container then
                safeCall(container.ClearAllPoints, container)
                safeCall(container.SetPoint, container, "BOTTOMLEFT", display, "TOPLEFT", x, STYLE2_AURA_Y + y)
            end
        end
    end

    if type(self.RefreshPreview) == "function" then self:RefreshPreview() end
    if not silent then RB:Print(string.format("HUD auras: X %d | Y %d", x, y)) end
    return true
end

function HUD:SetAuraScale(scale, silent)
    scale = tonumber(scale)
    if not scale then return false end

    scale = math.max(STYLE2_MIN_AURA_SCALE, math.min(STYLE2_MAX_AURA_SCALE, scale))
    getConfig().auraScale = scale

    for _, display in pairs(self.unitDisplays or {}) do
        local playerAuras = display and display.RapzoQoLPlayerAuras
        local targetAuras = display and display.RapzoQoLTargetAuras
        if playerAuras then safeCall(playerAuras.SetScale, playerAuras, scale) end
        if targetAuras then safeCall(targetAuras.SetScale, targetAuras, scale) end
    end

    if type(self.RefreshPreview) == "function" then
        self:RefreshPreview()
    end

    if not silent then
        RB:Print(string.format("HUD auras: %.2fx | base aprox. %d px", scale, math.floor(STYLE2_AURA * scale + 0.5)))
    end
    return true
end

function HUD:SetFrameScale(scale, silent)
    scale = tonumber(scale)
    if not scale then return false end

    scale = math.max(STYLE2_MIN_SCALE, math.min(STYLE2_MAX_SCALE, scale))
    local cfg = getConfig()
    cfg.frameScale = scale

    self:ApplyFrameStyle()

    if type(self.RefreshPreview) == "function" then
        self:RefreshPreview()
    end

    if not silent then
        local visualW = math.floor(STYLE2_WIDTH * scale + 0.5)
        local visualH = math.floor(STYLE2_HEIGHT * scale + 0.5)
        RB:Print(string.format("HUD scale: %.2fx | aprox. %dx%d px", scale, visualW, visualH))
    end
    return true
end

function HUD:GetStyleAuraOffset(unit)
    if self:GetStyle() ~= STYLE_ICON then return 0 end
    if unit == "target" or unit == "focus" then
        return 0
    end
    return STYLE2_CONTENT
end

function HUD:GetStyleAuraRightInset(unit)
    if self:GetStyle() ~= STYLE_ICON then return 0 end
    if unit == "target" or unit == "focus" then
        return STYLE2_CONTENT
    end
    return 6
end

local function createSimpleEdges(parent, color)
    if parent.RapzoQoLEdges then return parent.RapzoQoLEdges end
    color = color or {0.95, 0.70, 0.16}
    local edges = {}
    for i = 1, 4 do
        local tex = parent:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(color[1], color[2], color[3], 0.78)
        edges[i] = tex
    end
    edges[1]:SetPoint("TOPLEFT", parent, "TOPLEFT", -1, 1)
    edges[1]:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 1, 1)
    edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -1, -1)
    edges[2]:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 1, -1)
    edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT", parent, "TOPLEFT", -1, 1)
    edges[3]:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -1, -1)
    edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 1, 1)
    edges[4]:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 1, -1)
    edges[4]:SetWidth(1)
    parent.RapzoQoLEdges = edges
    return edges
end

local function ensureCastBar(display)
    if display.RapzoQoLCastBar then return display.RapzoQoLCastBar end

    local bar = CreateFrame("StatusBar", nil, display)
    bar:SetStatusBarTexture(WHITE_TEXTURE)
    bar:SetStatusBarColor(0.92, 0.63, 0.12)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar:SetHeight(14)
    bar:SetPoint("TOPLEFT", display, "BOTTOMLEFT", STYLE2_CONTENT, -4)
    bar:SetPoint("RIGHT", display, "RIGHT", -6, 0)
    bar:SetFrameLevel(display:GetFrameLevel() + 3)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetColorTexture(0.01, 0.02, 0.03, 0.97)

    local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", bar, "LEFT", 4, 0)
    text:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    text:SetJustifyH("CENTER")
    text:SetText("")

    bar.RapzoQoLEdges = createSimpleEdges(bar, display.color)
    bar.RapzoQoLBackground = bg

    bar.RapzoQoLText = text
    display.RapzoQoLCastBar = bar
    bar:Hide()
    return bar
end

local function setCastText(fontString, value)
    if not fontString then return end
    if isSecret(value) then
        fontString:SetText(value)
    else
        fontString:SetText(value or "")
    end
end

local function updateCastBar(unit)
    local display = HUD.unitDisplays and HUD.unitDisplays[unit]
    if not display then return end

    if not hudFramesActive() then
        if display.RapzoQoLCastBar then display.RapzoQoLCastBar:Hide() end
        return
    end

    local bar = ensureCastBar(display)
    if HUD:GetStyle() ~= STYLE_ICON then
        bar:Hide()
        return
    end

    -- En contenido restringido el nombre del cast puede ser secreto: se decide
    -- "hay cast" sin compararlo (un secreto cuenta como cast presente) y el
    -- texto se entrega tal cual a SetText, que si acepta secretos.
    local name
    local casting = false
    local isChannel = false

    if type(UnitCastingInfo) == "function" then
        local ok, value = pcall(UnitCastingInfo, unit)
        if ok and (isSecret(value) or value ~= nil) then
            name, casting = value, true
        end
    end

    if not casting and type(UnitChannelInfo) == "function" then
        local ok, value = pcall(UnitChannelInfo, unit)
        if ok and (isSecret(value) or value ~= nil) then
            name, casting, isChannel = value, true, true
        end
    end

    if not casting then
        bar:Hide()
        return
    end

    setCastText(bar.RapzoQoLText, name)
    if display.color then
        bar:SetStatusBarColor(display.color[1] or 0.92, display.color[2] or 0.63, display.color[3] or 0.12)
        for _, edge in ipairs(bar.RapzoQoLEdges or {}) do
            edge:SetColorTexture(0.015, 0.018, 0.024, 0.98)
        end
    end

    local duration
    if isChannel and type(UnitChannelDuration) == "function" then
        local ok, value = pcall(UnitChannelDuration, unit)
        if ok then duration = value end
    elseif type(UnitCastingDuration) == "function" then
        local ok, value = pcall(UnitCastingDuration, unit)
        if ok then duration = value end
    end

    -- SetTimerDuration consume duraciones secretas directamente.
    if (isSecret(duration) or duration ~= nil) and type(bar.SetTimerDuration) == "function" then
        if isChannel and Enum and Enum.StatusBarFillDirection and Enum.StatusBarFillDirection.Reverse then
            safeCall(bar.SetTimerDuration, bar, duration, Enum.StatusBarFillDirection.Reverse)
        else
            safeCall(bar.SetTimerDuration, bar, duration)
        end
    else
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
    end

    if type(HUD.ApplyClassResourceCastAnchor) == "function" then
        HUD:ApplyClassResourceCastAnchor(unit, bar)
    end

    bar:Show()
end

local function initAuraButton(button)
    button:SetSize(STYLE2_AURA, STYLE2_AURA)

    -- AuraContainer does not expose a prebuilt Count region. Register our own
    -- compact application counter so Blizzard does not create/use its large
    -- default presentation on these 16 px buttons.
    local count = button:CreateFontString(nil, "OVERLAY")
    if STANDARD_TEXT_FONT then
        count:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE")
    else
        count:SetFontObject("NumberFontNormalSmall")
        count:SetScale(0.65)
    end
    count:SetJustifyH("RIGHT")
    count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
    count:SetTextColor(1, 1, 1, 1)
    safeCall(button.SetApplicationCount, button, count, {})

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    safeCall(button.SetIcon, button, icon)

    if type(button.CreateMaskTexture) == "function" and type(icon.AddMaskTexture) == "function" then
        local mask = button:CreateMaskTexture()
        mask:SetAllPoints(icon)
        mask:SetTexture(PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        icon:AddMaskTexture(mask)
        button.RapzoQoLAuraMask = mask
    end

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(button)
    safeCall(cooldown.SetDrawEdge, cooldown, false)
    safeCall(cooldown.SetDrawBling, cooldown, false)
    if type(cooldown.SetCountdownFont) == "function" and type(CreateFont) == "function" then
        local fontName = "RapzoQoLAuraCooldownFont"
        local font = _G[fontName] or CreateFont(fontName)
        if font and STANDARD_TEXT_FONT then
            safeCall(font.SetFont, font, STANDARD_TEXT_FONT, 7, "OUTLINE")
            safeCall(cooldown.SetCountdownFont, cooldown, fontName)
        end
    end
    if type(cooldown.SetCountdownAbbrevThreshold) == "function" then
        safeCall(cooldown.SetCountdownAbbrevThreshold, cooldown, 60)
    end
    if type(cooldown.SetHideCountdownNumbers) == "function" then
        safeCall(cooldown.SetHideCountdownNumbers, cooldown, false)
    end
    if type(button.SetDurationCooldown) == "function" then
        safeCall(button.SetDurationCooldown, button, cooldown)
    end

    local ring = button:CreateTexture(nil, "BACKGROUND")
    ring:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
    ring:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
    ring:SetColorTexture(0.95, 0.70, 0.16, 0.26)
    if button.RapzoQoLAuraMask and type(ring.AddMaskTexture) == "function" then
        ring:AddMaskTexture(button.RapzoQoLAuraMask)
    end
    button.RapzoQoLAuraGlow = ring
end

local function ensurePlayerAuraContainer(display)
    if display.RapzoQoLPlayerAuras then return display.RapzoQoLPlayerAuras end
    if display.unit ~= "player" then return nil end

    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return nil
    end

    local ok, container = pcall(CreateFrame, "AuraContainer", nil, display, "CustomAuraContainerTemplate")
    if not ok or not container or type(container.AddAuraGroup) ~= "function" then
        return nil
    end

    container:SetSize(STYLE2_AURA_WIDTH, 22)
    local auraX, auraY = HUD:GetAuraOffset()
    container:SetPoint("BOTTOMLEFT", display, "TOPLEFT", STYLE2_CONTENT + auraX, STYLE2_AURA_Y + auraY)
    container:SetFrameLevel(display:GetFrameLevel() + 4)
    safeCall(container.SetScale, container, HUD:GetAuraScale())
    container:Show()

    local added = safeCall(container.AddAuraGroup, container, "rapzoPlayerHelpful", "HELPFUL", {
        maxFrameCount = 5,
        -- Let Blizzard's secret-safe AuraContainer engine discard long-lived
        -- utility buffs (flask, food, city buffs, etc.). The HUD strip is for
        -- short combat information only; the native BuffFrame remains complete.
        candidateFilters = {
            maxDuration = 120,
        },
        initializeFrame = initAuraButton,
        layout = {
            elementWidth = STYLE2_AURA,
            elementHeight = STYLE2_AURA,
            elementSpacing = 5,
            lineSpacing = 5,
        },
    })

    if not added then
        container:Hide()
        return nil
    end

    safeCall(container.SetUnit, container, "player")
    if type(container.SetEnabled) == "function" then
        safeCall(container.SetEnabled, container, true)
    end
    if type(container.UpdateAllAuras) == "function" then
        safeCall(container.UpdateAllAuras, container)
    end

    display.RapzoQoLPlayerAuras = container
    return container
end

local function ensureTargetAuraContainer(display)
    if not display or (display.unit ~= "target" and display.unit ~= "focus") then return nil end
    if display.RapzoQoLTargetAuras then return display.RapzoQoLTargetAuras end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then return nil end

    local ok, container = pcall(CreateFrame, "AuraContainer", nil, display, "CustomAuraContainerTemplate")
    if not ok or not container or type(container.AddAuraGroup) ~= "function" then return nil end

    container:SetSize(STYLE2_AURA_WIDTH, 22)
    local auraX, auraY = HUD:GetAuraOffset()
    container:SetPoint("BOTTOMLEFT", display, "TOPLEFT", STYLE2_EDGE + auraX, STYLE2_AURA_Y + auraY)
    container:SetFrameLevel(display:GetFrameLevel() + 4)
    safeCall(container.SetScale, container, HUD:GetAuraScale())

    local added = safeCall(container.AddAuraGroup, container, "rapzoTargetHarmfulPlayer", "HARMFUL|PLAYER", {
        maxFrameCount = 5,
        candidateFilters = {},
        initializeFrame = initAuraButton,
        layout = {
            elementWidth = STYLE2_AURA,
            elementHeight = STYLE2_AURA,
            elementSpacing = 5,
            lineSpacing = 5,
        },
    })

    if not added then
        container:Hide()
        return nil
    end

    safeCall(container.SetUnit, container, display.unit)
    if type(container.SetEnabled) == "function" then
        safeCall(container.SetEnabled, container, true)
    end
    if type(container.UpdateAllAuras) == "function" then
        safeCall(container.UpdateAllAuras, container)
    end

    display.RapzoQoLTargetAuras = container
    return container
end

local function setTargetAurasEnabled(display, enabled)
    if not display or (display.unit ~= "target" and display.unit ~= "focus") then return end

    local container = display.RapzoQoLTargetAuras
    if enabled and not container then
        container = ensureTargetAuraContainer(display)
    end
    if not container then return end

    if type(container.SetEnabled) == "function" then
        safeCall(container.SetEnabled, container, enabled)
    end

    if enabled then
        container:Show()
        if type(container.SetUnit) == "function" then
            safeCall(container.SetUnit, container, display.unit)
        end
        if type(container.UpdateAllAuras) == "function" then
            safeCall(container.UpdateAllAuras, container)
        end
    else
        container:Hide()
    end
end

local function setPlayerAurasEnabled(display, enabled)
    if not display or display.unit ~= "player" then return end

    local container = display.RapzoQoLPlayerAuras
    if enabled and not container then
        container = ensurePlayerAuraContainer(display)
    end
    if not container then return end

    if type(container.SetEnabled) == "function" then
        safeCall(container.SetEnabled, container, enabled)
    end

    if enabled then
        container:Show()
        if type(container.UpdateAllAuras) == "function" then
            safeCall(container.UpdateAllAuras, container)
        end
    else
        container:Hide()
    end
end

local function setShellVisible(display, visible)
    if not display then return end

    if display.panel then
        display.panel:SetAlpha(visible and 1 or 0)
    end

    if display.accent then
        display.accent:SetAlpha(visible and 1 or 0)
    end

    for _, edge in ipairs(display.edges or {}) do
        edge:SetAlpha(visible and 1 or 0)
    end
end

local function setEdgesColor(edges, r, g, b, a)
    for _, edge in ipairs(edges or {}) do
        edge:SetColorTexture(r, g, b, a)
    end
end

local function ensureToxiDecor(display)
    if not display or not display.health then return end
    if display.RapzoQoLToxiDecor then return end

    local health = display.health

    local highlight = health:CreateTexture(nil, "OVERLAY")
    highlight:SetPoint("TOPLEFT", health, "TOPLEFT", 1, -1)
    highlight:SetPoint("TOPRIGHT", health, "TOPRIGHT", -1, -1)
    highlight:SetHeight(1)
    highlight:SetColorTexture(1, 1, 1, 0.10)

    local lowerShade = health:CreateTexture(nil, "OVERLAY")
    lowerShade:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 1, 1)
    lowerShade:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -1, 1)
    lowerShade:SetHeight(7)
    lowerShade:SetColorTexture(0, 0, 0, 0.10)

    display.RapzoQoLToxiDecor = {
        highlight = highlight,
        lowerShade = lowerShade,
    }
end

local function setToxiDecorVisible(display, visible)
    local decor = display and display.RapzoQoLToxiDecor
    if not decor then return end
    if decor.highlight then decor.highlight:SetShown(visible) end
    if decor.lowerShade then decor.lowerShade:SetShown(visible) end
end

-- Snapshot de fuentes/sombras/colores antes de la primera tipografia Toxi, para
-- que V2 -> V1 vuelva exactamente a lo creado por HUD.lua sin /reload.
local TYPOGRAPHY_KEYS = { "nameText", "healthPercentText", "healthValueText", "powerValueText", "levelText" }

local function captureTypography(display)
    if not display or display.RapzoQoLTypographySnapshot then return end
    local snapshot = {}
    for _, key in ipairs(TYPOGRAPHY_KEYS) do
        local text = display[key]
        if text then
            local entry = {}
            if type(text.GetFont) == "function" then
                local ok, path, size, flags = pcall(text.GetFont, text)
                if ok and path then entry.font = { path, size, flags } end
            end
            if type(text.GetShadowOffset) == "function" then
                local ok, x, y = pcall(text.GetShadowOffset, text)
                if ok then entry.shadowOffset = { x or 0, y or 0 } end
            end
            if type(text.GetShadowColor) == "function" then
                local ok, r, g, b, a = pcall(text.GetShadowColor, text)
                if ok then entry.shadowColor = { r or 0, g or 0, b or 0, a or 0 } end
            end
            if type(text.GetTextColor) == "function" then
                local ok, r, g, b, a = pcall(text.GetTextColor, text)
                if ok then entry.textColor = { r or 1, g or 1, b or 1, a or 1 } end
            end
            snapshot[key] = entry
        end
    end
    display.RapzoQoLTypographySnapshot = snapshot
end

local function restoreTypography(display)
    local snapshot = display and display.RapzoQoLTypographySnapshot
    if not snapshot then return end
    for key, entry in pairs(snapshot) do
        local text = display[key]
        if text then
            if entry.font then pcall(text.SetFont, text, entry.font[1], entry.font[2], entry.font[3]) end
            if entry.shadowOffset then pcall(text.SetShadowOffset, text, entry.shadowOffset[1], entry.shadowOffset[2]) end
            if entry.shadowColor then pcall(text.SetShadowColor, text, entry.shadowColor[1], entry.shadowColor[2], entry.shadowColor[3], entry.shadowColor[4]) end
            if entry.textColor then pcall(text.SetTextColor, text, entry.textColor[1], entry.textColor[2], entry.textColor[3], entry.textColor[4]) end
        end
    end
end

local function applyToxiTypography(display)
    if not display then return end
    captureTypography(display)
    local fontPath = STANDARD_TEXT_FONT

    if display.nameText then
        display.nameText:SetTextColor(0.98, 0.98, 0.98)
        display.nameText:SetShadowColor(0, 0, 0, 1)
        display.nameText:SetShadowOffset(1, -1)
        if fontPath then
            pcall(display.nameText.SetFont, display.nameText, fontPath, 9, "OUTLINE")
        end
    end

    for _, text in ipairs({
        display.healthPercentText,
        display.healthValueText,
    }) do
        if text and fontPath then
            pcall(text.SetFont, text, fontPath, 8, "OUTLINE")
        end
    end

    if display.powerValueText and fontPath then
        pcall(display.powerValueText.SetFont, display.powerValueText, fontPath, 8, "OUTLINE")
    end

    if display.levelText and fontPath then
        pcall(display.levelText.SetFont, display.levelText, fontPath, 10, "OUTLINE")
    end
end

local function applyStyle1(display)
    if not display then return end

    display:SetScale(1)
    setShellVisible(display, true)
    display:SetSize(240, 64)

    -- Todo lo que V2 toca se devuelve aqui: tipografia, alto del nombre, color
    -- y fondo de las barras. Asi V1 -> V2 -> V1 no necesita /reload.
    restoreTypography(display)
    local colors = HUD.COLORS or {}
    local dark = colors.dark or { 0.015, 0.020, 0.028 }
    local powerColor = colors.power or { 0.22, 0.28, 0.38 }

    display.nameText:ClearAllPoints()
    display.nameText:SetHeight(14)
    display.nameText:SetJustifyH("LEFT")
    display.nameText:SetPoint("TOPLEFT", display, "TOPLEFT", 6, -8)
    display.nameText:SetPoint("RIGHT", display, "RIGHT", -6, 0)

    display.health:ClearAllPoints()
    display.health:SetHeight(24)
    display.health:SetPoint("TOPLEFT", display, "TOPLEFT", 6, -25)
    display.health:SetPoint("RIGHT", display, "RIGHT", -6, 0)

    display.power:ClearAllPoints()
    display.power:SetHeight(10)
    display.power:SetPoint("TOPLEFT", display.health, "BOTTOMLEFT", 0, -4)
    display.power:SetPoint("RIGHT", display.health, "RIGHT", 0, 0)
    display.power:SetStatusBarColor(powerColor[1], powerColor[2], powerColor[3])
    if display.health.RapzoQoLBackground then
        display.health.RapzoQoLBackground:SetColorTexture(dark[1], dark[2], dark[3], 0.96)
    end
    if display.power.RapzoQoLBackground then
        display.power.RapzoQoLBackground:SetColorTexture(dark[1], dark[2], dark[3], 0.96)
    end

    if display.unitTag then display.unitTag:Show() end
    if display.levelText then display.levelText:Hide() end
    if display.healthPercentText then display.healthPercentText:Hide() end
    if display.healthValueText then display.healthValueText:Hide() end
    if display.powerValueText then display.powerValueText:Hide() end
    if display.RapzoQoLCastBar then display.RapzoQoLCastBar:Hide() end
    setToxiDecorVisible(display, false)

    if display.color then
        setEdgesColor(display.health and display.health.RapzoQoLEdges, display.color[1], display.color[2], display.color[3], 0.60)
    end
    setEdgesColor(display.power and display.power.RapzoQoLEdges, powerColor[1], powerColor[2], powerColor[3], 0.60)

    setPlayerAurasEnabled(display, false)
    setTargetAurasEnabled(display, false)
end

local function applyStyle2(display)
    if not display then return end

    -- Whole Style 2 frame is scaled uniformly so every element keeps
    -- the same Toxi proportions (text, bars, auras, castbar and resources).
    display:SetScale(HUD:GetFrameScale())

    -- Rapzo QoL / ToxiUI-inspired:
    -- name floats above, health is the visual anchor and the power bar stays thin.
    -- No portrait, no exterior panel and no decorative shell.
    setShellVisible(display, false)
    display:SetSize(STYLE2_WIDTH, STYLE2_HEIGHT)

    display.health:ClearAllPoints()
    display.health:SetHeight(21)
    display.health:SetPoint("TOPLEFT", display, "TOPLEFT", STYLE2_EDGE, -11)
    display.health:SetPoint("RIGHT", display, "RIGHT", -STYLE2_EDGE, 0)

    display.power:ClearAllPoints()
    display.power:SetHeight(9)
    display.power:SetPoint("TOPLEFT", display.health, "BOTTOMLEFT", 0, -1)
    display.power:SetPoint("RIGHT", display.health, "RIGHT", 0, 0)

    display.nameText:ClearAllPoints()
    display.nameText:SetHeight(10)
    display.nameText:SetPoint("BOTTOMLEFT", display.health, "TOPLEFT", 1, 1)
    display.nameText:SetPoint("RIGHT", display.health, "RIGHT", -28, 0)
    display.nameText:SetJustifyH("LEFT")

    if display.unitTag then display.unitTag:Hide() end
    if display.levelText then
        display.levelText:ClearAllPoints()
        display.levelText:SetPoint("BOTTOMRIGHT", display.health, "TOPRIGHT", -1, 1)
        display.levelText:Show()
    end
    if display.healthPercentText then display.healthPercentText:Hide() end
    if display.healthValueText then display.healthValueText:Show() end
    if display.powerValueText then display.powerValueText:Show() end

    ensureToxiDecor(display)
    setToxiDecorVisible(display, true)
    applyToxiTypography(display)

    -- ToxiUI-like black outline: let the class/reaction color be the fill,
    -- not the border. This keeps the frame readable over every zone.
    setEdgesColor(display.health.RapzoQoLEdges, 0.01, 0.01, 0.01, 1.00)
    setEdgesColor(display.power.RapzoQoLEdges, 0.01, 0.01, 0.01, 1.00)

    if display.health.RapzoQoLBackground then
        display.health.RapzoQoLBackground:SetColorTexture(0.025, 0.028, 0.035, 0.98)
    end
    if display.power.RapzoQoLBackground then
        display.power.RapzoQoLBackground:SetColorTexture(0.012, 0.015, 0.020, 0.99)
    end
    display.power:SetStatusBarColor(0.11, 0.14, 0.18, 1)

    local castBar = ensureCastBar(display)
    castBar:SetHeight(10)
    castBar:ClearAllPoints()
    castBar:SetPoint("TOPLEFT", display, "BOTTOMLEFT", 0, -4)
    castBar:SetPoint("RIGHT", display, "RIGHT", 0, 0)
    setEdgesColor(castBar.RapzoQoLEdges, 0.01, 0.01, 0.01, 1.00)
    if castBar.RapzoQoLBackground then
        castBar.RapzoQoLBackground:SetColorTexture(0.012, 0.015, 0.020, 0.99)
    end

    if type(HUD.ApplyClassResourceCastAnchor) == "function" then
        HUD:ApplyClassResourceCastAnchor(display.unit, castBar)
    end

    setPlayerAurasEnabled(display, display.unit == "player")
    setTargetAurasEnabled(display, display.unit == "target" or display.unit == "focus")
    if display.RapzoQoLPlayerAuras then safeCall(display.RapzoQoLPlayerAuras.SetScale, display.RapzoQoLPlayerAuras, HUD:GetAuraScale()) end
    if display.RapzoQoLTargetAuras then safeCall(display.RapzoQoLTargetAuras.SetScale, display.RapzoQoLTargetAuras, HUD:GetAuraScale()) end
    local auraX, auraY = HUD:GetAuraOffset()
    for _, container in pairs({display.RapzoQoLPlayerAuras, display.RapzoQoLTargetAuras}) do
        if container then
            safeCall(container.ClearAllPoints, container)
            safeCall(container.SetPoint, container, "BOTTOMLEFT", display, "TOPLEFT", auraX, STYLE2_AURA_Y + auraY)
        end
    end
    updateCastBar(display.unit)
end

local function applyDisplayStyle(display)
    if HUD:GetStyle() == STYLE_ICON then
        applyStyle2(display)
    else
        applyStyle1(display)
    end
end

function HUD:ApplyFrameStyle(unit)
    if not hudFramesActive() then return end

    if unit then
        applyDisplayStyle(self.unitDisplays and self.unitDisplays[unit])
        return
    end

    for _, key in ipairs({"player", "target", "focus"}) do
        applyDisplayStyle(self.unitDisplays and self.unitDisplays[key])
    end

    if type(self.ReanchorAuras) == "function" then
        self:ReanchorAuras()
    end

    if type(self.ApplyStyleFixes) == "function" then
        self:ApplyStyleFixes()
    end
end

function HUD:SetStyle(style)
    style = tonumber(style)
    if style ~= STYLE_CURRENT and style ~= STYLE_ICON then
        RB:Print("Uso: /rapzo hud style 1|2")
        return false
    end

    local cfg = getConfig()
    cfg.style = style
    self:ApplyFrameStyle()

    if style == STYLE_CURRENT then
        RB:Print("HUD frames: ESTILO 1 (actual).")
    else
        RB:Print("HUD frames: ESTILO 2 TOXI (sin iconos, health principal + power fino).")
    end

    if type(self.RefreshPreview) == "function" then
        self:RefreshPreview()
    end
    return true
end

-- Estilo y valores van separados: UpdateUnitFrames (cada UNIT_HEALTH/POWER)
-- solo escribe valores; el estilo se aplica al crear displays, al cambiar
-- estilo/escala, al cambiar target/focus y al salir de combate.
if type(hooksecurefunc) == "function" then
    if type(HUD.CreateUnitDisplays) == "function" then
        hooksecurefunc(HUD, "CreateUnitDisplays", function()
            HUD:ApplyFrameStyle()
        end)
    end
end

local castEvents = CreateFrame("Frame")
HUD.StyleEvents = castEvents

for _, event in ipairs({
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
}) do
    pcall(castEvents.RegisterEvent, castEvents, event)
end

for _, event in ipairs({
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_EMPOWER_STOP",
}) do
    if type(RB.RegisterUnitEventSafe) == "function" then
        RB:RegisterUnitEventSafe(castEvents, event, "player", "target", "focus")
    else
        pcall(castEvents.RegisterEvent, castEvents, event)
    end
end

castEvents:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_TARGET_CHANGED" then
        HUD:ApplyFrameStyle("target")
        updateCastBar("target")
        return
    elseif event == "PLAYER_FOCUS_CHANGED" then
        HUD:ApplyFrameStyle("focus")
        updateCastBar("focus")
        return
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
        HUD:ApplyFrameStyle()
        updateCastBar("player")
        updateCastBar("target")
        updateCastBar("focus")
        return
    end

    if unit == "player" or unit == "target" or unit == "focus" then
        updateCastBar(unit)
    end
end)

local baseHandleSlash = HUD.HandleSlash
function HUD:HandleSlash(rest)
    rest = tostring(rest or "")
    -- Tolerate leading/trailing whitespace and extra tokens.
    local part = rest:match("^%s*(%S+)") or ""
    local value = rest:match("^%s*%S+%s+(%S+)") or ""
    part = string.lower(part)
    value = string.lower(value)

    if part == "style" then
        if value == "" then
            RB:Print("HUD frame style actual: " .. tostring(self:GetStyle()) .. " | usa /rapzo hud style 1|2")
            return
        end
        self:SetStyle(value)
        return
    elseif part == "scale" then
        if value == "" then
            local scale = self:GetFrameScale()
            local visualW = math.floor(STYLE2_WIDTH * scale + 0.5)
            local visualH = math.floor(STYLE2_HEIGHT * scale + 0.5)
            RB:Print(string.format("HUD scale actual: %.2fx | aprox. %dx%d px | usa /rapzo hud scale 1.25", scale, visualW, visualH))
            return
        elseif value == "reset" then
            self:SetFrameScale(STYLE2_DEFAULT_SCALE)
            return
        end

        if not self:SetFrameScale(value) then
            RB:Print("Uso: /rapzo hud scale 0.50-2.50")
        end
        return
    elseif part == "aurascale" then
        if value == "" then
            local scale = self:GetAuraScale()
            RB:Print(string.format("HUD aura scale actual: %.2fx | aprox. %d px | usa /rapzo hud aurascale 1.25", scale, math.floor(STYLE2_AURA * scale + 0.5)))
            return
        elseif value == "reset" then
            self:SetAuraScale(STYLE2_DEFAULT_AURA_SCALE)
            return
        end

        if not self:SetAuraScale(value) then
            RB:Print("Uso: /rapzo hud aurascale 0.75-1.75")
        end
        return
    elseif part == "aurax" or part == "auray" then
        local x, y = self:GetAuraOffset()
        if value == "reset" then
            self:SetAuraOffset(0, 0)
        elseif value == "" then
            RB:Print(string.format("HUD aura position: X %d | Y %d | usa /rapzo hud aurax -30 o auray 20", x, y))
        elseif part == "aurax" and tonumber(value) then
            self:SetAuraOffset(value, y)
        elseif part == "auray" and tonumber(value) then
            self:SetAuraOffset(x, value)
        else
            RB:Print("Uso: /rapzo hud aurax -150..150 | auray -60..100 | reset")
        end
        return
    elseif part == "preview" then
        if type(self.TogglePreview) == "function" then
            self:TogglePreview(value)
        else
            RB:Print("Preview HUD todavia no esta disponible.")
        end
        return
    end

    return baseHandleSlash(self, rest)
end

if C_Timer and C_Timer.After then
    C_Timer.After(0.6, function() HUD:ApplyFrameStyle() end)
    C_Timer.After(2.0, function() HUD:ApplyFrameStyle() end)
else
    HUD:ApplyFrameStyle()
end
