local addonName = ...
local RB = _G.RapzoQoL or _G.RapzoBags
if not RB or not RB.HUD then return end

local HUD = RB.HUD
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"

local RESOURCE_GAP = 3
local RESOURCE_HEIGHT = 6
local RESOURCE_WIDTH = 150
local RESOURCE_Y = -2
local CAST_GAP = 3
local MAX_PIPS = 10

local function isSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

local function safeCall(func, ...)
    if type(func) ~= "function" then return false end
    return pcall(func, ...)
end

local function getPlayerSpecID()
    -- 11.1.5+: C_SpecializationInfo; las globales quedan como fallback deprecado.
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local getSpecInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
    if type(getSpec) ~= "function" or type(getSpecInfo) ~= "function" then
        return nil
    end

    local okIndex, index = pcall(getSpec)
    if not okIndex or not index or isSecret(index) then return nil end

    local okInfo, specID = pcall(getSpecInfo, index)
    if not okInfo or not specID or isSecret(specID) then return nil end
    return tonumber(specID)
end

local function getPlayerClassFile()
    if type(UnitClass) ~= "function" then return nil end
    local ok, _, classFile = pcall(UnitClass, "player")
    if not ok or isSecret(classFile) or type(classFile) ~= "string" then return nil end
    return classFile
end

local function enumPower(name)
    return Enum and Enum.PowerType and Enum.PowerType[name] or nil
end

local RESOURCE_DEFS = {
    ROGUE = {
        label = "COMBO",
        power = "ComboPoints",
    },
    WARLOCK = {
        label = "SHARDS",
        power = "SoulShards",
        precision = 10,
    },
    PALADIN = {
        label = "HOLY POWER",
        power = "HolyPower",
    },
    DEATHKNIGHT = {
        label = "RUNES",
        kind = "runes",
        max = 6,
    },
    EVOKER = {
        label = "ESSENCE",
        power = "Essence",
    },
    DRUID = {
        label = "COMBO",
        power = "ComboPoints",
        specs = {
            [103] = true, -- Feral
        },
    },
    MONK = {
        label = "CHI",
        power = "Chi",
        specs = {
            [269] = true, -- Windwalker
        },
    },
    MAGE = {
        label = "ARCANE",
        power = "ArcaneCharges",
        specs = {
            [62] = true, -- Arcane
        },
    },
}

-- La definicion solo cambia con clase/spec: se cachea y se invalida en los
-- eventos de spec/talentos para no consultar UnitClass y la spec por cada tick.
local resourceDefCache = { valid = false }

local function invalidateResourceDef()
    resourceDefCache.valid = false
end

local function computeResourceDef()
    local classFile = getPlayerClassFile()
    if not classFile then return nil end

    local def = RESOURCE_DEFS[classFile]
    if not def then return nil end

    if def.specs then
        local specID = getPlayerSpecID()
        if not specID or def.specs[specID] ~= true then
            return nil
        end
    end

    if def.kind ~= "runes" and not enumPower(def.power) then
        return nil
    end

    return def, classFile
end

local function getResourceDef()
    if resourceDefCache.valid then
        return resourceDefCache.def, resourceDefCache.classFile
    end
    local def, classFile = computeResourceDef()
    -- Sin clase legible (login temprano) no se cachea el nil.
    if classFile then
        resourceDefCache.valid = true
        resourceDefCache.def = def
        resourceDefCache.classFile = classFile
    end
    return def, classFile
end

local function getPlayerClassColor(display)
    if display and display.color then
        return display.color
    end

    local classFile = getPlayerClassFile()
    local classColor = classFile and type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[classFile]
    if classColor then
        return {classColor.r or 1, classColor.g or 1, classColor.b or 1}
    end

    return {0.95, 0.70, 0.16}
end

local function createPip(parent)
    local pip = CreateFrame("StatusBar", nil, parent)
    pip:SetStatusBarTexture(WHITE_TEXTURE)
    pip:SetMinMaxValues(0, 1)
    pip:SetValue(0)

    local bg = pip:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(pip)
    bg:SetColorTexture(0.035, 0.045, 0.06, 0.98)

    local edge = pip:CreateTexture(nil, "OVERLAY")
    edge:SetAllPoints(pip)
    edge:SetTexture("Interface\\Buttons\\WHITE8X8")
    edge:SetColorTexture(0.30, 0.34, 0.40, 0.55)

    pip.RapzoQoLBackground = bg
    pip.RapzoQoLEdge = edge
    return pip
end

local function ensureResourceFrame(display)
    if not display or display.unit ~= "player" then return nil end
    if display.RapzoQoLClassResource then return display.RapzoQoLClassResource end

    local frame = CreateFrame("Frame", nil, display)
    frame:SetSize(RESOURCE_WIDTH, RESOURCE_HEIGHT)
    frame:SetPoint("TOPLEFT", display, "BOTTOMLEFT", 0, RESOURCE_Y)
    frame:SetFrameLevel(display:GetFrameLevel() + 4)
    frame:EnableMouse(false)

    frame.pips = {}
    for i = 1, MAX_PIPS do
        frame.pips[i] = createPip(frame)
    end

    frame:Hide()
    display.RapzoQoLClassResource = frame
    return frame
end

local function layoutPips(frame, count)
    count = math.max(1, math.min(MAX_PIPS, tonumber(count) or 1))
    if frame.activeCount == count then return end
    local totalGap = RESOURCE_GAP * (count - 1)
    local pipWidth = math.max(4, (RESOURCE_WIDTH - totalGap) / count)

    for i, pip in ipairs(frame.pips) do
        pip:ClearAllPoints()
        if i <= count then
            pip:SetSize(pipWidth, RESOURCE_HEIGHT)
            if i == 1 then
                pip:SetPoint("LEFT", frame, "LEFT", 0, 0)
            else
                pip:SetPoint("LEFT", frame.pips[i - 1], "RIGHT", RESOURCE_GAP, 0)
            end
            pip:Show()
        else
            pip:Hide()
        end
    end

    frame.activeCount = count
end

local function stylePips(frame, display)
    local color = getPlayerClassColor(display)
    for i = 1, frame.activeCount or 0 do
        local pip = frame.pips[i]
        pip:SetStatusBarColor(color[1], color[2], color[3], 0.98)
        if pip.RapzoQoLEdge then
            pip.RapzoQoLEdge:SetColorTexture(color[1], color[2], color[3], 0.48)
        end
    end
end

local function setNumericPips(frame, current, maximum)
    if isSecret(current) or isSecret(maximum) then
        frame:Hide()
        return false
    end

    current = tonumber(current)
    maximum = tonumber(maximum)
    if not current or not maximum or maximum <= 0 then
        frame:Hide()
        return false
    end

    maximum = math.min(MAX_PIPS, math.max(1, math.ceil(maximum)))
    layoutPips(frame, maximum)

    for i = 1, maximum do
        local fraction = current - (i - 1)
        if fraction < 0 then fraction = 0 end
        if fraction > 1 then fraction = 1 end
        frame.pips[i]:SetValue(fraction)
    end

    return true
end

local function updatePowerResource(frame, def)
    local powerType = enumPower(def.power)
    if not powerType or type(UnitPower) ~= "function" or type(UnitPowerMax) ~= "function" then
        return false
    end

    local usePrecision = def.precision ~= nil
    local okCurrent, current = pcall(UnitPower, "player", powerType, usePrecision)
    local okMaximum, maximum = pcall(UnitPowerMax, "player", powerType, usePrecision)
    if not okCurrent or not okMaximum then return false end
    if isSecret(current) or isSecret(maximum) then return false end

    if def.precision then
        current = (tonumber(current) or 0) / def.precision
        maximum = (tonumber(maximum) or 0) / def.precision
    end

    return setNumericPips(frame, current, maximum)
end

local function runeProgress(index)
    if type(GetRuneCooldown) ~= "function" then return nil end
    local ok, startTime, duration, ready = pcall(GetRuneCooldown, index)
    if not ok or isSecret(startTime) or isSecret(duration) or isSecret(ready) then
        return nil
    end

    if ready == true then return 1 end

    startTime = tonumber(startTime)
    duration = tonumber(duration)
    if not startTime or not duration or duration <= 0 or type(GetTime) ~= "function" then
        return 0
    end

    local elapsed = GetTime() - startTime
    local progress = elapsed / duration
    if progress < 0 then progress = 0 end
    if progress > 1 then progress = 1 end
    return progress
end

local function updateRunes(frame)
    layoutPips(frame, 6)

    local valid = false
    for i = 1, 6 do
        local progress = runeProgress(i)
        if progress ~= nil then
            frame.pips[i]:SetValue(progress)
            valid = true
        else
            frame.pips[i]:SetValue(0)
        end
    end

    return valid
end

local function setRuneAnimation(frame, enabled)
    if enabled then
        if frame:GetScript("OnUpdate") then return end

        local elapsedTotal = 0
        frame:SetScript("OnUpdate", function(self, elapsed)
            elapsedTotal = elapsedTotal + (tonumber(elapsed) or 0)
            if elapsedTotal < 0.05 then return end
            elapsedTotal = 0

            if HUD:GetStyle() ~= 2 or not self:IsShown() then
                return
            end

            updateRunes(self)
        end)
    else
        frame:SetScript("OnUpdate", nil)
    end
end

function HUD:ApplyClassResourceCastAnchor(unit, castBar)
    if unit ~= "player" or not castBar then return end

    local display = self.unitDisplays and self.unitDisplays.player
    if not display then return end

    local resource = display.RapzoQoLClassResource

    castBar:ClearAllPoints()
    if self:GetStyle() == 2 and resource and resource:IsShown() then
        castBar:SetPoint("TOPLEFT", resource, "BOTTOMLEFT", 0, -CAST_GAP)
        castBar:SetPoint("RIGHT", resource, "RIGHT", 0, 0)
    else
        castBar:SetPoint("TOPLEFT", display, "BOTTOMLEFT", 0, -4)
        castBar:SetPoint("RIGHT", display, "RIGHT", 0, 0)
    end
end

function HUD:UpdateClassResource()
    local display = self.unitDisplays and self.unitDisplays.player
    if not display then return end

    -- Stay inert while the Rapzo unit frames are toggled off: never create
    -- the resource frame and hide any existing one.
    local cfg = self.config
    local framesOff = (cfg and cfg.unitFrames == false)
        or (type(self.IsEnabled) == "function" and not self:IsEnabled())
    if framesOff then
        local existing = display.RapzoQoLClassResource
        if existing then
            setRuneAnimation(existing, false)
            existing:Hide()
        end
        return
    end

    local frame = ensureResourceFrame(display)
    if not frame then return end

    if self:GetStyle() ~= 2 then
        setRuneAnimation(frame, false)
        frame:Hide()
        self:ApplyClassResourceCastAnchor("player", display.RapzoQoLCastBar)
        return
    end

    local def = getResourceDef()
    if not def then
        setRuneAnimation(frame, false)
        frame:Hide()
        self:ApplyClassResourceCastAnchor("player", display.RapzoQoLCastBar)
        return
    end

    local visible = false
    if def.kind == "runes" then
        visible = updateRunes(frame)
        setRuneAnimation(frame, visible)
    else
        setRuneAnimation(frame, false)
        visible = updatePowerResource(frame, def)
    end

    if visible then
        stylePips(frame, display)
        frame:Show()
    else
        frame:Hide()
    end

    self:ApplyClassResourceCastAnchor("player", display.RapzoQoLCastBar)
end

-- Un solo hook: el recurso se relayouta con el estilo; los valores llegan por
-- sus propios eventos UNIT_POWER_* (solo player).
if type(hooksecurefunc) == "function" then
    if type(HUD.ApplyFrameStyle) == "function" then
        hooksecurefunc(HUD, "ApplyFrameStyle", function(_, unit)
            if unit == nil or unit == "player" then
                HUD:UpdateClassResource()
            end
        end)
    end
end

local events = CreateFrame("Frame")
HUD.ClassResourceEvents = events

for _, event in ipairs({
    "PLAYER_ENTERING_WORLD",
    "PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_TALENT_UPDATE",
    "TRAIT_CONFIG_UPDATED",
    "UPDATE_SHAPESHIFT_FORM",
    "RUNE_POWER_UPDATE",
    "PLAYER_REGEN_ENABLED",
}) do
    pcall(events.RegisterEvent, events, event)
end

for _, event in ipairs({ "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER" }) do
    if type(RB.RegisterUnitEventSafe) == "function" then
        RB:RegisterUnitEventSafe(events, event, "player")
    else
        pcall(events.RegisterEvent, events, event)
    end
end

events:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" then
        if unit ~= "player" then return end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if unit and unit ~= "player" then return end
        invalidateResourceDef()
    elseif event == "PLAYER_TALENT_UPDATE" or event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_ENTERING_WORLD" then
        invalidateResourceDef()
    end

    HUD:UpdateClassResource()
end)

if C_Timer and C_Timer.After then
    C_Timer.After(0.7, function() HUD:UpdateClassResource() end)
    C_Timer.After(2.0, function() HUD:UpdateClassResource() end)
else
    HUD:UpdateClassResource()
end
