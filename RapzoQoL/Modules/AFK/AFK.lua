local addonName = ...
local RB = _G.RapzoBags
if not RB then return end

local AFK = {}
RB.AFK = AFK
RB:RegisterModule("afk", AFK)

AFK.frame = nil
AFK.eventFrame = nil
AFK.ticker = nil
AFK.afkStartedAt = nil
AFK.preview = false
AFK.initialized = false
AFK.lastStateReason = nil

local DARK = {
    screen = {0.002, 0.004, 0.008},
    card = {0.006, 0.010, 0.016},
    border = {0.10, 0.64, 0.82},
    cyan = {0.24, 0.90, 1.00},
    cyanStrong = {0.38, 0.95, 1.00},
    text = {0.97, 0.98, 1.00},
    muted = {0.76, 0.81, 0.88},
    soft = {0.62, 0.72, 0.82},
}

local function getAccentColor()
    -- The AFK screen follows the current player's Blizzard class color.
    -- The global Rapzo QoL accent remains available to the rest of the addon.
    if type(UnitClass) == "function" and type(RAID_CLASS_COLORS) == "table" then
        local ok, _, classFile = pcall(UnitClass, "player")
        local secretClass = classFile
            and type(issecretvalue) == "function"
            and issecretvalue(classFile)

        if ok and classFile and not secretClass then
            local color = RAID_CLASS_COLORS[classFile]
            if color then
                return color.r or DARK.cyan[1],
                    color.g or DARK.cyan[2],
                    color.b or DARK.cyan[3]
            end
        end
    end

    -- Fallback for login/loading edge cases where the class is not available yet.
    if type(RB.GetAccentColor) == "function" then
        return RB:GetAccentColor()
    end
    return DARK.cyan[1], DARK.cyan[2], DARK.cyan[3]
end

local function liftColor(r, g, b, amount)
    amount = tonumber(amount) or 0
    return r + ((1 - r) * amount),
        g + ((1 - g) * amount),
        b + ((1 - b) * amount)
end

local function accentHex(r, g, b)
    if type(RB.ColorToHex) == "function" then
        return RB:ColorToHex(r, g, b)
    end
    return string.format("%02X%02X%02X", math.floor((r * 255) + 0.5), math.floor((g * 255) + 0.5), math.floor((b * 255) + 0.5))
end

local function isSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

local function safeAFKState()
    if type(UnitIsAFK) ~= "function" then
        return nil, "unavailable"
    end

    local ok, value = pcall(UnitIsAFK, "player")
    if not ok then
        return nil, "error"
    end
    if isSecret(value) then
        return nil, "secret"
    end

    return value == true, nil
end

local function getConfig()
    local db = RB:EnsureDB()
    db.settings.afk = type(db.settings.afk) == "table" and db.settings.afk or {}
    local cfg = db.settings.afk

    if cfg.enabled == nil then cfg.enabled = RB:IsFeatureEnabled("afk") end
    if cfg.opacity == nil then cfg.opacity = 0.84 end
    if cfg.showTimer == nil then cfg.showTimer = true end
    if cfg.showCharacter == nil then cfg.showCharacter = true end
    if cfg.showZone == nil then cfg.showZone = true end
    if cfg.showClock == nil then cfg.showClock = true end
    if cfg.showMoney == nil then cfg.showMoney = false end
    if cfg.hideInCombat == nil then cfg.hideInCombat = true end

    if cfg.opacity < 0.35 then cfg.opacity = 0.35 end
    if cfg.opacity > 1 then cfg.opacity = 1 end

    -- AFK:SetEnabled es el unico que sincroniza settings.modules.afk; hacerlo
    -- aqui reescribia la DB en cada tick del temporizador.
    return cfg
end

local function formatElapsed(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60

    if hours > 0 then
        return string.format("%02d:%02d:%02d", hours, minutes, secs)
    end
    return string.format("%02d:%02d", minutes, secs)
end

local function getSpecName()
    -- 11.1.5+: C_SpecializationInfo; las globales quedan como fallback deprecado.
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local getSpecInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
    if type(getSpec) ~= "function" or type(getSpecInfo) ~= "function" then
        return nil
    end

    local okIndex, specIndex = pcall(getSpec)
    if not okIndex or not specIndex or isSecret(specIndex) then
        return nil
    end

    local okInfo, _, specName = pcall(getSpecInfo, specIndex)
    if not okInfo or not specName or isSecret(specName) then
        return nil
    end

    return tostring(specName)
end

local function getClassFile()
    if type(UnitClass) ~= "function" then return nil end
    local ok, _, classFile = pcall(UnitClass, "player")
    if not ok or not classFile or isSecret(classFile) then return nil end
    return classFile
end

local function getZoneText()
    local zone = type(GetRealZoneText) == "function" and GetRealZoneText() or nil
    local subZone = type(GetSubZoneText) == "function" and GetSubZoneText() or nil

    if isSecret(zone) then zone = nil end
    if isSecret(subZone) then subZone = nil end

    zone = type(zone) == "string" and zone or ""
    subZone = type(subZone) == "string" and subZone or ""

    if subZone ~= "" and subZone ~= zone then
        if zone ~= "" then return subZone .. " · " .. zone end
        return subZone
    end
    if zone ~= "" then return zone end
    return "World of Warcraft"
end

local function getMoneyText()
    if type(GetMoney) ~= "function" then return nil end
    local ok, copper = pcall(GetMoney)
    if not ok or not copper or isSecret(copper) then return nil end

    local formatter = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    if type(formatter) == "function" then
        local okText, text = pcall(formatter, copper)
        if okText and text and not isSecret(text) then
            return text
        end
    end

    return string.format("%dg", math.floor((tonumber(copper) or 0) / 10000))
end

function AFK:IsEnabled()
    return getConfig().enabled ~= false and RB:IsFeatureEnabled("afk")
end

function AFK:SetEnabled(enabled)
    local cfg = getConfig()
    cfg.enabled = enabled and true or false
    RB:SetFeatureEnabled("afk", cfg.enabled, true)

    if not cfg.enabled then
        self.preview = false
        self.afkStartedAt = nil
        self:HideScreen(true)
        RB:Print("Pantalla AFK: OFF")
    else
        RB:Print("Pantalla AFK: ON")
        self:RefreshState()
    end
end

function AFK:CreateFrame()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "RapzoQoLAFKFrame", UIParent)
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(900)
    frame:EnableMouse(false)
    frame:Hide()

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(frame)
    background:SetColorTexture(DARK.screen[1], DARK.screen[2], DARK.screen[3], math.min(0.82, getConfig().opacity * 0.92))
    frame.background = background

    local ar, ag, ab = getAccentColor()
    local sr, sg, sb = liftColor(ar, ag, ab, 0.18)

    local card = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    card:SetPoint("CENTER", frame, "CENTER", 0, 0)
    card:SetSize(880, 560)
    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    card:SetBackdropColor(DARK.card[1], DARK.card[2], DARK.card[3], 0.88)
    card:SetBackdropBorderColor(ar, ag, ab, 0.22)
    frame.card = card
    card:SetFrameLevel(frame:GetFrameLevel() + 10)

    local topLine = card:CreateTexture(nil, "ARTWORK")
    topLine:SetPoint("TOP", card, "TOP", 0, 0)
    topLine:SetSize(180, 2)
    topLine:SetColorTexture(ar, ag, ab, 0.72)
    frame.topLine = topLine

    local logo = card:CreateTexture(nil, "OVERLAY")
    logo:SetPoint("TOP", card, "TOP", 0, -28)
    logo:SetSize(1, 1)
    logo:SetAlpha(0)
    frame.logo = logo

    local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", card, "TOP", 0, -56)
    local titleFont = STANDARD_TEXT_FONT
    if titleFont then
        pcall(title.SetFont, title, titleFont, 28, "OUTLINE")
    end
    title:SetText("|cff" .. accentHex(sr, sg, sb) .. "RAPZO|r |cffF4F7FBQoL|r")
    title:SetShadowColor(0, 0, 0, 1)
    title:SetShadowOffset(1, -1)
    title:SetDrawLayer("OVERLAY", 7)
    frame.title = title

    local afkText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    afkText:SetPoint("TOP", title, "BOTTOM", 0, -24)
    local fontPath = STANDARD_TEXT_FONT
    if (not fontPath or fontPath == "") and GameFontNormalHuge and GameFontNormalHuge.GetFont then
        fontPath = select(1, GameFontNormalHuge:GetFont())
    end
    if fontPath then
        pcall(afkText.SetFont, afkText, fontPath, 110, "OUTLINE")
    end
    afkText:SetText("AFK")
    afkText:SetTextColor(DARK.text[1], DARK.text[2], DARK.text[3])
    afkText:SetShadowColor(0, 0, 0, 1)
    afkText:SetShadowOffset(2, -2)
    afkText:SetDrawLayer("OVERLAY", 7)
    frame.afkText = afkText

    local accent = card:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOP", afkText, "BOTTOM", 0, -18)
    accent:SetSize(420, 1)
    accent:SetColorTexture(ar, ag, ab, 0.62)
    frame.accent = accent

    local timer = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    timer:SetPoint("TOP", accent, "BOTTOM", 0, -26)
    if titleFont then
        pcall(timer.SetFont, timer, titleFont, 34, "OUTLINE")
    end
    timer:SetTextColor(sr, sg, sb)
    timer:SetShadowColor(0, 0, 0, 1)
    timer:SetShadowOffset(1, -1)
    timer:SetDrawLayer("OVERLAY", 7)
    frame.timer = timer

    local character = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    character:SetPoint("TOP", timer, "BOTTOM", 0, -34)
    if titleFont then
        pcall(character.SetFont, character, titleFont, 24, "OUTLINE")
    end
    character:SetText("Player")
    character:SetShadowColor(0, 0, 0, 1)
    character:SetShadowOffset(1, -1)
    character:SetDrawLayer("OVERLAY", 7)
    frame.character = character

    local detail = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    detail:SetPoint("TOP", character, "BOTTOM", 0, -10)
    if titleFont then
        pcall(detail.SetFont, detail, titleFont, 16, "OUTLINE")
    end
    detail:SetTextColor(DARK.muted[1], DARK.muted[2], DARK.muted[3])
    detail:SetShadowColor(0, 0, 0, 1)
    detail:SetShadowOffset(1, -1)
    detail:SetDrawLayer("OVERLAY", 7)
    frame.detail = detail

    local zone = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    zone:SetPoint("TOP", detail, "BOTTOM", 0, -12)
    if titleFont then
        pcall(zone.SetFont, zone, titleFont, 16, "OUTLINE")
    end
    zone:SetTextColor(DARK.soft[1], DARK.soft[2], DARK.soft[3])
    zone:SetShadowColor(0, 0, 0, 1)
    zone:SetShadowOffset(1, -1)
    zone:SetDrawLayer("OVERLAY", 7)
    frame.zone = zone

    local money = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    money:SetPoint("TOP", zone, "BOTTOM", 0, -12)
    money:SetDrawLayer("OVERLAY", 7)
    frame.money = money

    local quote = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    quote:SetPoint("BOTTOM", card, "BOTTOM", 0, 62)
    if titleFont then
        pcall(quote.SetFont, quote, titleFont, 14, "OUTLINE")
    end
    quote:SetTextColor(0.78, 0.82, 0.88)
    quote:SetShadowColor(0, 0, 0, 1)
    quote:SetShadowOffset(1, -1)
    quote:SetText("Quality of life, the Rapzo way.")
    frame.quote = quote

    local footer = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footer:SetPoint("TOP", quote, "BOTTOM", 0, -10)
    if titleFont then
        pcall(footer.SetFont, footer, titleFont, 13, "OUTLINE")
    end
    footer:SetTextColor(0.64, 0.70, 0.78)
    footer:SetShadowColor(0, 0, 0, 1)
    footer:SetShadowOffset(1, -1)
    frame.footer = footer

    local fadeIn = frame:CreateAnimationGroup()
    local fadeInAlpha = fadeIn:CreateAnimation("Alpha")
    fadeInAlpha:SetFromAlpha(0)
    fadeInAlpha:SetToAlpha(1)
    fadeInAlpha:SetDuration(0.35)
    fadeIn:SetScript("OnFinished", function()
        frame:SetAlpha(1)
    end)
    frame.fadeIn = fadeIn

    local fadeOut = frame:CreateAnimationGroup()
    local fadeOutAlpha = fadeOut:CreateAnimation("Alpha")
    fadeOutAlpha:SetFromAlpha(1)
    fadeOutAlpha:SetToAlpha(0)
    fadeOutAlpha:SetDuration(0.25)
    fadeOut:SetScript("OnFinished", function()
        frame:Hide()
        frame:SetAlpha(1)
    end)
    frame.fadeOut = fadeOut

    frame:SetScript("OnShow", function()
        AFK:StartTicker()
        AFK:UpdateDisplay()
    end)

    frame:SetScript("OnHide", function()
        AFK:StopTicker()
        if AFK.preview then
            AFK.preview = false
            AFK.afkStartedAt = nil
        end
    end)

    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = "RapzoQoLAFKFrame"
    end

    self.frame = frame
    return frame
end

function AFK:ApplyTheme()
    local frame = self.frame
    if not frame then return end

    local r, g, b = getAccentColor()
    local sr, sg, sb = liftColor(r, g, b, 0.18)

    if frame.card then
        frame.card:SetBackdropBorderColor(r, g, b, 0.22)
    end
    if frame.topLine then
        frame.topLine:SetColorTexture(r, g, b, 0.72)
    end
    if frame.accent then
        frame.accent:SetColorTexture(r, g, b, 0.62)
    end
    if frame.timer then
        frame.timer:SetTextColor(sr, sg, sb)
    end
    if frame.title then
        frame.title:SetText("|cff" .. accentHex(sr, sg, sb) .. "RAPZO|r |cffF4F7FBQoL|r")
    end
end

function AFK:UpdateDisplay()
    local frame = self:CreateFrame()
    local cfg = getConfig()

    frame.background:SetColorTexture(DARK.screen[1], DARK.screen[2], DARK.screen[3], math.min(0.82, cfg.opacity * 0.92))
    if frame.card then
        frame.card:SetBackdropColor(DARK.card[1], DARK.card[2], DARK.card[3], math.min(0.92, 0.76 + (cfg.opacity * 0.16)))
    end
    self:ApplyTheme()

    local playerName = RB:GetPlayerNameSafe()
    local realmName = RB:GetRealmNameSafe()
    local specName = getSpecName()
    local classFile = getClassFile()

    local r, g, b = 0.92, 0.96, 1.00
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local color = RAID_CLASS_COLORS[classFile]
        r, g, b = color.r or r, color.g or g, color.b or b

        -- Preserve Blizzard class color but lift it toward white so every
        -- class remains readable over the dark AFK card.
        local lift = 0.28
        r = r + ((1 - r) * lift)
        g = g + ((1 - g) * lift)
        b = b + ((1 - b) * lift)
    end

    frame.character:SetShown(cfg.showCharacter ~= false)
    frame.detail:SetShown(cfg.showCharacter ~= false)
    if cfg.showCharacter ~= false then
        frame.character:SetText(string.upper(tostring(playerName or "Player")))
        frame.character:SetTextColor(r, g, b)
        local details = {}
        if specName and specName ~= "" then details[#details + 1] = specName end
        if realmName and realmName ~= "" then details[#details + 1] = tostring(realmName) end
        frame.detail:SetText(table.concat(details, " · "))
    end

    frame.zone:SetShown(cfg.showZone ~= false)
    if cfg.showZone ~= false then
        frame.zone:SetText(getZoneText())
    end

    frame.timer:SetShown(cfg.showTimer ~= false)
    if cfg.showTimer ~= false then
        local startedAt = self.afkStartedAt or (type(GetTime) == "function" and GetTime() or 0)
        local now = type(GetTime) == "function" and GetTime() or startedAt
        frame.timer:SetText("AFK · " .. formatElapsed(now - startedAt))
    end

    local moneyText = cfg.showMoney and getMoneyText() or nil
    frame.money:SetShown(moneyText ~= nil)
    if moneyText then frame.money:SetText(moneyText) end

    local footerParts = {}
    if cfg.showClock ~= false and type(date) == "function" then
        footerParts[#footerParts + 1] = date("%H:%M")
    end
    footerParts[#footerParts + 1] = "Rapzo QoL " .. tostring(RB.version or "")
    frame.footer:SetText(table.concat(footerParts, "   ·   "))
end

function AFK:StartTicker()
    if self.ticker or not C_Timer or type(C_Timer.NewTicker) ~= "function" then
        return
    end

    self.ticker = C_Timer.NewTicker(1, function()
        if AFK.frame and AFK.frame:IsShown() then
            AFK:UpdateDisplay()
        end
    end)
end

function AFK:StopTicker()
    if self.ticker and type(self.ticker.Cancel) == "function" then
        self.ticker:Cancel()
    end
    self.ticker = nil
end

function AFK:ShowScreen()
    if not self:IsEnabled() then return end

    local cfg = getConfig()
    if cfg.hideInCombat and type(InCombatLockdown) == "function" and InCombatLockdown() then
        return
    end

    local frame = self:CreateFrame()
    if frame.fadeOut and frame.fadeOut:IsPlaying() then frame.fadeOut:Stop() end

    if not frame:IsShown() then
        frame:SetAlpha(1)
        frame:Show()
        if frame.fadeIn then
            frame.fadeIn:Stop()
            frame.fadeIn:Play()
        end
    else
        self:UpdateDisplay()
    end
end

function AFK:HideScreen(immediate)
    local frame = self.frame
    if not frame or not frame:IsShown() then
        self:StopTicker()
        return
    end

    if frame.fadeIn and frame.fadeIn:IsPlaying() then frame.fadeIn:Stop() end

    if immediate then
        if frame.fadeOut and frame.fadeOut:IsPlaying() then frame.fadeOut:Stop() end
        frame:Hide()
        frame:SetAlpha(1)
        return
    end

    if frame.fadeOut and not frame.fadeOut:IsPlaying() then
        frame.fadeOut:Play()
    else
        frame:Hide()
    end
end

function AFK:RefreshState()
    if self.preview then
        return
    end

    if not self:IsEnabled() then
        self.afkStartedAt = nil
        self:HideScreen(true)
        return
    end

    local cfg = getConfig()
    if cfg.hideInCombat and type(InCombatLockdown) == "function" and InCombatLockdown() then
        self.lastStateReason = "combat"
        self:HideScreen(true)
        return
    end

    local isAFK, reason = safeAFKState()
    self.lastStateReason = reason

    -- Retail 12.x can return a secret value for UnitIsAFK during chat
    -- messaging lockdown. Never branch on that secret: keep the current
    -- screen state untouched and retry until the state is readable again.
    if isAFK == nil then
        if not self.secretRetryPending and C_Timer and type(C_Timer.After) == "function" then
            self.secretRetryPending = true
            C_Timer.After(2, function()
                AFK.secretRetryPending = nil
                AFK:RefreshState()
            end)
        end
        return
    end

    if isAFK then
        if not self.afkStartedAt then
            self.afkStartedAt = type(GetTime) == "function" and GetTime() or 0
        end
        self:ShowScreen()
    else
        self.afkStartedAt = nil
        self:HideScreen(false)
    end
end

function AFK:ScheduleRefresh(delay)
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(tonumber(delay) or 0, function()
            AFK:RefreshState()
        end)
    else
        self:RefreshState()
    end
end

function AFK:TogglePreview()
    if self.preview and self.frame and self.frame:IsShown() then
        self.preview = false
        self.afkStartedAt = nil
        self:HideScreen(false)
        return
    end

    if not self:IsEnabled() then
        RB:Print("Pantalla AFK desactivada. Usa /rapzo afk on.")
        return
    end

    local cfg = getConfig()
    if cfg.hideInCombat and type(InCombatLockdown) == "function" and InCombatLockdown() then
        RB:Print("La vista previa AFK no puede abrirse en combate.")
        return
    end

    self.preview = true
    self.afkStartedAt = type(GetTime) == "function" and GetTime() or 0
    self:ShowScreen()

    if self.frame and self.frame:IsShown() then
        RB:Print("Vista previa AFK activa. Pulsa ESC o repite /rapzo afk preview para salir.")
    else
        -- ShowScreen refused to show (state changed between the checks).
        -- Never leave the preview flag armed with no visible screen: it would
        -- suppress the real AFK screen for the rest of the session.
        self.preview = false
        self.afkStartedAt = nil
        RB:Print("La vista previa AFK no pudo abrirse ahora mismo.")
    end
end

function AFK:HandleSlash(rest)
    rest = tostring(rest or "")
    local command = string.lower(rest:match("^(%S+)") or "")

    if command == "on" then
        self:SetEnabled(true)
        return
    elseif command == "off" then
        self:SetEnabled(false)
        return
    elseif command == "preview" or command == "test" or command == "show" then
        self:TogglePreview()
        return
    elseif command == "hide" then
        self.preview = false
        self.afkStartedAt = nil
        self:HideScreen(false)
        return
    elseif command == "status" or command == "" then
        local state, reason = safeAFKState()
        local stateText
        if state == nil then
            stateText = "RESTRINGIDO (" .. tostring(reason or "unknown") .. ")"
        else
            stateText = state and "AFK" or "ACTIVO"
        end
        RB:Print(string.format(
            "AFK Screen: %s | jugador: %s | visible: %s",
            self:IsEnabled() and "ON" or "OFF",
            stateText,
            self.frame and self.frame:IsShown() and "SI" or "NO"
        ))
        return
    end

    RB:Print("Uso: /rapzo afk [status|on|off|preview|hide]")
end

function AFK:Initialize()
    if self.initialized then return end
    self.initialized = true

    getConfig()
    self:CreateFrame()

    local events = CreateFrame("Frame")
    self.eventFrame = events

    local function register(event)
        pcall(events.RegisterEvent, events, event)
    end

    register("PLAYER_LOGIN")
    register("PLAYER_ENTERING_WORLD")
    register("PLAYER_FLAGS_CHANGED")
    register("PLAYER_REGEN_DISABLED")
    register("PLAYER_REGEN_ENABLED")
    register("ZONE_CHANGED_NEW_AREA")

    events:SetScript("OnEvent", function(_, event, unitTarget)
        if event == "PLAYER_FLAGS_CHANGED" then
            if isSecret(unitTarget) then
                -- The event cannot be attributed to a unit (it may be a
                -- groupmate's flags). Do not hide a legitimately visible AFK
                -- screen; re-evaluate shortly instead.
                AFK.lastStateReason = "secret-event"
                AFK:ScheduleRefresh(1)
                return
            end
            if unitTarget ~= "player" then return end
            AFK:RefreshState()
            return
        end

        if event == "PLAYER_REGEN_DISABLED" then
            if getConfig().hideInCombat then
                AFK.lastStateReason = "combat"
                AFK:HideScreen(true)
            end
            return
        end

        AFK:ScheduleRefresh(event == "PLAYER_ENTERING_WORLD" and 0.35 or 0.05)
    end)

    self:ScheduleRefresh(0.5)
end

RB:RegisterCommand("afk", function(rest) AFK:HandleSlash(rest) end, "/rapzo afk [status|on|off|preview|hide] - configura la pantalla AFK")
AFK:Initialize()
