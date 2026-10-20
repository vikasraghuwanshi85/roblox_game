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
    if not options.actualIds then
        config.GoldTreadmillProductId, config.GodTreadmillProductId = 101, 102
    end
    if options.disableNewProducts then
        config.GoldTreadmillProductId, config.GodTreadmillProductId = 0, 0
    end
    local players = {PlayerRemoving = signal(), users = {}}
    function players:GetPlayerByUserId(id) return self.users[id] end
    local store = {profiles = {}, failWrite = false, failRead = false}
    function store:UpdateAsync(key, callback)
        if self.failWrite then error("write unavailable") end
        self.profiles[key] = callback(self.profiles[key])
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
        return {PriceInRobux = options.wrongPrice and 999 or prices[id]}
    end
    function market:PromptProductPurchase(player, id)
        table.insert(self.prompts, {player, id})
    end
    local services = {
        Players = players,
        MarketplaceService = market,
        DataStoreService = {GetDataStore = function(_, name)
            assert(name == "MazeQuestSilverV1", "existing ownership store must be retained")
            return store
        end},
    }
    game = {GetService = function(_, name) return services[name] end}
    script = {Parent = {ShopConfig = "config"}}
    require = function(name) assert(name == "config"); return config end
    task = {spawn = function(callback) callback() end}
    warn = function() end
    Enum = {InfoType = {Product = "product"}, ProductPurchaseDecision = {NotProcessedYet = "retry", PurchaseGranted = "granted"}}
    local shop = dofile("src/server/SilverShop.lua")
    local changes = 0
    shop.start(function() changes = changes + 1 end)
    local function player(id)
        local p = {UserId = id, Parent = true, attributes = {}}
        function p:SetAttribute(name, value) self.attributes[name] = value end
        function p:GetAttribute(name) return self.attributes[name] end
        players.users[id] = p
        return p
    end
    local function receipt(id, productId)
        return market.ProcessReceipt({PlayerId = id, ProductId = productId})
    end
    return {shop = shop, player = player, store = store, market = market, receipt = receipt, config = config, players = players}
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
}
for _, test in ipairs(tests) do
    local ok, failure = pcall(test[2])
    if not ok then error(test[1] .. ": " .. tostring(failure)) end
    print("PASS " .. test[1])
end
print(#tests .. " shop tests passed (mocked services)")
