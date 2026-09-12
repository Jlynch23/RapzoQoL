local addonName = ...
local RB = _G.RapzoBags
if not RB or not RB.Vendor then return end

local Vendor = RB.Vendor

-- Compra masiva desde el popup nativo de Shift+Click del vendedor.
-- Blizzard limita ese popup a GetMerchantItemMaxStack(); aqui ampliamos el
-- numero que se puede escribir y dividimos la compra en varias transacciones.
local BulkBuy = {}
Vendor.BulkBuy = BulkBuy

local HARD_LIMIT = 9999
local PURCHASE_INTERVAL = 0.10

BulkBuy.hooked = false
BulkBuy.activePurchase = nil
BulkBuy.purchaseFrame = CreateFrame("Frame")

local function isAddonLoaded(name)
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
        return ok and loaded or false
    end
    if type(IsAddOnLoaded) == "function" then
        local ok, loaded = pcall(IsAddOnLoaded, name)
        return ok and loaded or false
    end
    return false
end

local function isChatEditFocused()
    local editBox = _G.ChatFrame1EditBox
    return editBox and type(editBox.HasFocus) == "function" and editBox:HasFocus()
end

function BulkBuy:GetRealIndex(visibleIndex)
    visibleIndex = tonumber(visibleIndex)
    if not visibleIndex then return nil end

    if Vendor.IsFilterActive and Vendor:IsFilterActive() and Vendor.MapVisibleIndex then
        return Vendor:MapVisibleIndex(visibleIndex)
    end
    return visibleIndex
end

function BulkBuy:GetItemInfo(realIndex, visibleIndex)
    local raw = Vendor.originalAPI and Vendor.originalAPI.CGetItemInfo
    if type(raw) == "function" then
        local ok, info = pcall(raw, realIndex)
        if ok then return info end
    end

    if C_MerchantFrame and type(C_MerchantFrame.GetItemInfo) == "function" then
        local ok, info = pcall(C_MerchantFrame.GetItemInfo, visibleIndex)
        if ok then return info end
    end
    return nil
end

function BulkBuy:GetNativeMax(realIndex, visibleIndex)
    local raw = Vendor.originalAPI and Vendor.originalAPI.GetMerchantItemMaxStack
    local ok, value

    if type(raw) == "function" then
        ok, value = pcall(raw, realIndex)
    elseif type(GetMerchantItemMaxStack) == "function" then
        ok, value = pcall(GetMerchantItemMaxStack, visibleIndex)
    end

    value = ok and tonumber(value) or 0
    value = math.floor(value or 0)
    return math.max(1, value)
end

function BulkBuy:GetBulkMax(realIndex, visibleIndex, info)
    local maxAmount = HARD_LIMIT

    info = info or self:GetItemInfo(realIndex, visibleIndex)
    if not info then return nil end
    if info.isPurchasable == false then return nil end

    -- Las compras con monedas/items alternativos tienen confirmaciones propias
    -- de Blizzard. Por seguridad se dejan con el comportamiento nativo.
    if info.hasExtendedCost then return nil end

    local preset = math.max(1, tonumber(info.stackCount) or 1)
    local price = tonumber(info.price) or 0

    if price > 0 and type(GetMoney) == "function" then
        -- El precio devuelto es por el lote (preset), no necesariamente por 1.
        local unitPrice = math.max(1, math.ceil(price / preset))
        maxAmount = math.min(maxAmount, math.floor(GetMoney() / unitPrice))
    end

    local available = tonumber(info.numAvailable)
    if available and available >= 0 then
        maxAmount = math.min(maxAmount, available)
    end

    return math.max(0, math.floor(maxAmount))
end

function BulkBuy:RawBuy(realIndex, visibleIndex, quantity)
    quantity = math.floor(tonumber(quantity) or 0)
    if quantity <= 0 then return false end

    local raw = Vendor.originalAPI and Vendor.originalAPI.BuyMerchantItem
    if type(raw) == "function" then
        return pcall(raw, realIndex, quantity)
    end

    if type(BuyMerchantItem) == "function" then
        -- Si Vendor ya envolvio la API, debe recibir el indice visible.
        return pcall(BuyMerchantItem, visibleIndex, quantity)
    end
    return false
end

function BulkBuy:StopPurchase()
    self.activePurchase = nil
    if self.purchaseFrame then
        self.purchaseFrame:SetScript("OnUpdate", nil)
    end
end

function BulkBuy:ProcessPurchase(elapsed)
    local state = self.activePurchase
    if not state then
        self:StopPurchase()
        return
    end

    if not MerchantFrame or not MerchantFrame:IsShown() or MerchantFrame.selectedTab ~= 1 then
        self:StopPurchase()
        return
    end

    state.elapsed = (state.elapsed or 0) + (elapsed or 0)
    if state.elapsed < PURCHASE_INTERVAL then return end
    state.elapsed = 0

    local quantity = math.min(state.remaining, state.chunk)
    if quantity <= 0 then
        self:StopPurchase()
        return
    end

    local ok = self:RawBuy(state.realIndex, state.visibleIndex, quantity)
    if not ok then
        self:StopPurchase()
        return
    end

    state.remaining = state.remaining - quantity
    if state.remaining <= 0 then
        self:StopPurchase()
    end
end

function BulkBuy:Purchase(button, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 or not button then return end

    local visibleIndex = tonumber(button.RapzoQoLBulkVisibleIndex) or tonumber(button:GetID())
    local realIndex = tonumber(button.RapzoQoLBulkRealIndex) or self:GetRealIndex(visibleIndex)
    if not visibleIndex or not realIndex then return end

    local info = self:GetItemInfo(realIndex, visibleIndex)
    if not info or info.hasExtendedCost then
        local original = button.RapzoQoLOriginalSplitStack
        if type(original) == "function" then
            return original(button, amount)
        end
        return
    end

    local maxAmount = self:GetBulkMax(realIndex, visibleIndex, info)
    if maxAmount then
        amount = math.min(amount, maxAmount)
    end
    if amount <= 0 then return end

    local nativeMax = self:GetNativeMax(realIndex, visibleIndex)
    if amount <= nativeMax then
        self:RawBuy(realIndex, visibleIndex, amount)
        return
    end

    -- Una compra por tick evita inundar al servidor y sigue el enfoque de los
    -- addons de compra masiva actuales. La primera unidad se procesa enseguida.
    self:StopPurchase()
    self.activePurchase = {
        realIndex = realIndex,
        visibleIndex = visibleIndex,
        remaining = amount,
        chunk = nativeMax,
        elapsed = PURCHASE_INTERVAL,
    }

    self.purchaseFrame:SetScript("OnUpdate", function(_, elapsed)
        BulkBuy:ProcessPurchase(elapsed)
    end)
end

function BulkBuy:PrepareButton(button, realIndex, visibleIndex)
    if not button then return end

    if not button.RapzoQoLOriginalSplitStack then
        button.RapzoQoLOriginalSplitStack = button.SplitStack
    end

    button.RapzoQoLBulkRealIndex = realIndex
    button.RapzoQoLBulkVisibleIndex = visibleIndex
    button.SplitStack = function(owner, amount)
        BulkBuy:Purchase(owner, amount)
    end
end

function BulkBuy:OnModifiedClick(button)
    if not button or not MerchantFrame or MerchantFrame.selectedTab ~= 1 then return end
    if not RB:IsFeatureEnabled("vendor") then return end
    if not IsModifiedClick or not IsModifiedClick("SPLITSTACK") then return end
    if isChatEditFocused() then return end

    -- Evita doble interfaz si el usuario tiene BuyEmAll instalado.
    if isAddonLoaded("BuyEmAll") then return end

    local visibleIndex = tonumber(button:GetID())
    local realIndex = self:GetRealIndex(visibleIndex)
    if not realIndex then return end

    local info = self:GetItemInfo(realIndex, visibleIndex)
    if not info or info.hasExtendedCost then return end

    local nativeMax = self:GetNativeMax(realIndex, visibleIndex)
    local bulkMax = self:GetBulkMax(realIndex, visibleIndex, info)
    if not bulkMax or bulkMax <= nativeMax or bulkMax <= 1 then return end

    self:PrepareButton(button, realIndex, visibleIndex)

    -- El handler nativo ya abrio StackSplitFrame usando nativeMax. Solo
    -- ampliamos su maximo; el aspecto y controles siguen siendo los de Blizzard.
    if type(UpdateStackSplitFrame) == "function" then
        pcall(UpdateStackSplitFrame, bulkMax)
    elseif type(OpenStackSplitFrame) == "function" then
        pcall(OpenStackSplitFrame, bulkMax, button, "BOTTOMLEFT", "TOPLEFT")
    end
end

function BulkBuy:TryHook()
    if self.hooked then return true end
    if type(MerchantItemButton_OnModifiedClick) ~= "function" then return false end
    if type(hooksecurefunc) ~= "function" then return false end

    hooksecurefunc("MerchantItemButton_OnModifiedClick", function(button)
        BulkBuy:OnModifiedClick(button)
    end)
    self.hooked = true
    return true
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("MERCHANT_CLOSED")
events:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_CLOSED" then
        BulkBuy:StopPurchase()
        return
    end

    if BulkBuy:TryHook() then
        events:UnregisterEvent("ADDON_LOADED")
        events:UnregisterEvent("PLAYER_LOGIN")
    end
end)

BulkBuy:TryHook()
