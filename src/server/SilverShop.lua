-- The original module/store names preserve existing treadmill purchases.
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Config = require(script.Parent.ShopConfig)
local TrailCatalog = require(game:GetService("ReplicatedStorage"):WaitForChild("TrailCatalog"))
local store = DataStoreService:GetDataStore("MazeQuestSilverV1")
local Shop = {}
local ready, enabled, pending, usingSkip, revisions = {}, {}, {}, {}, {}
local offers, treadmills = {}, {}
local byKey, byProduct = {}, {}
local changed, lastLevel, rewards
local buyingTrail = {}
local trailsByKey = {}
for _, trail in ipairs(TrailCatalog) do trailsByKey[trail.Key] = trail end
local function add(offer)
    table.insert(offers, offer)
    byKey[offer.Key] = offer
    if offer.ProductId > 0 then
        assert(not byProduct[offer.ProductId], "Each shop product needs a different Product ID")
        byProduct[offer.ProductId] = offer
    end
end
for _, key in ipairs({"Silver", "Gold", "God"}) do
    local offer = {
        Key = key, Label = key .. " treadmill", Kind = "Treadmill",
        ProductId = Config[key .. "TreadmillProductId"],
        Price = Config[key .. "TreadmillPrice"],
        Multiplier = Config[key .. "Multiplier"], Attribute = key .. "TreadmillOwned",
    }
    add(offer)
    table.insert(treadmills, offer)
end
add({Key = "MillionSpeed", Label = "1m speed", Kind = "Speed", ProductId = Config.MillionSpeedProductId})
add({Key = "SkipLevel", Label = "Skip level", Kind = "Skip", ProductId = Config.SkipLevelProductId})

function Shop.offers() return treadmills end
function Shop.multiplier(player)
    local multiplier = 1
    for _, offer in ipairs(treadmills) do
        if player:GetAttribute(offer.Attribute) then multiplier = math.max(multiplier, offer.Multiplier) end
    end
    return multiplier
end
function Shop.baseSpeed(player, trainedSpeed)
    if player:GetAttribute("MillionSpeedOwned") then return math.max(trainedSpeed, Config.MillionSpeedAmount) end
    return trainedSpeed
end

-- A stale join read must not overwrite a receipt or a consumed skip credit.
local function merge(player, data)
    if not player or not player.Parent then return end
    data = data or {}
    local revision = data.Revision or 0
    if revision < (revisions[player] or 0) then return end
    revisions[player] = revision
    for _, offer in ipairs(treadmills) do
        if data[offer.Key] then player:SetAttribute(offer.Attribute, true) end
    end
    if data.MillionSpeed then player:SetAttribute("MillionSpeedOwned", true) end
    player:SetAttribute("SkipCredits", data.SkipCredits or 0)
    player:SetAttribute("PurchasedCheckpoint", data.PaidCheckpoint or 1)
    player:SetAttribute("Wins", data.Wins or 0)
    player:SetAttribute("UnlockedLevel", math.min(lastLevel, math.max(data.UnlockedLevel or 1, data.PaidCheckpoint or 1)))
    player:SetAttribute("SkipUses", data.SkipUses or 0)
    player:SetAttribute("EquippedTrail", data.EquippedTrail or "")
    for _, trail in ipairs(TrailCatalog) do
        player:SetAttribute("OwnsTrail_" .. trail.Key, data.Trails and data.Trails[trail.Key] or false)
    end
    ready[player] = true
    player:SetAttribute("ShopReady", true)
    changed(player)
end

-- Skip credits and their destination are committed together. A disconnect after
-- this write restores the paid destination on the next join instead of losing it.
function Shop.useSkip(player, purchaseId)
    local level = player:GetAttribute("CurrentMazeLevel")
    if not ready[player] or usingSkip[player] or player:GetAttribute("StageTransition") or not level or level < 1 or level > lastLevel then return end
    local entryId = player:GetAttribute("StageEntryId")
    usingSkip[player] = true
    player:SetAttribute("SkipTransition", true)
    local ok, data = pcall(function()
        return store:UpdateAsync(tostring(player.UserId), function(previous)
            previous = previous or {}
            local selected = purchaseId
            if not selected then
                for id, status in pairs(previous.SkipReceipts or {}) do
                    if status == "pending" then selected = id; break end
                end
            end
            if selected and previous.SkipReceipts and previous.SkipReceipts[selected] == "pending" and (previous.SkipCredits or 0) > 0 then
                local checkpoint = level
                if checkpoint <= lastLevel then
                    previous.SkipCredits = previous.SkipCredits - 1
                    previous.PaidCheckpoint = math.max(previous.PaidCheckpoint or 1, checkpoint + 1)
                    previous.UnlockedLevel = math.max(previous.UnlockedLevel or 1, math.min(checkpoint + 1, lastLevel))
                    previous.SkipUses = (previous.SkipUses or 0) + 1
                    previous.StageRewards = previous.StageRewards or {}
                    if not entryId or not previous.StageRewards[entryId] then
                        previous.Wins = (previous.Wins or 0) + (rewards[checkpoint] or 0)
                        if entryId then previous.StageRewards[entryId] = checkpoint end
                    end
                    previous.SkipReceipts[selected] = checkpoint + 1
                    previous.Revision = (previous.Revision or 0) + 1
                end
            end
            return previous
        end)
    end)
    usingSkip[player] = nil
    player:SetAttribute("SkipTransition", false)
    if ok then merge(player, data)
    else player:SetAttribute("ShopMessage", "Skip is saved. Please try using your credit again.") end
end

function Shop.start(onChanged, levelCount, onCatalogChanged, stageRewards)
    changed, lastLevel, rewards = onChanged, levelCount, stageRewards or {}
    MarketplaceService.ProcessReceipt = function(receipt)
        local offer = byProduct[receipt.ProductId]
        if not offer then return Enum.ProductPurchaseDecision.NotProcessedYet end
        if offer.Kind == "Skip" and (type(receipt.PurchaseId) ~= "string" or receipt.PurchaseId == "") then
            return Enum.ProductPurchaseDecision.NotProcessedYet
        end
        local ok, data = pcall(function()
            return store:UpdateAsync(tostring(receipt.PlayerId), function(previous)
                previous = previous or {}
                if offer.Kind == "Skip" then
                    previous.SkipReceipts = previous.SkipReceipts or {}
                    if not previous.SkipReceipts[receipt.PurchaseId] then
                        previous.SkipReceipts[receipt.PurchaseId] = "pending"
                        previous.SkipCredits = (previous.SkipCredits or 0) + 1
                    end
                else
                    previous[offer.Key] = true
                end
                previous.Revision = (previous.Revision or 0) + 1
                return previous
            end)
        end)
        if not ok or not data then return Enum.ProductPurchaseDecision.NotProcessedYet end
        local granted = offer.Kind == "Skip" and data.SkipReceipts and data.SkipReceipts[receipt.PurchaseId] or data[offer.Key]
        if not granted then return Enum.ProductPurchaseDecision.NotProcessedYet end
        local player = Players:GetPlayerByUserId(receipt.PlayerId)
        if player then
            if pending[player] == receipt.ProductId then pending[player] = nil end
            merge(player, data)
            -- Only a newly available credit can advance; duplicate receipts after
            -- consumption see zero credits and cannot advance a second time.
            if offer.Kind == "Skip" then Shop.useSkip(player, receipt.PurchaseId) end
        end
        return Enum.ProductPurchaseDecision.PurchaseGranted
    end
    MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
        local player = Players:GetPlayerByUserId(userId)
        if player and pending[player] == productId and not purchased then pending[player] = nil end
        -- A checkout closing never grants anything. Paid checkouts remain pending
        -- until their receipt is stored, preventing another charge while retrying.
    end)
    for _, offer in ipairs(offers) do
        if offer.ProductId > 0 then
            task.spawn(function()
                local ok, info = pcall(function()
                    return MarketplaceService:GetProductInfo(offer.ProductId, Enum.InfoType.Product)
                end)
                local valid = ok and type(info) == "table" and type(info.PriceInRobux) == "number" and info.PriceInRobux >= 0
                if valid and offer.Kind ~= "Treadmill" then offer.Price = info.PriceInRobux end
                enabled[offer.Key] = valid and info.PriceInRobux == offer.Price
                if onCatalogChanged then onCatalogChanged(offer, enabled[offer.Key]) end
                if not enabled[offer.Key] then warn(offer.Label .. " disabled: verify its Product ID and price.") end
            end)
        end
    end
end

function Shop.load(player)
    player:SetAttribute("ShopReady", false)
    for _, offer in ipairs(treadmills) do player:SetAttribute(offer.Attribute, false) end
    player:SetAttribute("MillionSpeedOwned", false)
    player:SetAttribute("SkipCredits", 0)
    task.spawn(function()
        local ok, data = pcall(function() return store:GetAsync(tostring(player.UserId)) end)
        if not player.Parent then return end
        if ok then merge(player, data)
        else warn("Shop ownership could not load; purchases are disabled for this player.") end
    end)
end

function Shop.prompt(player, key)
    local offer = byKey[key]
    if not offer then return end
    player:SetAttribute("EconomyMessage", nil)
    if offer.Kind == "Treadmill" and Shop.multiplier(player) >= offer.Multiplier then
        player:SetAttribute("ShopMessage", "Your active boost is already equal to or higher than this treadmill.")
        return
    end
    if key == "MillionSpeed" and player:GetAttribute("MillionSpeedOwned") then
        player:SetAttribute("ShopMessage", "Your permanent 1,000,000 base speed is already active.")
        return
    end
    if key == "SkipLevel" then
        local level = player:GetAttribute("CurrentMazeLevel")
        if not level or level < 1 or level > lastLevel or player:GetAttribute("StageTransition") then return end
        if (player:GetAttribute("SkipCredits") or 0) > 0 then Shop.useSkip(player); return end
    end
    if not enabled[key] or not ready[player] then
        player:SetAttribute("ShopMessage", offer.Label .. " unavailable. Product setup or ownership loading is incomplete.")
        return
    end
    if pending[player] then return end
    pending[player] = offer.ProductId
    player:SetAttribute("ShopMessage", "Confirm " .. offer.Price .. " Robux in Roblox to purchase " .. offer.Label .. ".")
    local ok = pcall(function() MarketplaceService:PromptProductPurchase(player, offer.ProductId) end)
    if not ok then
        pending[player] = nil
        player:SetAttribute("ShopMessage", "Purchase prompt unavailable. Please try again later.")
    end
end

-- Called only by the server after validating a stage's reward pad. Entry IDs
-- come from the server; a retried save cannot pay for the same completion twice.
function Shop.completeStage(player, entryId, stage)
    if not ready[player] or type(entryId) ~= "string" or entryId == "" then return false end
    if type(stage) ~= "number" or stage % 1 ~= 0 or stage < 1 or stage > lastLevel then return false end
    if player:GetAttribute("CurrentMazeLevel") ~= stage then return false end
    local ok, data = pcall(function()
        return store:UpdateAsync(tostring(player.UserId), function(previous)
            previous = previous or {}
            previous.StageRewards = previous.StageRewards or {}
            if not previous.StageRewards[entryId] then
                previous.StageRewards[entryId] = stage
                previous.Wins = (previous.Wins or 0) + (rewards[stage] or 0)
                previous.UnlockedLevel = math.max(previous.UnlockedLevel or 1, math.min(stage + 1, lastLevel))
                previous.Revision = (previous.Revision or 0) + 1
            end
            return previous
        end)
    end)
    if not ok or not data or not data.StageRewards or data.StageRewards[entryId] ~= stage then
        player:SetAttribute("EconomyMessage", "Reward save unavailable. Step off the button and try again.")
        return false
    end
    merge(player, data)
    player:SetAttribute("EconomyMessage", "+" .. (rewards[stage] or 0) .. " wins for Level " .. stage .. "!")
    return true
end

-- The server uses catalog prices and stored balances; clients never submit costs
-- or currency amounts. Ownership, spending, and equipment commit in one write.
function Shop.selectTrail(player, key, action)
    local trail = trailsByKey[key]
    if not trail or not ready[player] or buyingTrail[player] then return false end
    if action ~= "Buy" and action ~= "Equip" and action ~= "Unequip" then return false end
    buyingTrail[player] = true
    local ok, data = pcall(function()
        return store:UpdateAsync(tostring(player.UserId), function(previous)
            previous = previous or {}
            previous.Trails = previous.Trails or {}
            if action == "Unequip" then
                if previous.EquippedTrail == key then previous.EquippedTrail = "" end
            else
                if not previous.Trails[key] then
                    if action ~= "Buy" or (previous.Wins or 0) < trail.Price then return previous end
                    previous.Wins = previous.Wins - trail.Price
                    previous.Trails[key] = true
                end
                previous.EquippedTrail = key
            end
            previous.Revision = (previous.Revision or 0) + 1
            return previous
        end)
    end)
    buyingTrail[player] = nil
    if not ok or not data then
        player:SetAttribute("EconomyMessage", "Trail save unavailable. Please try again.")
        return false
    end
    merge(player, data)
    if action ~= "Unequip" and not (data.Trails and data.Trails[key]) then
        player:SetAttribute("EconomyMessage", action == "Buy" and ("You need " .. trail.Price .. " wins for " .. trail.Name .. ".") or "Buy this trail before equipping it.")
        return false
    end
    player:SetAttribute("EconomyMessage", action == "Unequip" and "Trail removed." or (trail.Name .. " equipped!"))
    return true
end

Players.PlayerRemoving:Connect(function(player)
    ready[player], pending[player], usingSkip[player], revisions[player], buyingTrail[player] = nil, nil, nil, nil, nil
end)
return Shop
