-- Run from the repository root with Lua 5.3+ or fengari tests/shop_spec.lua.
-- Roblox services are mocked; no purchases or network requests are made.
local function signal()
    local result = {callbacks = {}}
    function result:Connect(callback) table.insert(self.callbacks, callback) end
    function result:Fire(...)
        for _, callback in ipairs(self.callbacks) do callback(...) end
    end
    return result
end

local function fixture(options)
    options = options or {}
    local config = dofile("src/server/ShopConfig.lua")
    local trailCatalog = dofile("src/shared/TrailCatalog.lua")
    if not options.actualIds then
        config.GoldTreadmillProductId, config.GodTreadmillProductId = 101, 102
    end
    if options.disableNewProducts then
        config.GoldTreadmillProductId, config.GodTreadmillProductId = 0, 0
    end
    local players = {PlayerRemoving = signal(), users = {}}
    function players:GetPlayerByUserId(id) return self.users[id] end
    local store = {profiles = {}, failWrite = false, failRead = false, writes = 0}
    function store:UpdateAsync(key, callback)
        self.writes = self.writes + 1
        if self.failWrite or self.writes == self.failOnWrite then error("write unavailable") end
        self.profiles[key] = callback(self.profiles[key])
        if self.writes == self.failAfterCommit then error("response lost after commit") end
        return self.profiles[key]
    end
    function store:GetAsync(key)
        if self.failRead then error("read unavailable") end
        if self.onRead then return self.onRead(key) end
        return self.profiles[key]
    end
    local market = {PromptProductPurchaseFinished = signal(), prompts = {}}
    function market:GetProductInfo(id)
        local prices = {[config.SilverTreadmillProductId] = 15, [config.GoldTreadmillProductId] = 30, [config.GodTreadmillProductId] = 50}
        prices[config.MillionSpeedProductId] = 60
        prices[config.SkipLevelProductId] = 20
        if options.extraPricesUnavailable and (id == config.MillionSpeedProductId or id == config.SkipLevelProductId) then error("catalog unavailable") end
        return {PriceInRobux = options.wrongPrice and 999 or prices[id]}
    end
    function market:PromptProductPurchase(player, id)
        table.insert(self.prompts, {player, id})
    end
    local services = {
        Players = players,
        ReplicatedStorage = {WaitForChild = function(_, name) assert(name == "TrailCatalog"); return "trails" end},
        MarketplaceService = market,
        DataStoreService = {GetDataStore = function(_, name)
            assert(name == "MazeQuestSilverV1", "existing ownership store must be retained")
            return store
        end},
    }
    game = {GetService = function(_, name) return services[name] end}
    script = {Parent = {ShopConfig = "config"}}
    require = function(name)
        if name == "trails" then return trailCatalog end
        assert(name == "config"); return config
    end
    task = {spawn = function(callback) callback() end}
    warn = function() end
    Enum = {InfoType = {Product = "product"}, ProductPurchaseDecision = {NotProcessedYet = "retry", PurchaseGranted = "granted"}}
    local shop = dofile("src/server/SilverShop.lua")
    local changes = 0
    local catalog = {}
    shop.start(function(p)
        changes = changes + 1
        local checkpoint = p:GetAttribute("PurchasedCheckpoint") or 1
        if checkpoint > (p:GetAttribute("CurrentMazeLevel") or 1) then
            p:SetAttribute("CurrentMazeLevel", checkpoint)
        end
    end, 7, function(offer, available)
        catalog[offer.Key] = {Price = offer.Price, Available = available}
    end, {0, 1, 5, 15, 50, 100, 200})
    local function player(id)
        local p = {UserId = id, Parent = true, attributes = {CurrentMazeLevel = 1}}
        function p:SetAttribute(name, value) self.attributes[name] = value end
        function p:GetAttribute(name) return self.attributes[name] end
        players.users[id] = p
        return p
    end
    local function receipt(id, productId, purchaseId)
        return market.ProcessReceipt({PlayerId = id, ProductId = productId, PurchaseId = purchaseId or ("purchase-" .. id .. "-" .. productId)})
    end
    return {shop = shop, player = player, store = store, market = market, receipt = receipt, config = config, players = players, catalog = catalog}
end

local tests = {
    {"gold grants only after durable receipt and retries do not stack", function()
        local f = fixture(); local p = f.player(1); f.shop.load(p)
        f.shop.prompt(p, "Gold")
        assert(#f.market.prompts == 1 and f.shop.multiplier(p) == 1)
        f.store.failWrite = true
        assert(f.receipt(1, 101) == "retry" and f.shop.multiplier(p) == 1)
        f.store.failWrite = false
        assert(f.receipt(1, 101) == "granted" and f.store.profiles["1"].Gold)
        assert(f.shop.multiplier(p) == 5)
        assert(f.receipt(1, 101) == "granted" and f.shop.multiplier(p) == 5)
    end},
    {"highest tier wins even if lower receipts arrive later", function()
        local f = fixture(); local p = f.player(2); f.shop.load(p)
        assert(f.receipt(2, 102) == "granted" and f.shop.multiplier(p) == 99)
        f.receipt(2, 101); f.receipt(2, f.config.SilverTreadmillProductId)
        assert(f.shop.multiplier(p) == 99)
        f.shop.prompt(p, "Gold"); f.shop.prompt(p, "God"); f.shop.prompt(p, "Silver")
        assert(#f.market.prompts == 0)
    end},
    {"cancelled checkout grants nothing and permits retry", function()
        local f = fixture(); local p = f.player(3); f.shop.load(p)
        f.shop.prompt(p, "Gold"); f.shop.prompt(p, "God")
        assert(#f.market.prompts == 1)
        f.market.PromptProductPurchaseFinished:Fire(3, 101, false)
        assert(f.shop.multiplier(p) == 1)
        f.shop.prompt(p, "God"); assert(#f.market.prompts == 2)
        f.market.PromptProductPurchaseFinished:Fire(3, 102, true)
        assert(f.shop.multiplier(p) == 1, "checkout closure must not grant ownership")
        f.shop.prompt(p, "God")
        assert(#f.market.prompts == 2, "paid checkout must wait for receipt before another prompt")
        f.receipt(3, 102); assert(f.shop.multiplier(p) == 99)
    end},
    {"rejoining restores legacy silver and new entitlements", function()
        local f = fixture(); f.store.profiles["4"] = {Silver = true}
        local p = f.player(4); f.shop.load(p); assert(f.shop.multiplier(p) == 2.5)
        f.receipt(4, 101); f.receipt(4, 102)
        local rejoined = f.player(4); f.shop.load(rejoined)
        assert(f.shop.multiplier(rejoined) == 99 and rejoined:GetAttribute("SilverTreadmillOwned"))
    end},
    {"failed ownership reads block purchases", function()
        local f = fixture(); f.store.failRead = true
        local p = f.player(5); f.shop.load(p); f.shop.prompt(p, "Gold")
        assert(#f.market.prompts == 0)
    end},
    {"wrong prices block purchases", function()
        local f = fixture({wrongPrice = true}); local p = f.player(6)
        f.shop.load(p); f.shop.prompt(p, "Gold"); f.shop.prompt(p, "God")
        assert(#f.market.prompts == 0)
    end},
    {"unknown products remain unacknowledged", function()
        local f = fixture(); assert(f.receipt(7, 987654) == "retry")
        assert(f.store.profiles["7"] == nil)
    end},
    {"offline purchases persist for next join", function()
        local f = fixture(); assert(f.receipt(8, 102) == "granted")
        local p = f.player(8); f.shop.load(p); assert(f.shop.multiplier(p) == 99)
    end},
    {"in-flight stale ownership read cannot erase a new purchase", function()
        local f = fixture(); local p = f.player(9)
        f.store.onRead = function() f.receipt(9, 102); return {} end
        f.shop.load(p); assert(f.shop.multiplier(p) == 99)
    end},
    {"unconfigured gold and god products remain disabled", function()
        local f = fixture({disableNewProducts = true}); local p = f.player(10); f.shop.load(p)
        f.shop.prompt(p, "Gold"); f.shop.prompt(p, "God")
        assert(#f.market.prompts == 0)
        f.shop.prompt(p, "Silver"); assert(#f.market.prompts == 1)
    end},
    {"configured gold and god products route prompts and receipt grants", function()
        local f = fixture({actualIds = true}); local p = f.player(11); f.shop.load(p)
        for _, key in ipairs({"Gold", "God"}) do
            local id = f.config[key .. "TreadmillProductId"]
            f.shop.prompt(p, key)
            assert(f.market.prompts[#f.market.prompts][2] == id)
            assert(f.receipt(11, id) == "granted")
            assert(f.shop.multiplier(p) == f.config[key .. "Multiplier"])
        end
        assert(f.store.profiles["11"].Gold and f.store.profiles["11"].God)
    end},

    {"million speed is permanent, non-stacking, and respects treadmill multipliers", function()
        local f = fixture(); local p = f.player(12); f.shop.load(p)
        f.shop.prompt(p, "MillionSpeed")
        assert(f.market.prompts[1][2] == 3720266025)
        assert(f.shop.baseSpeed(p, 32) == 32)
        assert(f.receipt(12, f.config.MillionSpeedProductId) == "granted")
        assert(f.shop.baseSpeed(p, 32) == 1000000)
        f.receipt(12, f.config.MillionSpeedProductId)
        assert(f.shop.baseSpeed(p, 32) == 1000000)
        f.shop.prompt(p, "MillionSpeed"); assert(#f.market.prompts == 1)
        f.receipt(12, 101)
        assert(f.shop.baseSpeed(p, 16) * f.shop.multiplier(p) == 5000000)
        local rejoined = f.player(12); f.shop.load(rejoined)
        assert(f.shop.baseSpeed(rejoined, 16) == 1000000)
    end},
    {"skip advances once per distinct receipt and restores its destination", function()
        local f = fixture(); local p = f.player(13); f.shop.load(p)
        f.shop.prompt(p, "SkipLevel"); assert(f.market.prompts[1][2] == 3720265823)
        assert(f.receipt(13, f.config.SkipLevelProductId, "skip-a") == "granted")
        assert(p:GetAttribute("CurrentMazeLevel") == 2 and p:GetAttribute("SkipCredits") == 0)
        f.receipt(13, f.config.SkipLevelProductId, "skip-a")
        assert(p:GetAttribute("CurrentMazeLevel") == 2)
        f.receipt(13, f.config.SkipLevelProductId, "skip-b")
        assert(p:GetAttribute("CurrentMazeLevel") == 3)
        local rejoined = f.player(13); f.shop.load(rejoined)
        assert(rejoined:GetAttribute("CurrentMazeLevel") == 3)
    end},
    {"offline skip credit can be consumed later without another checkout", function()
        local f = fixture(); assert(f.receipt(14, f.config.SkipLevelProductId, "offline") == "granted")
        local p = f.player(14); f.shop.load(p)
        assert(p:GetAttribute("SkipCredits") == 1)
        f.shop.prompt(p, "SkipLevel")
        assert(#f.market.prompts == 0 and p:GetAttribute("CurrentMazeLevel") == 2)
        assert(p:GetAttribute("SkipCredits") == 0)
    end},
    {"failed skip consumption retains a paid credit", function()
        local f = fixture(); local p = f.player(15); f.shop.load(p)
        f.store.failOnWrite = 2
        assert(f.receipt(15, f.config.SkipLevelProductId, "saved") == "granted")
        assert(p:GetAttribute("CurrentMazeLevel") == 1 and p:GetAttribute("SkipCredits") == 1)
        f.store.failOnWrite = nil
        f.shop.prompt(p, "SkipLevel")
        assert(p:GetAttribute("CurrentMazeLevel") == 2 and p:GetAttribute("SkipCredits") == 0)
    end},
    {"receipt retry after an ambiguous write grants only one skip", function()
        local f = fixture(); local p = f.player(16); f.shop.load(p)
        f.store.failAfterCommit = 1
        assert(f.receipt(16, f.config.SkipLevelProductId, "retry") == "retry")
        assert(p:GetAttribute("CurrentMazeLevel") == 1)
        f.store.failAfterCommit = nil
        assert(f.receipt(16, f.config.SkipLevelProductId, "retry") == "granted")
        assert(p:GetAttribute("CurrentMazeLevel") == 2 and p:GetAttribute("SkipCredits") == 0)
    end},
    {"retrying a consumed receipt does not consume another paid credit", function()
        local f = fixture(); local p = f.player(17); f.shop.load(p)
        f.receipt(17, f.config.SkipLevelProductId, "used")
        p.Parent = false; f.players.users[17] = nil
        f.receipt(17, f.config.SkipLevelProductId, "banked")
        local rejoined = f.player(17); f.shop.load(rejoined)
        f.receipt(17, f.config.SkipLevelProductId, "used")
        assert(rejoined:GetAttribute("CurrentMazeLevel") == 2 and rejoined:GetAttribute("SkipCredits") == 1)
    end},
    {"skipping the last level wins and completed runs cannot buy more skips", function()
        local f = fixture(); local p = f.player(18); f.shop.load(p)
        p:SetAttribute("CurrentMazeLevel", 7)
        f.receipt(18, f.config.SkipLevelProductId, "last")
        assert(p:GetAttribute("CurrentMazeLevel") == 8)
        f.shop.prompt(p, "SkipLevel"); assert(#f.market.prompts == 0)
    end},
    {"missing receipt IDs are deferred without creating credits", function()
        local f = fixture(); local p = f.player(19); f.shop.load(p)
        assert(f.market.ProcessReceipt({PlayerId = 19, ProductId = f.config.SkipLevelProductId}) == "retry")
        assert(p:GetAttribute("SkipCredits") == 0 and f.store.profiles["19"] == nil)
    end},
    {"new product prices come from Roblox and unavailable products stay disabled", function()
        local f = fixture()
        assert(f.catalog.MillionSpeed.Price == 60 and f.catalog.SkipLevel.Price == 20)
        assert(f.catalog.MillionSpeed.Available and f.catalog.SkipLevel.Available)
        local unavailable = fixture({extraPricesUnavailable = true})
        local p = unavailable.player(20); unavailable.shop.load(p)
        unavailable.shop.prompt(p, "MillionSpeed"); unavailable.shop.prompt(p, "SkipLevel")
        assert(#unavailable.market.prompts == 0)
    end},
    {"consumption committed before disconnect restores the skipped destination", function()
        local f = fixture(); local p = f.player(21); f.shop.load(p)
        f.store.failAfterCommit = 2
        f.receipt(21, f.config.SkipLevelProductId, "disconnect")
        assert(p:GetAttribute("CurrentMazeLevel") == 1)
        f.store.failAfterCommit = nil
        local rejoined = f.player(21); f.shop.load(rejoined)
        assert(rejoined:GetAttribute("CurrentMazeLevel") == 2 and rejoined:GetAttribute("SkipCredits") == 0)
    end},

    {"every stage awards the configured amount including zero for Level 1", function()
        local f = fixture(); local p = f.player(22); f.shop.load(p)
        local expected, total = {0, 1, 5, 15, 50, 100, 200}, 0
        for stage, amount in ipairs(expected) do
            p:SetAttribute("CurrentMazeLevel", stage)
            assert(f.shop.completeStage(p, "entry-" .. stage, stage))
            total = total + amount
            assert(p:GetAttribute("Wins") == total)
            assert(p:GetAttribute("UnlockedLevel") == math.min(stage + 1, 7))
            assert(f.shop.completeStage(p, "entry-" .. stage, stage))
            assert(p:GetAttribute("Wins") == total, "duplicate touch/save must not award twice")
        end
        assert(total == 371)
    end},
    {"reward retries after a lost response cannot duplicate wins", function()
        local f = fixture(); local p = f.player(23); f.shop.load(p)
        p:SetAttribute("CurrentMazeLevel", 3)
        f.store.failAfterCommit = 1
        assert(not f.shop.completeStage(p, "retry-reward", 3))
        f.store.failAfterCommit = nil
        assert(f.shop.completeStage(p, "retry-reward", 3))
        assert(p:GetAttribute("Wins") == 5)
    end},
    {"trail purchase deducts its server price and repeat buys are free", function()
        local f = fixture(); f.store.profiles["24"] = {Wins = 150}
        local p = f.player(24); f.shop.load(p)
        assert(f.shop.selectTrail(p, "White", "Buy"))
        assert(p:GetAttribute("Wins") == 50 and p:GetAttribute("OwnsTrail_White"))
        assert(p:GetAttribute("EquippedTrail") == "White")
        assert(f.shop.selectTrail(p, "White", "Buy") and p:GetAttribute("Wins") == 50)
        assert(f.shop.selectTrail(p, "White", "Unequip") and p:GetAttribute("EquippedTrail") == "")
        assert(f.shop.selectTrail(p, "White", "Equip") and p:GetAttribute("Wins") == 50)
    end},
    {"insufficient stored wins block purchases regardless of displayed balance", function()
        local f = fixture(); local p = f.player(25); f.shop.load(p)
        p:SetAttribute("Wins", 999999)
        assert(not f.shop.selectTrail(p, "Red", "Buy"))
        assert(not p:GetAttribute("OwnsTrail_Red") and p:GetAttribute("Wins") == 0)
        assert(p:GetAttribute("EquippedTrail") == "")
    end},
    {"wins, ownership, equipment and unlocked stages persist across joins", function()
        local f = fixture(); f.store.profiles["26"] = {Wins = 350, UnlockedLevel = 5}
        local p = f.player(26); f.shop.load(p)
        assert(f.shop.selectTrail(p, "Green", "Buy"))
        local rejoined = f.player(26); f.shop.load(rejoined)
        assert(rejoined:GetAttribute("Wins") == 50 and rejoined:GetAttribute("UnlockedLevel") == 5)
        assert(rejoined:GetAttribute("EquippedTrail") == "Green" and rejoined:GetAttribute("OwnsTrail_Green"))
    end},
    {"failed trail writes do not grant a trail or lose wins", function()
        local f = fixture(); f.store.profiles["27"] = {Wins = 100}
        local p = f.player(27); f.shop.load(p); f.store.failWrite = true
        assert(not f.shop.selectTrail(p, "White", "Buy"))
        assert(p:GetAttribute("Wins") == 100 and not p:GetAttribute("OwnsTrail_White"))
        f.store.failWrite = false
        assert(f.shop.selectTrail(p, "White", "Buy") and p:GetAttribute("Wins") == 0)
    end},
    {"trail retry after a committed write never charges twice", function()
        local f = fixture(); f.store.profiles["28"] = {Wins = 1000}
        local p = f.player(28); f.shop.load(p); f.store.failAfterCommit = 1
        assert(not f.shop.selectTrail(p, "White", "Buy"))
        f.store.failAfterCommit = nil
        assert(f.shop.selectTrail(p, "White", "Buy"))
        assert(p:GetAttribute("Wins") == 900 and p:GetAttribute("EquippedTrail") == "White")
    end},
    {"unowned equipment and unknown trail actions are rejected", function()
        local f = fixture(); local p = f.player(29); f.shop.load(p)
        assert(not f.shop.selectTrail(p, "Blue", "Equip"))
        local writes = f.store.writes
        assert(not f.shop.selectTrail(p, "Unknown", "Buy"))
        assert(not f.shop.selectTrail(p, "White", "Free"))
        assert(f.store.writes == writes and p:GetAttribute("EquippedTrail") == "")
    end},
    {"skipped stages award wins once and stage transitions block overlapping skips", function()
        local f = fixture(); local p = f.player(30); f.shop.load(p)
        p:SetAttribute("CurrentMazeLevel", 4)
        f.receipt(30, f.config.SkipLevelProductId, "rewarded-skip")
        assert(p:GetAttribute("Wins") == 15 and p:GetAttribute("SkipUses") == 1)
        f.receipt(30, f.config.SkipLevelProductId, "rewarded-skip")
        assert(p:GetAttribute("Wins") == 15 and p:GetAttribute("SkipUses") == 1)
        p:SetAttribute("StageTransition", true)
        f.receipt(30, f.config.SkipLevelProductId, "wait-for-button")
        assert(p:GetAttribute("Wins") == 15 and p:GetAttribute("SkipCredits") == 1)
    end},
    {"lobby cannot consume a skip or claim a stage reward", function()
        local f = fixture(); local p = f.player(31); f.shop.load(p)
        p:SetAttribute("CurrentMazeLevel", 0)
        f.shop.prompt(p, "SkipLevel")
        assert(#f.market.prompts == 0)
        assert(not f.shop.completeStage(p, "forged-level", 7))
        assert(p:GetAttribute("Wins") == 0)
    end},
    {"the four trail prices are charged correctly", function()
        for _, item in ipairs({{"White", 100}, {"Green", 300}, {"Blue", 1000}, {"Red", 10000}}) do
            local f = fixture(); f.store.profiles["32"] = {Wins = item[2]}
            local p = f.player(32); f.shop.load(p)
            assert(f.shop.selectTrail(p, item[1], "Buy"))
            assert(p:GetAttribute("Wins") == 0 and p:GetAttribute("OwnsTrail_" .. item[1]))
        end
    end},

    {"a committed skip and a later pad touch cannot pay twice for one entry", function()
        local f = fixture(); local p = f.player(33); f.shop.load(p)
        p:SetAttribute("CurrentMazeLevel", 3)
        p:SetAttribute("StageEntryId", "same-attempt")
        f.store.failAfterCommit = 2
        f.receipt(33, f.config.SkipLevelProductId, "ambiguous-skip")
        f.store.failAfterCommit = nil
        p:SetAttribute("CurrentMazeLevel", 3)
        assert(f.shop.completeStage(p, "same-attempt", 3))
        assert(p:GetAttribute("Wins") == 5)
    end},
}
for _, test in ipairs(tests) do
    local ok, failure = pcall(test[2])
    if not ok then error(test[1] .. ": " .. tostring(failure)) end
    print("PASS " .. test[1])
end
print(#tests .. " shop tests passed (mocked services)")
