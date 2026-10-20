local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Config = require(script.Parent.ShopConfig)
local store = DataStoreService:GetDataStore("MazeQuestSilverV1")
local Shop = {}
local ready, enabled = {}, false
local changed

-- Permanent entitlement: retrying any receipt sets the same boolean, never
-- multiplies repeatedly. Commit the entitlement before acknowledging payment.
function Shop.start(onChanged)
    changed = onChanged
    if Config.SilverTreadmillProductId <= 0 then return end
    MarketplaceService.ProcessReceipt = function(receipt)
        if receipt.ProductId ~= Config.SilverTreadmillProductId then
            return Enum.ProductPurchaseDecision.NotProcessedYet
        end
        local ok = pcall(function()
            store:UpdateAsync(tostring(receipt.PlayerId), function(data)
                data = data or {}
                data.Silver = true
                return data
            end)
        end)
        if not ok then return Enum.ProductPurchaseDecision.NotProcessedYet end
        local player = Players:GetPlayerByUserId(receipt.PlayerId)
        if player then
            player:SetAttribute("SilverTreadmillOwned", true)
            ready[player] = true
            changed(player)
        end
        return Enum.ProductPurchaseDecision.PurchaseGranted
    end
    task.spawn(function()
        local ok, info = pcall(function()
            return MarketplaceService:GetProductInfo(Config.SilverTreadmillProductId, Enum.InfoType.Product)
        end)
        enabled = ok and info.PriceInRobux == Config.SilverTreadmillPrice
        if not enabled then warn("Silver treadmill purchases disabled: verify Product ID and 15 Robux price.") end
    end)
end

function Shop.load(player)
    player:SetAttribute("SilverTreadmillOwned", false)
    if Config.SilverTreadmillProductId <= 0 then return end
    task.spawn(function()
        local ok, data = pcall(function() return store:GetAsync(tostring(player.UserId)) end)
        if not player.Parent then return end
        if ok then
            -- A receipt may finish while the initial read is in flight.
            if data and data.Silver then player:SetAttribute("SilverTreadmillOwned", true) end
            ready[player] = true
            changed(player)
        else
            warn("Silver treadmill ownership could not load; purchasing is disabled for this player.")
        end
    end)
end

function Shop.prompt(player)
    if player:GetAttribute("SilverTreadmillOwned") then return end
    if not enabled or not ready[player] then
        player:SetAttribute("ShopMessage", "Silver treadmill unavailable. Product setup or ownership loading is incomplete.")
        return
    end
    player:SetAttribute("ShopMessage", "Confirm the 15 Robux purchase in Roblox to unlock the silver treadmill boost.")
    local ok = pcall(function()
        MarketplaceService:PromptProductPurchase(player, Config.SilverTreadmillProductId)
    end)
    if not ok then player:SetAttribute("ShopMessage", "Purchase prompt unavailable. Please try again later.") end
end

function Shop.multiplier(player)
    return player:GetAttribute("SilverTreadmillOwned") and Config.SilverMultiplier or 1
end

Players.PlayerRemoving:Connect(function(player) ready[player] = nil end)
return Shop
