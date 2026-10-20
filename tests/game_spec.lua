-- A service-mocked server smoke test. It does not simulate Roblox physics.
local function signal()
    local value = {callbacks = {}}
    function value:Connect(callback)
        local item = {callback = callback, active = true}
        table.insert(self.callbacks, item)
        return {Disconnect = function() item.active = false end}
    end
    function value:Fire(...) for _, item in ipairs(self.callbacks) do if item.active then item.callback(...) end end end
    return value
end
local vector = {}
vector.__index = function(v, key)
    if key == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
    if key == "Unit" then return Vector3.new(v.X / v.Magnitude, v.Y / v.Magnitude, v.Z / v.Magnitude) end
end
Vector3 = {new = function(x, y, z) return setmetatable({X = x, Y = y, Z = z}, vector) end}
vector.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
vector.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
vector.__mul = function(a, b) return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
typeof = function(value) return getmetatable(value) == vector and "Vector3" or type(value) end
local frame = {}
frame.__mul = function(a, b) return setmetatable({Position = a.Position + b.Position}, frame) end
CFrame = {new = function(x, y, z)
    return setmetatable({Position = type(x) == "table" and x or Vector3.new(x, y, z)}, frame)
end}
Color3 = {fromRGB = function(...) return {...} end, new = function(...) return {...} end}
ColorSequenceKeypoint = {new = function(...) return {...} end}
ColorSequence = {new = function(value) return value end}
UDim2 = {fromOffset = function(...) return {...} end, fromScale = function(...) return {...} end}
local enums = {CreatorType = {}, ActuatorRelativeTo = {}, OrientationAlignmentMode = {}, Material = {}, SurfaceType = {}, Font = {}, HumanoidHealthDisplayType = {}, HumanoidStateType = {}, InfoType = {}, ProductPurchaseDecision = {PurchaseGranted = "granted", NotProcessedYet = "retry"}}
for _, values in pairs(enums) do setmetatable(values, {__index = function(_, key) return key end}) end
Enum = enums
Random = {new = function() return {NextInteger = function(_, minimum) return minimum end} end}
local methods, instance = {}, {}
local signals = {Touched = true, Triggered = true, OnServerEvent = true, HealthChanged = true, PlayerAdded = true, PlayerRemoving = true, CharacterAdded = true, PromptProductPurchaseFinished = true, Died = true}
instance.__index = function(object, key)
    if methods[key] then return methods[key] end
    if key == "CFrame" then return CFrame.new(object.props.Position) end
    local value = object.props[key]
    if value ~= nil then return value end
    if signals[key] then
        object.props[key] = signal()
        return object.props[key]
    end
    for child in pairs(object.children) do if child.Name == key then return child end end
end
instance.__newindex = function(object, key, value)
    if key == "Parent" then
        local old = object.props.Parent
        if old then old.children[object] = nil end
        if value then value.children[object] = true end
    end
    object.props[key] = value
    if key == "Health" and object.props.HealthChanged then object.HealthChanged:Fire(value) end
end
Instance = {new = function(class)
    return setmetatable({props = {Name = class, ClassName = class, Position = Vector3.new(0, 0, 0), Health = 100, MaxHealth = 100}, children = {}, attributes = {}}, instance)
end}
function methods:SetAttribute(key, value) self.attributes[key] = value end
function methods:GetAttribute(key) return self.attributes[key] end
function methods:FindFirstChild(name) for child in pairs(self.children) do if child.Name == name then return child end end end
function methods:FindFirstChildOfClass(class) for child in pairs(self.children) do if child.ClassName == class then return child end end end
function methods:WaitForChild(name) return assert(self:FindFirstChild(name), "Missing child: " .. name) end
function methods:FindFirstAncestorOfClass(class)
    local current = self.Parent
    while current do if current.ClassName == class then return current end; current = current.Parent end
end
function methods:Destroy() self.Parent = nil end
function methods:SetNetworkOwner(value) self.props.NetworkOwner = value end
function methods:SetNetworkOwnershipAuto() self.props.NetworkAutomatic = true end
function methods:ChangeState(value) self.props.HumanoidState = value end
function methods:SetStateEnabled(key, enabled) self.attributes["state:" .. key] = enabled end
function methods:MoveTo(position) self.props.LastMoveTo = position end
function methods:PivotTo(cframe) self.HumanoidRootPart.Position = cframe.Position end
workspace = Instance.new("Workspace")
local players, replicated = Instance.new("Players"), Instance.new("ReplicatedStorage")
local users, profiles, failWrite = {}, {}, false
players.GetPlayers = function() return users end
players.GetUserIdFromNameAsync = function(_, name)
    -- Deliberate test-only IDs; no real account IDs are asserted here.
    local ids = {progamer2013988 = 321, raindeer_g6 = 654}
    return assert(ids[name], "test lookup failed")
end
players.GetPlayerByUserId = function(_, id) for _, p in ipairs(users) do if p.UserId == id then return p end end end
players.GetPlayerFromCharacter = function(_, character) for _, p in ipairs(users) do if p.Character == character then return p end end end
local market = Instance.new("MarketplaceService")
local prices = {[3720262741] = 15, [3720265337] = 30, [3720265626] = 50, [3720266025] = 60, [3720265823] = 20}
market.GetProductInfo = function(_, id) return {PriceInRobux = prices[id]} end
local purchasePrompts = 0
market.PromptProductPurchase = function() purchasePrompts = purchasePrompts + 1 end
local store = {}
function store:GetAsync(key) return profiles[key] end
function store:UpdateAsync(key, callback)
    if failWrite then error("test storage failure") end
    profiles[key] = callback(profiles[key])
    return profiles[key]
end
local serial = 0
local heartbeat = signal()
local services = {
    RunService = {Heartbeat = heartbeat},
    GroupService = {GetGroupInfoAsync = function() return {Owner = {Id = 888}} end},
    Players = players, ReplicatedStorage = replicated, MarketplaceService = market,
    DataStoreService = {GetDataStore = function() return store end},
    HttpService = {GenerateGUID = function() serial = serial + 1; return "entry-" .. serial end},
    PathfindingService = {},
}
game = {CreatorId = 999, CreatorType = Enum.CreatorType.User, GetService = function(_, name) return assert(services[name], name) end}
task = {spawn = function(callback)
    local co = coroutine.create(callback)
    local ok, failure = coroutine.resume(co)
    assert(ok, failure)
end, wait = function() coroutine.yield() end}
warn = function() end
local catalogObject = Instance.new("ModuleScript")
catalogObject.Name, catalogObject.Parent = "TrailCatalog", replicated
local catalog = dofile("src/shared/TrailCatalog.lua")
local levels, config = dofile("src/server/Levels.lua"), dofile("src/server/ShopConfig.lua")
local shop, admin
local adminConfig = dofile("src/server/AdminConfig.lua")
adminConfig.AdminUserIds = {123}
script = {AdminPowers = "admin", Levels = "levels", SilverShop = "shop", Parent = {ShopConfig = "config", AdminConfig = "adminConfig"}}
require = function(name)
    if name == catalogObject then return catalog end
    if name == "levels" then return levels end
    if name == "config" then return config end
    if name == "shop" then return shop end
    if name == "admin" then return admin end
    if name == "adminConfig" then return adminConfig end
    error("Unknown module")
end
shop = dofile("src/server/SilverShop.lua")
admin = dofile("src/server/AdminPowers.lua")
dofile("src/server/init.server.lua")
local function character()
    local model, root, humanoid = Instance.new("Model"), Instance.new("Part"), Instance.new("Humanoid")
    root.Name, root.Parent = "HumanoidRootPart", model
    humanoid.Parent, model.Parent = model, workspace
    return model
end
local function join(id)
    local player = Instance.new("Player")
    player.UserId, player.Parent, player.Character = id or 42, players, character()
    if id then table.insert(users, player) else users[1] = player end
    players.PlayerAdded:Fire(player)
    return player
end
local function touch(player, pad)
    player.Character:PivotTo(CFrame.new(pad.Position + Vector3.new(0, 3, 0)))
    pad.Touched:Fire(player.Character.HumanoidRootPart)
end
local player = join()
local world, lobby = workspace.MazeQuest, workspace.MazeQuest.Lobby
assert(player:GetAttribute("CurrentMazeLevel") == 0 and player:GetAttribute("Wins") == 0)
assert(player.Character.HumanoidRootPart.Position.X == -700)
touch(player, lobby.EnterLevel3)
assert(player:GetAttribute("CurrentMazeLevel") == 0, "locked stage must remain inaccessible")
local total = 0
for stage, level in ipairs(levels) do
    touch(player, lobby["EnterLevel" .. stage])
    assert(player:GetAttribute("CurrentMazeLevel") == stage)
    local button = world["Level" .. stage].WinButton
    if stage == 2 then
        failWrite = true; touch(player, button)
        assert(player:GetAttribute("CurrentMazeLevel") == 2 and player:GetAttribute("Wins") == 0)
        failWrite = false
    end
    touch(player, button)
    total = total + level.WinReward
    assert(player:GetAttribute("CurrentMazeLevel") == 0, "reward button must return to lobby")
    assert(player:GetAttribute("Wins") == total and player.leaderstats.Wins.Value == total)
    assert(player.Character.HumanoidRootPart.Position.X == -700)
    button.Touched:Fire(player.Character.HumanoidRootPart)
    assert(player:GetAttribute("Wins") == total, "repeat body touches cannot duplicate rewards")
end
assert(total == 371 and player:GetAttribute("UnlockedLevel") == 7)
replicated.MazeShop.TrailRequest.OnServerEvent:Fire(player, "White", "Buy")
assert(player:GetAttribute("Wins") == 271 and player:GetAttribute("OwnsTrail_White"))
assert(player.Character.HumanoidRootPart.WinTrail:GetAttribute("TrailKey") == "White")
player.Character = character(); player.CharacterAdded:Fire(player.Character)
assert(player.Character.HumanoidRootPart.WinTrail, "equipped trail must return after respawn")
players.PlayerRemoving:Fire(player); player.Parent = nil
local rejoined = join()
assert(rejoined:GetAttribute("CurrentMazeLevel") == 0 and rejoined:GetAttribute("Wins") == 271)
assert(rejoined:GetAttribute("UnlockedLevel") == 7 and rejoined.Character.HumanoidRootPart.WinTrail)
touch(rejoined, lobby.EnterLevel2)
market.ProcessReceipt({PlayerId = 42, ProductId = 3720265823, PurchaseId = "skip-lobby"})
assert(rejoined:GetAttribute("CurrentMazeLevel") == 0 and rejoined:GetAttribute("Wins") == 272)
market.ProcessReceipt({PlayerId = 42, ProductId = 3720265823, PurchaseId = "skip-lobby"})
assert(rejoined:GetAttribute("Wins") == 272)
for stage = 2, #levels do
    local boss = world["Level" .. stage][levels[stage].BossName]
    assert(boss:GetAttribute("Immortal") and boss:FindFirstChildOfClass("ForceField"))
    assert(boss.Humanoid.WalkSpeed == levels[stage].BossSpeed)
    boss.Humanoid.Health = 0
    assert(boss.Humanoid.Health == boss.Humanoid.MaxHealth)
    assert(boss.Humanoid.attributes["state:Dead"] == false)
    assert(not boss.HumanoidRootPart:FindFirstChildOfClass("ProximityPrompt"))
end
print("PASS server lobby, seven reward buttons, save failure/retry, duplicate touches, trail purchase, respawn, rejoin, skip, and immortal boss setup (mocked services)")

-- Role and movement checks run against the actual server module and event wiring.
local request = replicated.MazeShop.AdminRequest
local originalClock, now = os.clock, 100
os.clock = function() return now end
local before = rejoined.Character.Humanoid.WalkSpeed
rejoined:SetAttribute("CanAdminPowers", true)
rejoined:SetAttribute("AdminInfiniteActive", true)
request.OnServerEvent:Fire(rejoined, "ToggleInfinite")
request.OnServerEvent:Fire(rejoined, "ToggleFlight")
assert(rejoined.Character.Humanoid.WalkSpeed == before)
assert(not rejoined.Character.HumanoidRootPart.AdminFlightVelocity)
assert(not admin.enableGod(rejoined), "forged attributes cannot grant admin powers")
local owner = join(999)
assert(owner:GetAttribute("AdminRole") == "Owner" and owner:GetAttribute("CanAdminPowers"))
local belt = lobby.GodTreadmill.Belt
owner.Character:PivotTo(CFrame.new(belt.Position + Vector3.new(0, 3, 0)))
local promptsBefore = purchasePrompts
belt.ProximityPrompt.Triggered:Fire(owner)
assert(owner:GetAttribute("AdminGodActive") and owner.Character.Humanoid.WalkSpeed == 16 * 99)
assert(purchasePrompts == promptsBefore and not (profiles["999"] and profiles["999"].God))
request.OnServerEvent:Fire(owner, "ToggleInfinite")
assert(owner.Character.Humanoid.WalkSpeed == adminConfig.InfiniteWalkSpeed)
now = now + 1
request.OnServerEvent:Fire(owner, "ToggleFlight")
assert(owner:GetAttribute("AdminFlying") and owner.Character.HumanoidRootPart.AdminFlightVelocity)
now = now + 0.1
request.OnServerEvent:Fire(owner, "FlightInput", Vector3.new(100, 0, 0))
heartbeat:Fire()
assert(owner.Character.HumanoidRootPart.AdminFlightVelocity.VectorVelocity.Magnitude == adminConfig.FlySpeed)
now = now + 0.1
request.OnServerEvent:Fire(owner, "FlightInput", Vector3.new(0 / 0, 0, 0))
heartbeat:Fire()
assert(owner.Character.HumanoidRootPart.AdminFlightVelocity.VectorVelocity.Magnitude == adminConfig.FlySpeed)
now = now + 1
heartbeat:Fire()
assert(owner.Character.HumanoidRootPart.AdminFlightVelocity.VectorVelocity.Magnitude == 0, "stale input must hover")
local oldRoot = owner.Character.HumanoidRootPart
owner.Character = character(); owner.CharacterAdded:Fire(owner.Character)
assert(not owner:GetAttribute("AdminFlying") and not oldRoot.AdminFlightVelocity)
assert(oldRoot.props.NetworkAutomatic and owner.Character.Humanoid.WalkSpeed == adminConfig.InfiniteWalkSpeed)
now = now + 1
request.OnServerEvent:Fire(owner, "ToggleInfinite")
assert(owner.Character.Humanoid.WalkSpeed == 16 * 99)
local permitted = join(123)
assert(permitted:GetAttribute("AdminRole") == "Admin")
assert(admin.enableGod(permitted) and permitted.Character.Humanoid.WalkSpeed == 16 * 99)
assert(not admin.handle(permitted, "BecomeOwner"))
request.OnServerEvent:Fire(permitted, "ToggleFlight")
assert(permitted:GetAttribute("AdminFlying"))
adminConfig.AdminUserIds = {}
heartbeat:Fire()
assert(not permitted:GetAttribute("AdminFlying") and not permitted:GetAttribute("CanAdminPowers"))
assert(permitted.Character.Humanoid.WalkSpeed == 16, "revocation must remove free God and infinite movement")
-- Group ownership is looked up by the server; the group ID is never a User ID.
game.CreatorType, game.CreatorId = Enum.CreatorType.Group, 900
admin.start(function() end)
assert(admin.role({UserId = 888}) == "Owner")
assert(admin.role({UserId = 900}) == "Player")
assert(admin.role({UserId = -1}) == "Player")
assert(admin.role({UserId = 321}) == "Admin" and admin.role({UserId = 654}) == "Admin")
assert(admin.role({UserId = 987, Name = "progamer2013988", DisplayName = "raindeer_g6"}) == "Player", "names never bypass ID authorization")
os.clock = originalClock
print("PASS admin/owner roles, forged-role rejection, free God access, finite infinite mode, bounded flight, invalid/stale input, respawn cleanup, revocation, and group owner resolution (mocked services)")
