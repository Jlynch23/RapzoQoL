local addonName = ...
local RB = _G.RapzoQoL or _G.RapzoBags
if not RB or not RB.HUD then return end

local HUD = RB.HUD
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local STYLE2_WIDTH = 150
local STYLE2_HEIGHT = 43
local STYLE2_AURA = 16

HUD.previewFrame = nil
HUD.previewBackdrop = nil
HUD.previewDisplays = HUD.previewDisplays or {}
HUD.previewAuraScenario = HUD.previewAuraScenario or "mixed"

local AURA_SCENARIOS = {
    buffs = {
        label = "BUFFS DE PRUEBA",
        spells = {6673, 21562, 1459, 1126, 19740},
        durations = {"2m", "38", "18", "9", "4"},
        counts = {"", "2", "", "", ""},
    },
    debuffs = {
        label = "DEBUFFS DE PRUEBA",
        spells = {589, 172, 116, 118, 853},
        durations = {"24", "18", "12", "8", "4"},
        counts = {"", "", "", "", ""},
    },
    stacks = {
        label = "CARGAS 2 / 5 / 10 / 25 / 99",
        spells = {6673, 21562, 1459, 1126, 19740},
        durations = {"30", "30", "30", "30", "30"},
        counts = {"2", "5", "10", "25", "99"},
    },
    timers = {
        label = "TIEMPOS 2m / 38 / 18 / 9 / 4",
        spells = {589, 172, 116, 118, 853},
        durations = {"2m", "38", "18", "9", "4"},
        counts = {"", "", "", "", ""},
    },
}

local function getSpellTexture(spellID)
    if C_Spell and type(C_Spell.GetSpellTexture) == "function" then
        local ok, texture = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and texture then return texture end
    end
end

local function setSmallFont(fontString, size)
    if STANDARD_TEXT_FONT then
        pcall(fontString.SetFont, fontString, STANDARD_TEXT_FONT, size, "OUTLINE")
    else
        fontString:SetFontObject("GameFontHighlightSmall")
    end
end

local function makePanel(parent, width, height, color)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, height)

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0.005, 0.009, 0.015, 0.96)
    frame.RapzoQoLPanel = bg

    local accent = frame:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    accent:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    accent:SetHeight(2)
    accent:SetColorTexture(color[1], color[2], color[3], 0.95)

    local edges = {}
    local function edge(a, b, c, d, w, h)
        local tex = frame:CreateTexture(nil, "OVERLAY")
        edges[#edges + 1] = tex
        tex:SetPoint(a, frame, a, b, c)
        if d then tex:SetPoint(d, frame, d, -b, -c) end
        if w then tex:SetWidth(w) end
        if h then tex:SetHeight(h) end
        tex:SetColorTexture(color[1], color[2], color[3], 0.34)
    end

    edge("TOPLEFT", -1, 1, "TOPRIGHT", nil, 1)
    edge("BOTTOMLEFT", -1, -1, "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT", -1, 1, "BOTTOMLEFT", 1, nil)
    edge("TOPRIGHT", 1, 1, "BOTTOMRIGHT", 1, nil)

    frame.RapzoQoLAccent = accent
    frame.RapzoQoLEdges = edges
    return frame
end

local function makeStatusBar(parent, height, color)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(height)
    bar:SetStatusBarTexture(WHITE_TEXTURE)
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(82)
    bar:SetStatusBarColor(color[1], color[2], color[3])

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetColorTexture(0.015, 0.022, 0.034, 0.98)

    local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER")
    bar.RapzoQoLText = text
    return bar
end

local function getPreviewClassColor(classFile, fallback)
    fallback = fallback or {0.92, 0.66, 0.10}
    if type(RAID_CLASS_COLORS) ~= "table" then return fallback end
    local color = RAID_CLASS_COLORS[classFile]
    if not color then return fallback end
    return {color.r or fallback[1], color.g or fallback[2], color.b or fallback[3]}
end

local function makeDemo(parent, key, title, color, classFile, isMob)
    local display = makePanel(parent, STYLE2_WIDTH, 50, color)
    display.key = key
    display.color = color

    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetText(key == "player" and "BUFFS DE PRUEBA" or "DEBUFFS DE PRUEBA")
    label:SetTextColor(color[1], color[2], color[3])
    label:SetPoint("BOTTOMLEFT", display, "TOPLEFT", 0, 42)
    display.previewLabel = label

    local name = display:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("TOPLEFT", display, "TOPLEFT", 6, -8)
    name:SetPoint("RIGHT", display, "RIGHT", -4, 0)
    name:SetHeight(14)
    name:SetJustifyH("LEFT")
    name:SetText(title)
    display.nameText = name

    local levelText = display:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    levelText:SetText(key == "player" and "90" or "??")
    levelText:SetTextColor(1.00, 0.82, 0.15)
    levelText:SetJustifyH("RIGHT")
    display.levelText = levelText

    local tag = display:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tag:SetPoint("TOPRIGHT", display, "TOPRIGHT", -6, -8)
    tag:SetText(string.upper(key))
    tag:SetTextColor(color[1], color[2], color[3])
    display.unitTag = tag

    local health = makeStatusBar(display, 24, color)
    health:SetPoint("TOPLEFT", display, "TOPLEFT", 6, -25)
    health:SetPoint("RIGHT", display, "RIGHT", -4, 0)
    health.RapzoQoLText:SetText(key == "player" and "1.24M / 1.24M  100%" or "82%")
    display.health = health

    local power = makeStatusBar(display, 10, {0.22, 0.28, 0.38})
    power:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -4)
    power:SetPoint("RIGHT", health, "RIGHT", 0, 0)
    power:SetValue(key == "player" and 72 or 58)
    power.RapzoQoLText:SetText(key == "player" and "RAGE 72" or "POWER")
    display.power = power

    local auraRow = CreateFrame("Frame", nil, display)
    auraRow:SetSize(STYLE2_WIDTH, 18)
    auraRow:SetPoint("BOTTOMLEFT", display, "TOPLEFT", 6, 6)
    display.previewAuras = auraRow
    display.previewAuraButtons = {}

    for i = 1, 5 do
        local aura = CreateFrame("Frame", nil, auraRow)
        aura:SetSize(STYLE2_AURA, STYLE2_AURA)
        aura:SetPoint("LEFT", auraRow, "LEFT", (i - 1) * 21, 0)

        local tex = aura:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(aura)
        local palette = {
            {0.95, 0.56, 0.12},
            {0.22, 0.66, 0.96},
            {0.70, 0.25, 0.92},
            {0.24, 0.78, 0.42},
            {0.94, 0.26, 0.18},
        }
        local c = palette[i]
        local initialScenario = key == "player" and AURA_SCENARIOS.buffs or AURA_SCENARIOS.debuffs
        local spellTexture = getSpellTexture(initialScenario.spells[i])
        if spellTexture then tex:SetTexture(spellTexture) else tex:SetColorTexture(c[1], c[2], c[3], 0.94) end
        aura.previewTexture = tex

        if type(aura.CreateMaskTexture) == "function" and type(tex.AddMaskTexture) == "function" then
            local mask = aura:CreateMaskTexture()
            mask:SetAllPoints(tex)
            mask:SetTexture(PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            tex:AddMaskTexture(mask)
        end

        local duration = aura:CreateFontString(nil, "OVERLAY")
        setSmallFont(duration, 7)
        duration:SetPoint("CENTER", aura, "CENTER", 0, 0)
        duration:SetText(initialScenario.durations[i])
        aura.previewDuration = duration

        local count = aura:CreateFontString(nil, "OVERLAY")
        setSmallFont(count, 7)
        count:SetPoint("BOTTOMRIGHT", aura, "BOTTOMRIGHT", 1, -1)
        count:SetText(initialScenario.counts[i])
        aura.previewCount = count
        display.previewAuraButtons[i] = aura
    end

    local cast = makeStatusBar(display, 14, {0.92, 0.63, 0.12})
    cast:SetPoint("TOPLEFT", display, "BOTTOMLEFT", 6, -4)
    cast:SetPoint("RIGHT", display, "RIGHT", -4, 0)
    cast:SetValue(key == "target" and 48 or 68)
    cast.RapzoQoLText:SetText(key == "target" and "Golpe demo  1.2 / 2.0" or "Lanzamiento demo")
    display.previewCast = cast

    HUD.previewDisplays[key] = display
    return display
end

local function applyAuraScenario(name)
    HUD.previewAuraScenario = name or "mixed"
    for key, display in pairs(HUD.previewDisplays or {}) do
        local scenarioName = HUD.previewAuraScenario
        if scenarioName == "mixed" then scenarioName = key == "player" and "buffs" or "debuffs" end
        local scenario = AURA_SCENARIOS[scenarioName] or AURA_SCENARIOS.buffs
        if display.previewLabel then display.previewLabel:SetText(scenario.label) end
        for i, aura in ipairs(display.previewAuraButtons or {}) do
            local spellTexture = getSpellTexture(scenario.spells[i])
            if spellTexture and aura.previewTexture then aura.previewTexture:SetTexture(spellTexture) end
            if aura.previewDuration then aura.previewDuration:SetText(scenario.durations[i] or "") end
            if aura.previewCount then aura.previewCount:SetText(scenario.counts[i] or "") end
        end
    end
end

local function applyPreviewAuraLayout(display)
    if not display or not display.previewAuras then return end
    local auraScale = (type(HUD.GetAuraScale) == "function" and HUD:GetAuraScale()) or 1
    local size = STYLE2_AURA * auraScale
    local spacing = 5 * auraScale

    for i, aura in ipairs(display.previewAuraButtons or {}) do
        aura:ClearAllPoints()
        aura:SetSize(size, size)
        aura:SetPoint("LEFT", display.previewAuras, "LEFT", (i - 1) * (size + spacing), 0)
    end
end

local function setPreviewShellVisible(display, visible)
    if not display then return end
    if display.RapzoQoLPanel then display.RapzoQoLPanel:SetAlpha(visible and 1 or 0) end
    if display.RapzoQoLAccent then display.RapzoQoLAccent:SetAlpha(visible and 1 or 0) end
    for _, edge in ipairs(display.RapzoQoLEdges or {}) do
        edge:SetAlpha(visible and 1 or 0)
    end
end

local function applyPreviewStyle(display, style)
    if not display then return end
    applyPreviewAuraLayout(display)

    if style == 2 then
        display:SetScale((type(HUD.GetFrameScale) == "function" and HUD:GetFrameScale()) or 1.50)
        setPreviewShellVisible(display, false)
        display:SetSize(STYLE2_WIDTH, STYLE2_HEIGHT)

        display.health:ClearAllPoints()
        display.health:SetHeight(21)
        display.health:SetPoint("TOPLEFT", display, "TOPLEFT", 0, -11)
        display.health:SetPoint("RIGHT", display, "RIGHT", 0, 0)

        display.power:ClearAllPoints()
        display.power:SetHeight(9)
        display.power:SetPoint("TOPLEFT", display.health, "BOTTOMLEFT", 0, -1)
        display.power:SetPoint("RIGHT", display.health, "RIGHT", 0, 0)

        display.nameText:ClearAllPoints()
        display.nameText:SetHeight(10)
        display.nameText:SetPoint("BOTTOMLEFT", display.health, "TOPLEFT", 1, 1)
        display.nameText:SetPoint("RIGHT", display.health, "RIGHT", -28, 0)
        display.nameText:SetJustifyH("LEFT")

        display.previewAuras:ClearAllPoints()
        display.previewAuras:SetSize(STYLE2_WIDTH, 18)
        local auraX, auraY = 0, 0
        if type(HUD.GetAuraOffset) == "function" then auraX, auraY = HUD:GetAuraOffset() end
        display.previewAuras:SetPoint("BOTTOMLEFT", display, "TOPLEFT", auraX, 18 + auraY)
        display.previewLabel:ClearAllPoints()
        display.previewLabel:SetPoint("BOTTOMLEFT", display.previewAuras, "TOPLEFT", 0, 4)

        display.previewCast:ClearAllPoints()
        display.previewCast:SetPoint("TOPLEFT", display, "BOTTOMLEFT", 0, -4)
        display.previewCast:SetPoint("RIGHT", display, "RIGHT", 0, 0)

        display.levelText:ClearAllPoints()
        display.levelText:SetPoint("BOTTOMRIGHT", display.health, "TOPRIGHT", -1, 1)
        display.levelText:Show()
        display.previewCast:SetHeight(10)

        display.previewAuras:Show()
        display.previewLabel:Show()
        display.previewCast:Show()
        display.unitTag:Hide()
    else
        display:SetScale(1)
        setPreviewShellVisible(display, true)
        display:SetSize(240, 64)

        -- Deshacer lo que V2 cambio (alturas), igual que applyStyle1 real.
        display.nameText:ClearAllPoints()
        display.nameText:SetHeight(14)
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

        display.previewCast:Hide()
        if display.levelText then display.levelText:Hide() end
        display.unitTag:Show()

        if display.key == "player" then
            display.previewAuras:Hide()
            display.previewLabel:Hide()
        else
            display.previewAuras:Show()
            display.previewLabel:Show()
            display.previewAuras:ClearAllPoints()
            display.previewAuras:SetPoint("BOTTOMLEFT", display, "TOPLEFT", 0, 7)
        end
    end

end

function HUD:CreatePreview()
    if self.previewFrame then return self.previewFrame end

    local backdrop = CreateFrame("Frame", "RapzoQoLHUDPreviewBackdrop", UIParent)
    backdrop:SetAllPoints(UIParent)
    backdrop:SetFrameStrata("FULLSCREEN_DIALOG")
    backdrop:SetFrameLevel(1)
    backdrop:EnableMouse(true)
    local backdropTexture = backdrop:CreateTexture(nil, "BACKGROUND")
    backdropTexture:SetAllPoints(backdrop)
    backdropTexture:SetColorTexture(0, 0, 0, 0.88)
    backdrop:Hide()
    self.previewBackdrop = backdrop

    local frame = CreateFrame("Frame", "RapzoQoLHUDPreviewFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(920, 680)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(backdrop:GetFrameLevel() + 10)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetScript("OnHide", function()
        if HUD.previewBackdrop then HUD.previewBackdrop:Hide() end
    end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if frame.TitleBg then
        title:SetPoint("LEFT", frame.TitleBg, "LEFT", 6, 0)
    else
        title:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -6)
    end
    title:SetText("Rapzo QoL - HUD Preview")
    frame.RapzoQoLTitle = title

    local intro = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -38)
    intro:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
    intro:SetJustifyH("LEFT")
    intro:SetText("Preview seguro: son frames falsos de demostracion. Puedes comparar Estilo 1 y Estilo 2 sin necesitar target, focus ni entrar en combate.")

    local style1 = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    style1:SetSize(150, 26)
    style1:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -68)
    style1:SetText("Estilo 1 - Actual")
    style1:SetScript("OnClick", function()
        HUD:SetStyle(1)
        HUD:ShowPreview()
    end)

    local style2 = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    style2:SetSize(260, 26)
    style2:SetPoint("LEFT", style1, "RIGHT", 10, 0)
    style2:SetText("Estilo 2 - ToxiUI")
    style2:SetScript("OnClick", function()
        HUD:SetStyle(2)
        HUD:ShowPreview()
    end)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("LEFT", style2, "RIGHT", 16, 0)
    hint:SetText("/rapzo hud style 1|2")
    hint:SetTextColor(0.55, 0.75, 0.95)

    local scaleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -106)
    scaleLabel:SetText("Escala exacta Style 2")

    local scaleValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scaleValue:SetPoint("LEFT", scaleLabel, "RIGHT", 10, 0)
    scaleValue:SetTextColor(1.00, 0.82, 0.15)

    local slider = CreateFrame("Slider", "RapzoQoLHUDScaleSlider", frame, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -124)
    slider:SetWidth(300)
    slider:SetMinMaxValues(0.50, 2.50)
    slider:SetValueStep(0.01)
    if type(slider.SetObeyStepOnDrag) == "function" then
        slider:SetObeyStepOnDrag(true)
    end

    local low = _G[slider:GetName() .. "Low"]
    local high = _G[slider:GetName() .. "High"]
    local label = _G[slider:GetName() .. "Text"]
    if low then low:SetText("0.50x") end
    if high then high:SetText("2.50x") end
    if label then label:SetText("") end

    -- SetFrameScale relayouta los frames reales: al arrastrar se aplica como
    -- mucho cada 0.1 s, no en cada paso de 0.01.
    local pendingScale
    local function flushScale()
        local value = pendingScale
        pendingScale = nil
        if value and type(HUD.SetFrameScale) == "function" then
            HUD:SetFrameScale(value, true)
        end
    end
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor((tonumber(value) or 1.50) * 100 + 0.5) / 100
        scaleValue:SetText(string.format("%.2fx  (~%dx%d px)", value, math.floor(STYLE2_WIDTH * value + 0.5), math.floor(STYLE2_HEIGHT * value + 0.5)))
        if type(HUD.GetFrameScale) == "function" and math.abs((HUD:GetFrameScale() or 0) - value) < 0.001 then
            return
        end
        local scheduled = pendingScale ~= nil
        pendingScale = value
        if scheduled then return end
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0.1, flushScale)
        else
            flushScale()
        end
    end)

    slider:SetValue((type(HUD.GetFrameScale) == "function" and HUD:GetFrameScale()) or 1.50)
    frame.RapzoQoLScaleSlider = slider
    frame.RapzoQoLScaleValue = scaleValue

    local auraLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    auraLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 390, -106)
    auraLabel:SetText("Tamaño de buffs / debuffs V2")

    local auraValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    auraValue:SetPoint("LEFT", auraLabel, "RIGHT", 10, 0)
    auraValue:SetTextColor(1.00, 0.82, 0.15)

    local auraSlider = CreateFrame("Slider", "RapzoQoLHUDAuraScaleSlider", frame, "OptionsSliderTemplate")
    auraSlider:SetPoint("TOPLEFT", frame, "TOPLEFT", 390, -124)
    auraSlider:SetWidth(300)
    auraSlider:SetMinMaxValues(0.75, 1.75)
    auraSlider:SetValueStep(0.05)
    if type(auraSlider.SetObeyStepOnDrag) == "function" then
        auraSlider:SetObeyStepOnDrag(true)
    end

    local auraLow = _G[auraSlider:GetName() .. "Low"]
    local auraHigh = _G[auraSlider:GetName() .. "High"]
    local auraText = _G[auraSlider:GetName() .. "Text"]
    if auraLow then auraLow:SetText("12 px") end
    if auraHigh then auraHigh:SetText("28 px") end
    if auraText then auraText:SetText("") end

    auraSlider:SetScript("OnValueChanged", function(_, value)
        value = math.floor((tonumber(value) or 1) * 20 + 0.5) / 20
        auraValue:SetText(string.format("%.2fx  (~%d px base)", value, math.floor(STYLE2_AURA * value + 0.5)))
        if type(HUD.SetAuraScale) == "function" then
            HUD:SetAuraScale(value, true)
        end
    end)
    auraSlider:SetValue((type(HUD.GetAuraScale) == "function" and HUD:GetAuraScale()) or 1)
    frame.RapzoQoLAuraScaleSlider = auraSlider
    frame.RapzoQoLAuraScaleValue = auraValue

    local positionXValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    positionXValue:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -164)
    positionXValue:SetTextColor(1.00, 0.82, 0.15)

    local positionYValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    positionYValue:SetPoint("TOPLEFT", frame, "TOPLEFT", 390, -164)
    positionYValue:SetTextColor(1.00, 0.82, 0.15)

    local function makePositionSlider(name, x, minValue, maxValue, onChanged)
        local control = CreateFrame("Slider", name, frame, "OptionsSliderTemplate")
        control:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -184)
        control:SetWidth(300)
        control:SetMinMaxValues(minValue, maxValue)
        control:SetValueStep(1)
        if type(control.SetObeyStepOnDrag) == "function" then control:SetObeyStepOnDrag(true) end
        local lowText = _G[control:GetName() .. "Low"]
        local highText = _G[control:GetName() .. "High"]
        local titleText = _G[control:GetName() .. "Text"]
        if lowText then lowText:SetText(tostring(minValue)) end
        if highText then highText:SetText(tostring(maxValue)) end
        if titleText then titleText:SetText("") end
        control:SetScript("OnValueChanged", onChanged)
        return control
    end

    local positionXSlider = makePositionSlider("RapzoQoLHUDAuraXSlider", 20, -150, 150, function(_, value)
        value = math.floor((tonumber(value) or 0) + 0.5)
        local _, currentY = HUD:GetAuraOffset()
        positionXValue:SetText(string.format("Horizontal: %d  (izquierda / derecha)", value))
        HUD:SetAuraOffset(value, currentY, true)
    end)

    local positionYSlider = makePositionSlider("RapzoQoLHUDAuraYSlider", 390, -60, 100, function(_, value)
        value = math.floor((tonumber(value) or 0) + 0.5)
        local currentX = HUD:GetAuraOffset()
        positionYValue:SetText(string.format("Vertical: %d  (abajo / arriba)", value))
        HUD:SetAuraOffset(currentX, value, true)
    end)

    local resetPosition = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    resetPosition:SetSize(150, 24)
    resetPosition:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -20, -174)
    resetPosition:SetText("Centrar auras")
    resetPosition:SetScript("OnClick", function()
        HUD:SetAuraOffset(0, 0, true)
        positionXSlider:SetValue(0)
        positionYSlider:SetValue(0)
        HUD:RefreshPreview()
    end)

    local initialX, initialY = HUD:GetAuraOffset()
    positionXSlider:SetValue(initialX)
    positionYSlider:SetValue(initialY)
    frame.RapzoQoLAuraXSlider = positionXSlider
    frame.RapzoQoLAuraYSlider = positionYSlider
    frame.RapzoQoLAuraXValue = positionXValue
    frame.RapzoQoLAuraYValue = positionYValue

    local scenarioTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scenarioTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -224)
    scenarioTitle:SetText("Caso que quieres probar:")

    local previousButton = scenarioTitle
    local scenarios = {
        {"Mixto", "mixed"}, {"Buffs", "buffs"}, {"Debuffs", "debuffs"},
        {"Cargas", "stacks"}, {"Duraciones", "timers"},
    }
    for _, info in ipairs(scenarios) do
        local scenarioName = info[2]
        local scenarioButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        scenarioButton:SetSize(105, 24)
        scenarioButton:SetPoint("LEFT", previousButton, "RIGHT", 8, 0)
        scenarioButton:SetText(info[1])
        scenarioButton:SetScript("OnClick", function()
            applyAuraScenario(scenarioName)
        end)
        previousButton = scenarioButton
    end

    local auraHelp = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    auraHelp:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -258)
    auraHelp:SetText("Mixto: Player muestra buffs y Target/Focus debuffs. Los otros botones fuerzan el mismo caso en los tres frames.")

    local player = makeDemo(frame, "player", "Rapzo", getPreviewClassColor("WARRIOR", {0.92, 0.66, 0.10}), "WARRIOR", false)
    player:SetPoint("TOPLEFT", frame, "TOPLEFT", 70, -315)

    local target = makeDemo(frame, "target", "Muñeco de entrenamiento", {0.92, 0.30, 0.09}, nil, true)
    target:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -70, -315)

    local focus = makeDemo(frame, "focus", "Focus Rogue", getPreviewClassColor("ROGUE", {1.00, 0.96, 0.41}), "ROGUE", false)
    focus:SetPoint("BOTTOM", frame, "BOTTOM", 0, 82)

    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 18)
    note:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
    note:SetJustifyH("LEFT")
    note:SetText("Estilo 2 Toxi: nombre arriba, health principal, power fino, sin iconos, auras arriba y castbar abajo.")

    self.previewFrame = frame
    applyAuraScenario(self.previewAuraScenario)

    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = "RapzoQoLHUDPreviewFrame"
    end

    self:RefreshPreview()
    frame:Hide()
    return frame
end

function HUD:RefreshPreview()
    local frame = self.previewFrame
    if not frame then return end

    if frame.RapzoQoLScaleSlider and type(self.GetFrameScale) == "function" then
        local scale = self:GetFrameScale()
        if math.abs((frame.RapzoQoLScaleSlider:GetValue() or 0) - scale) > 0.001 then
            frame.RapzoQoLScaleSlider:SetValue(scale)
        end
        if frame.RapzoQoLScaleValue then
            frame.RapzoQoLScaleValue:SetText(string.format("%.2fx  (~%dx%d px)", scale, math.floor(STYLE2_WIDTH * scale + 0.5), math.floor(STYLE2_HEIGHT * scale + 0.5)))
        end
    end

    if frame.RapzoQoLAuraScaleSlider and type(self.GetAuraScale) == "function" then
        local auraScale = self:GetAuraScale()
        if math.abs((frame.RapzoQoLAuraScaleSlider:GetValue() or 0) - auraScale) > 0.001 then
            frame.RapzoQoLAuraScaleSlider:SetValue(auraScale)
        end
        if frame.RapzoQoLAuraScaleValue then
            frame.RapzoQoLAuraScaleValue:SetText(string.format("%.2fx  (~%d px base)", auraScale, math.floor(STYLE2_AURA * auraScale + 0.5)))
        end
    end

    if type(self.GetAuraOffset) == "function" then
        local auraX, auraY = self:GetAuraOffset()
        if frame.RapzoQoLAuraXSlider and frame.RapzoQoLAuraXSlider:GetValue() ~= auraX then
            frame.RapzoQoLAuraXSlider:SetValue(auraX)
        end
        if frame.RapzoQoLAuraYSlider and frame.RapzoQoLAuraYSlider:GetValue() ~= auraY then
            frame.RapzoQoLAuraYSlider:SetValue(auraY)
        end
        if frame.RapzoQoLAuraXValue then
            frame.RapzoQoLAuraXValue:SetText(string.format("Horizontal: %d  (izquierda / derecha)", auraX))
        end
        if frame.RapzoQoLAuraYValue then
            frame.RapzoQoLAuraYValue:SetText(string.format("Vertical: %d  (abajo / arriba)", auraY))
        end
    end

    local style = self:GetStyle()
    for _, key in ipairs({"player", "target", "focus"}) do
        applyPreviewStyle(self.previewDisplays[key], style)
    end
end

function HUD:ShowPreview()
    local frame = self:CreatePreview()
    self:RefreshPreview()
    if self.previewBackdrop then self.previewBackdrop:Show() end
    frame:Show()
    frame:Raise()
end

function HUD:HidePreview()
    if self.previewFrame then self.previewFrame:Hide() end
    if self.previewBackdrop then self.previewBackdrop:Hide() end
end

function HUD:TogglePreview(value)
    value = string.lower(tostring(value or ""))

    if value == "off" then
        self:HidePreview()
        RB:Print("HUD preview: OFF")
        return
    end

    if value == "on" then
        self:ShowPreview()
        RB:Print("HUD preview: ON")
        return
    end

    local frame = self:CreatePreview()
    if frame:IsShown() then
        self:HidePreview()
        RB:Print("HUD preview: OFF")
    else
        self:ShowPreview()
        RB:Print("HUD preview: ON")
    end
end
