-- Handles every paid treadmill. Retains the original module and DataStore names
-- so existing silver owners keep their purchases.
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Config = require(script.Parent.ShopConfig)
local store = DataStoreService:GetDataStore("MazeQuestSilverV1")
local Shop = {}
local ready, enabled, pending = {}, {}, {}
local offers = {}
local byKey, byProduct = {}, {}
for _, key in ipairs({"Silver", "Gold", "God"}) do
    local offer = {
        Key = key,
        ProductId = Config[key .. "TreadmillProductId"],
        Price = Config[key .. "TreadmillPrice"],
        Multiplier = Config[key .. "Multiplier"],
        Attribute = key .. "TreadmillOwned",
    }
    table.insert(offers, offer)
    byKey[key] = offer
    if offer.ProductId > 0 then
        assert(not byProduct[offer.ProductId], "Each treadmill needs a different Product ID")
        byProduct[offer.ProductId] = offer
    end
end

function Shop.offers()
    return offers
end

function Shop.multiplier(player)
    local multiplier = 1
    for _, offer in ipairs(offers) do
        if player:GetAttribute(offer.Attribute) then multiplier = math.max(multiplier, offer.Multiplier) end
    end
    return multiplier
end

-- Permanent entitlements make receipt retries idempotent. Store the purchase
-- before acknowledging it; retain all other owned tiers in the same record.
function Shop.start(onChanged)
    MarketplaceService.ProcessReceipt = function(receipt)
        local offer = byProduct[receipt.ProductId]
        if not offer then return Enum.ProductPurchaseDecision.NotProcessedYet end
        local ok, data = pcall(function()
            return store:UpdateAsync(tostring(receipt.PlayerId), function(previous)
                previous = previous or {}
                previous[offer.Key] = true
                return previous
            end)
        end)
        if not ok or not data or not data[offer.Key] then
            return Enum.ProductPurchaseDecision.NotProcessedYet
        end
        local player = Players:GetPlayerByUserId(receipt.PlayerId)
        if player then
            -- Merge every entitlement returned by the atomic write.
            for _, tier in ipairs(offers) do
                if data[tier.Key] then player:SetAttribute(tier.Attribute, true) end
            end
            ready[player] = true
            if pending[player] == receipt.ProductId then pending[player] = nil end
            onChanged(player)
        end
        return Enum.ProductPurchaseDecision.PurchaseGranted
    end
    MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
        local player = Players:GetPlayerByUserId(userId)
        if player and pending[player] == productId and not purchased then pending[player] = nil end
        -- Keep a paid checkout pending until its receipt is stored, preventing
        -- another charge while acknowledgment is still being retried.
        -- Closing a checkout, including a successful one, never grants a boost.
    end)
    for _, offer in ipairs(offers) do
        if offer.ProductId > 0 then
            task.spawn(function()
                local ok, info = pcall(function()
                    return MarketplaceService:GetProductInfo(offer.ProductId, Enum.InfoType.Product)
                end)
                enabled[offer.Key] = ok and info.PriceInRobux == offer.Price
                if not enabled[offer.Key] then
                    warn(offer.Key .. " treadmill disabled: verify its Product ID and " .. offer.Price .. " Robux price.")
                end
            end)
        end
    end
    Shop.changed = onChanged
end

function Shop.load(player)
    for _, offer in ipairs(offers) do player:SetAttribute(offer.Attribute, false) end
    task.spawn(function()
        local ok, data = pcall(function() return store:GetAsync(tostring(player.UserId)) end)
        if not player.Parent then return end
        if ok then
            -- Never clear an entitlement granted while this read was in flight.
            for _, offer in ipairs(offers) do
                if data and data[offer.Key] then player:SetAttribute(offer.Attribute, true) end
            end
            ready[player] = true
            Shop.changed(player)
        else
            warn("Treadmill ownership could not load; purchases are disabled for this player.")
        end
    end)
end

function Shop.prompt(player, key)
    local offer = byKey[key]
    if not offer then return end
    if Shop.multiplier(player) >= offer.Multiplier then
        player:SetAttribute("ShopMessage", "Your active boost is already equal to or higher than this treadmill.")
        return
    end
    if not enabled[key] or not ready[player] then
        player:SetAttribute("ShopMessage", key .. " treadmill unavailable. Product setup or ownership loading is incomplete.")
        return
    end
    if pending[player] then return end
    pending[player] = offer.ProductId
    player:SetAttribute("ShopMessage", "Confirm " .. offer.Price .. " Robux in Roblox to unlock " .. key .. " (" .. offer.Multiplier .. "x). Highest owned boost applies.")
    local ok = pcall(function()
        MarketplaceService:PromptProductPurchase(player, offer.ProductId)
    end)
    if not ok then
        pending[player] = nil
        player:SetAttribute("ShopMessage", "Purchase prompt unavailable. Please try again later.")
    end
end

Players.PlayerRemoving:Connect(function(player)
    ready[player], pending[player] = nil, nil
end)
return Shop
