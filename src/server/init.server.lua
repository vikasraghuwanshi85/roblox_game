local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TrailCatalog = require(ReplicatedStorage:WaitForChild("TrailCatalog"))
local Levels = require(script.Levels)
local SilverShop = require(script.SilverShop)
local CELL, HEIGHT = 16, 14
local BASE_SPEED, SPEED_GAIN, MAX_SPEED, TRAIN_SECONDS = 16, 16, 640, 2
local world = Instance.new("Folder")
world.Name = "MazeQuest"
world.Parent = workspace
local maps, progress, shopRequests = {}, {}, {}
local LOBBY_CENTER = Vector3.new(-700, 0, 0)
local LOBBY_SPAWN = LOBBY_CENTER + Vector3.new(0, 4, -6)
local stageRewards, trailsByKey = {}, {}
for index, level in ipairs(Levels) do stageRewards[index] = level.WinReward end
for _, trail in ipairs(TrailCatalog) do trailsByKey[trail.Key] = trail end
local shopFolder = Instance.new("Folder")
shopFolder.Name = "MazeShop"
shopFolder.Parent = ReplicatedStorage
local purchaseRequest = Instance.new("RemoteEvent")
purchaseRequest.Name = "PurchaseRequest"
purchaseRequest.Parent = shopFolder
local trailRequest = Instance.new("RemoteEvent")
trailRequest.Name = "TrailRequest"
trailRequest.Parent = shopFolder

local function part(parent, name, size, position, color)
    local p = Instance.new("Part")
    p.Name, p.Size, p.Position = name, size, position
    p.Anchored = true
    p.Color = color
    p.TopSurface = Enum.SurfaceType.Smooth
    p.Parent = parent
    return p
end

-- A randomized depth-first spanning tree makes every maze cell reachable.
local function carve(size, seed)
    local random = Random.new(seed)
    local cells = {}
    for x = 1, size do
        cells[x] = {}
        for z = 1, size do cells[x][z] = {east = true, south = true} end
    end
    local stack = {{1, 1}}
    cells[1][1].visited = true
    while #stack > 0 do
        local current = stack[#stack]
        local x, z = current[1], current[2]
        local options = {}
        for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
            local nx, nz = x + d[1], z + d[2]
            if cells[nx] and cells[nx][nz] and not cells[nx][nz].visited then
                table.insert(options, {nx, nz})
            end
        end
        if #options == 0 then table.remove(stack)
        else
            local nextCell = options[random:NextInteger(1, #options)]
            local nx, nz = nextCell[1], nextCell[2]
            if nx > x then cells[x][z].east = false
            elseif nx < x then cells[nx][nz].east = false
            elseif nz > z then cells[x][z].south = false
            else cells[nx][nz].south = false end
            cells[nx][nz].visited = true
            table.insert(stack, nextCell)
        end
    end
    return cells
end

local function applySpeed(player)
    local state = progress[player]
    if not state then return end
    local multiplier = SilverShop.multiplier(player)
    local baseSpeed = SilverShop.baseSpeed(player, state.speed)
    local speed = baseSpeed * multiplier
    player:SetAttribute("BaseSpeed", baseSpeed)
    player:SetAttribute("SpeedMultiplier", multiplier)
    player:SetAttribute("TrainingSpeed", speed)
    local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if humanoid then humanoid.WalkSpeed = speed end
end

local function setStatus(player)
    local state = progress[player]
    if not state then return end
    applySpeed(player)
    player:SetAttribute("CurrentMazeLevel", state.inLobby and 0 or state.level)
    player:SetAttribute("MazeWon", false)
    if state.inLobby then
        player:SetAttribute("MazeStatus", "Lobby — Levels 1–" .. (player:GetAttribute("UnlockedLevel") or 1) .. " unlocked. Step on a stage pad; finish the maze to claim wins and return here.")
    else
        local level = Levels[state.level]
        local hint = level.Boss and (level.BossName .. " is immortal and chases at " .. level.BossSpeed .. " studs/sec.") or "No boss."
        player:SetAttribute("MazeStatus", "Level " .. state.level .. " — " .. level.Name .. "\n" .. hint .. " Find the green button: " .. level.WinReward .. " wins + return to lobby.")
    end
end

local function teleport(player)
    local state = progress[player]
    local character = player.Character
    if state and character then
        character:PivotTo(CFrame.new(state.inLobby and LOBBY_SPAWN or maps[state.level].spawn))
    end
end

local function returnToLobby(player)
    local state = progress[player]
    if not state then return end
    state.inLobby = true
    state.entryId = nil
    player:SetAttribute("StageEntryId", nil)
    teleport(player)
    setStatus(player)
end

local function applyTrail(player)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local key = player:GetAttribute("EquippedTrail") or ""
    local old = root:FindFirstChild("WinTrail")
    if old and old:GetAttribute("TrailKey") == key then return end
    for _, name in ipairs({"WinTrail", "WinTrailTop", "WinTrailBottom"}) do
        local object = root:FindFirstChild(name)
        if object then object:Destroy() end
    end
    local config = trailsByKey[key]
    if not config then return end
    local top, bottom = Instance.new("Attachment"), Instance.new("Attachment")
    top.Name, bottom.Name = "WinTrailTop", "WinTrailBottom"
    top.Position, bottom.Position = Vector3.new(0, 0.7, 1), Vector3.new(0, -0.7, 1)
    top.Parent, bottom.Parent = root, root
    local trail = Instance.new("Trail")
    trail.Name = "WinTrail"
    trail:SetAttribute("TrailKey", key)
    trail.Attachment0, trail.Attachment1 = top, bottom
    trail.Lifetime, trail.FaceCamera, trail.LightEmission = 0.8, true, 0.6
    local colors = {}
    for index, rgb in ipairs(config.Colors) do
        colors[index] = ColorSequenceKeypoint.new((index - 1) / (#config.Colors - 1), Color3.fromRGB(rgb[1], rgb[2], rgb[3]))
    end
    trail.Color = ColorSequence.new(colors)
    trail.Parent = root
end

local function sign(parent, text)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "Label"
    billboard.Size = UDim2.fromOffset(240, 70)
    billboard.StudsOffset = Vector3.new(0, 3.5, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 90
    billboard.Parent = parent
    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextStrokeTransparency = 0.2
    label.Font = Enum.Font.GothamBold
    label.TextSize = 18
    label.TextWrapped = true
    label.Parent = billboard
end

local function canTrainHere(state, trainingLevel)
    if not state then return false end
    if trainingLevel then return not state.inLobby and state.level == trainingLevel end
    return state.inLobby
end

local function buildTreadmills(folder, lobbyCenter, trainingLevel)
    local treadmill = Instance.new("Model")
    treadmill.Name = "SpeedTrainingTreadmill"
    treadmill.Parent = folder
    local belt = part(treadmill, "Belt", Vector3.new(5, 0.5, 7), lobbyCenter + Vector3.new(-8, 0.25, -6), Color3.fromRGB(25, 30, 40))
    for _, x in ipairs({-2.7, 2.7}) do
        part(treadmill, "Rail", Vector3.new(0.4, 2, 7), belt.Position + Vector3.new(x, 1, 0), Color3.fromRGB(100, 190, 240))
    end
    part(treadmill, "Console", Vector3.new(5, 1, 0.6), belt.Position + Vector3.new(0, 2, -3.2), Color3.fromRGB(100, 190, 240))
    local train = Instance.new("ProximityPrompt")
    train.ActionText = "Train: +16 speed (max 640)"
    train.ObjectText = "Speed Treadmill"
    train.HoldDuration = TRAIN_SECONDS
    train.MaxActivationDistance = 8
    train.RequiresLineOfSight = false
    train.Parent = belt
    train.Triggered:Connect(function(player)
        local state = progress[player]
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local now = os.clock()
        if not canTrainHere(state, trainingLevel) or not root or not humanoid or humanoid.Health <= 0 then return end
        if (root.Position - belt.Position).Magnitude > 10 or SilverShop.baseSpeed(player, state.speed) >= MAX_SPEED then return end
        if now - state.lastTraining < TRAIN_SECONDS then return end
        state.lastTraining = now
        state.speed = math.min(MAX_SPEED, state.speed + SPEED_GAIN)
        applySpeed(player)
        setStatus(player)
    end)
    local tierColors = {
        Silver = Color3.fromRGB(190, 195, 205),
        Gold = Color3.fromRGB(245, 190, 45),
        God = Color3.fromRGB(185, 95, 255),
    }
    local tierPositions = {
        Silver = Vector3.new(8, 0.25, -6),
        Gold = Vector3.new(-8, 0.25, 6),
        God = Vector3.new(8, 0.25, 6),
    }
    for _, offer in ipairs(SilverShop.offers()) do
        local machine = Instance.new("Model")
        machine.Name = offer.Key .. "Treadmill"
        machine.Parent = folder
        local paidBelt = part(machine, "Belt", Vector3.new(5, 0.5, 7), lobbyCenter + tierPositions[offer.Key], tierColors[offer.Key])
        paidBelt.Material = offer.Key == "God" and Enum.Material.Neon or Enum.Material.Metal
        for _, x in ipairs({-2.7, 2.7}) do
            part(machine, "Rail", Vector3.new(0.4, 2, 7), paidBelt.Position + Vector3.new(x, 1, 0), tierColors[offer.Key]).Material = Enum.Material.Metal
        end
        part(machine, "Console", Vector3.new(5, 1, 0.6), paidBelt.Position + Vector3.new(0, 2, -3.2), tierColors[offer.Key])
        local buy = Instance.new("ProximityPrompt")
        buy.ActionText = "Unlock " .. offer.Multiplier .. "x speed — " .. offer.Price .. " Robux"
        buy.ObjectText = offer.Key .. " Treadmill (permanent; highest boost applies)"
        buy.HoldDuration = 1
        buy.MaxActivationDistance = 8
        buy.RequiresLineOfSight = false
        buy.Parent = paidBelt
        buy.Triggered:Connect(function(player)
            local state = progress[player]
            local character = player.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if not canTrainHere(state, trainingLevel) or not root or not humanoid or humanoid.Health <= 0 then return end
            if (root.Position - paidBelt.Position).Magnitude > 10 then return end
            SilverShop.prompt(player, offer.Key)
        end)
    end
end

local lobby = Instance.new("Folder")
lobby.Name = "Lobby"
lobby.Parent = world
part(lobby, "Floor", Vector3.new(90, 2, 90), LOBBY_CENTER - Vector3.new(0, 1, 0), Color3.fromRGB(35, 42, 60))
for _, x in ipairs({-45, 45}) do
    part(lobby, "Wall", Vector3.new(1, HEIGHT, 90), LOBBY_CENTER + Vector3.new(x, HEIGHT / 2, 0), Color3.fromRGB(65, 75, 100))
end
for _, z in ipairs({-45, 45}) do
    part(lobby, "Wall", Vector3.new(90, HEIGHT, 1), LOBBY_CENTER + Vector3.new(0, HEIGHT / 2, z), Color3.fromRGB(65, 75, 100))
end
buildTreadmills(lobby, LOBBY_CENTER + Vector3.new(0, 0, -28), nil)
for index, level in ipairs(Levels) do
    local column = index <= 4 and (index - 1) or (index - 5)
    local x = index <= 4 and (-27 + column * 18) or (-18 + column * 18)
    local z = index <= 4 and 12 or 32
    local pad = part(lobby, "EnterLevel" .. index, Vector3.new(10, 1, 10), LOBBY_CENTER + Vector3.new(x, 0.5, z), level.WallColor or Color3.fromRGB(120, 78, 45))
    pad.Material = Enum.Material.Neon
    sign(pad, "Level " .. index .. " — " .. level.WinReward .. " wins\n" .. level.Name)
    pad.Touched:Connect(function(hit)
        local character = hit:FindFirstAncestorOfClass("Model")
        local player = character and Players:GetPlayerFromCharacter(character)
        local state = player and progress[player]
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not state or not state.inLobby or not root or not humanoid or humanoid.Health <= 0 then return end
        if not player:GetAttribute("ShopReady") or (root.Position - pad.Position).Magnitude > 12 then return end
        if index > (player:GetAttribute("UnlockedLevel") or 1) then
            player:SetAttribute("EconomyMessage", "Complete earlier stages to unlock Level " .. index .. ".")
            return
        end
        state.level, state.inLobby = index, false
        state.entryId = HttpService:GenerateGUID(false)
        player:SetAttribute("StageEntryId", state.entryId)
        teleport(player)
        setStatus(player)
    end)
end

for index, level in ipairs(Levels) do
    local folder = Instance.new("Folder")
    folder.Name = "Level" .. index
    folder.Parent = world
    local offset = Vector3.new((index - 1) * 500, 0, 0)
    local function pos(x, z, y) return offset + Vector3.new((x - 1) * CELL, y or 0, (z - 1) * CELL) end
    local size, cells = level.Size, carve(level.Size, level.Seed)
    local wallColor = level.WallColor or Color3.fromRGB(120, 78, 45)
    local function wall(p, s) part(folder, "Wall", s, p, wallColor) end
    part(folder, "Floor", Vector3.new(size * CELL, 2, size * CELL), pos((size + 1) / 2, (size + 1) / 2, -1), Color3.fromRGB(32, 45, 49))
    for x = 1, size do
        for z = 1, size do
            if cells[x][z].east then wall(pos(x, z, HEIGHT / 2) + Vector3.new(CELL / 2, 0, 0), Vector3.new(1, HEIGHT, CELL + 1)) end
            if cells[x][z].south then wall(pos(x, z, HEIGHT / 2) + Vector3.new(0, 0, CELL / 2), Vector3.new(CELL + 1, HEIGHT, 1)) end
        end
    end
    wall(pos(1, (size + 1) / 2, HEIGHT / 2) - Vector3.new(CELL / 2, 0, 0), Vector3.new(1, HEIGHT, size * CELL))
    wall(pos((size + 2) / 2, 1, HEIGHT / 2) - Vector3.new(0, 0, CELL / 2), Vector3.new((size - 1) * CELL, HEIGHT, 1))
    local lobbyCenter = pos(1, 1, 0) + Vector3.new(0, 0, -28)
    part(folder, "TrainingLobby", Vector3.new(32, 2, 24), lobbyCenter - Vector3.new(0, 1, 0), Color3.fromRGB(42, 48, 58))
    part(folder, "EntranceWalkway", Vector3.new(CELL, 2, 8), pos(1, 1, -1) + Vector3.new(0, 0, -12), Color3.fromRGB(42, 48, 58))
    for _, x in ipairs({-16, 16}) do
        wall(lobbyCenter + Vector3.new(x, HEIGHT / 2, 0), Vector3.new(1, HEIGHT, 24))
    end
    wall(lobbyCenter + Vector3.new(0, HEIGHT / 2, -12), Vector3.new(32, HEIGHT, 1))
    for _, x in ipairs({-12, 12}) do
        wall(lobbyCenter + Vector3.new(x, HEIGHT / 2, 12), Vector3.new(8, HEIGHT, 1))
    end
    for _, x in ipairs({-8, 8}) do
        wall(pos(1, 1, HEIGHT / 2) + Vector3.new(x, 0, -12), Vector3.new(1, HEIGHT, 8))
    end
    maps[index] = {spawn = lobbyCenter + Vector3.new(0, 4, 0)}
    buildTreadmills(folder, lobbyCenter, index)
    local exit = part(folder, "WinButton", Vector3.new(9, 1, 9), pos(size, size, 0.5), Color3.fromRGB(60, 255, 130))
    exit.Material = Enum.Material.Neon
    sign(exit, "STEP HERE\n+" .. level.WinReward .. " wins • Return to lobby")
    exit.Touched:Connect(function(hit)
        local character = hit:FindFirstAncestorOfClass("Model")
        local player = character and Players:GetPlayerFromCharacter(character)
        local state = player and progress[player]
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not state or state.inLobby or state.level ~= index or not root or not humanoid or humanoid.Health <= 0 then return end
        if player:GetAttribute("StageTransition") or player:GetAttribute("SkipTransition") or (root.Position - exit.Position).Magnitude > 12 then return end
        player:SetAttribute("StageTransition", true)
        local saved = SilverShop.completeStage(player, state.entryId, index)
        if saved then returnToLobby(player) end
        player:SetAttribute("StageTransition", false)
    end)
    if level.Boss then
        local guardian = part(folder, "Guardian", Vector3.new(5, 7, 5), pos(size, size - 1, 4), Color3.fromRGB(255, 65, 70))
        local bear = Instance.new("Model")
        bear.Name = level.BossName or "Bruno the Bear"
        bear.Parent = folder
        guardian.Parent = bear
        guardian.Name = "HumanoidRootPart"
        guardian.Size = Vector3.new(4, 5, 3)
        guardian.Anchored = false
        guardian.Color = (level.BossKind == "Cat" or level.BossKind == "Wolf" or level.BossKind == "Rat") and Color3.fromRGB(155, 155, 165) or Color3.fromRGB(112, 68, 38)
        if level.BossKind == "Lion" then guardian.Color = Color3.fromRGB(210, 155, 55) end
        bear.PrimaryPart = guardian
        local humanoid = Instance.new("Humanoid")
        humanoid.RequiresNeck = false
        humanoid.WalkSpeed = level.BossSpeed or 29
        humanoid.HipHeight = 1
        humanoid.DisplayName = bear.Name
        humanoid.BreakJointsOnDeath = false
        humanoid.MaxHealth = 1000000
        humanoid.Health = humanoid.MaxHealth
        humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
        humanoid.HealthChanged:Connect(function(health)
            if health < humanoid.MaxHealth then humanoid.Health = humanoid.MaxHealth end
        end)
        humanoid.Parent = bear
        bear:SetAttribute("Immortal", true)
        local protection = Instance.new("ForceField")
        protection.Visible = false
        protection.Parent = bear
        local function feature(name, size, relative, color)
            local p = part(bear, name, size, guardian.Position + relative, color)
            p.Anchored = false
            p.CanCollide = false
            p.Massless = true
            local weld = Instance.new("WeldConstraint")
            weld.Part0, weld.Part1, weld.Parent = guardian, p, p
            return p
        end
        local brown = guardian.Color
        feature("Head", Vector3.new(4, 3, 3), Vector3.new(0, 3, 0), brown)
        feature("LeftEar", Vector3.new(1.4, 1.4, 1), Vector3.new(-1.4, 4.6, 0), brown)
        feature("RightEar", Vector3.new(1.4, 1.4, 1), Vector3.new(1.4, 4.6, 0), brown)
        feature("Muzzle", Vector3.new(2.5, 1.2, 1), Vector3.new(0, 2.5, -1.7), Color3.fromRGB(185, 139, 91))
        for _, x in ipairs({-0.9, 0.9}) do
            feature("Eye", Vector3.new(0.4, 0.4, 0.3), Vector3.new(x, 3.4, -1.6), Color3.new(0, 0, 0))
        end
        if level.BossKind == "Cat" then
            -- Upright pointed ears, a pink nose, whiskers, and a long tail.
            for _, x in ipairs({-1.4, 1.4}) do
                local wedge = Instance.new("WedgePart")
                wedge.Name = "CatEar"
                wedge.Size = Vector3.new(1.4, 2, 1.2)
                wedge.CFrame = guardian.CFrame * CFrame.new(x, 4.7, 0)
                wedge.Color = brown
                wedge.CanCollide = false
                wedge.Massless = true
                wedge.Parent = bear
                local weld = Instance.new("WeldConstraint")
                weld.Part0, weld.Part1, weld.Parent = guardian, wedge, wedge
            end
            bear.LeftEar:Destroy()
            bear.RightEar:Destroy()
            bear.Muzzle.Color = Color3.fromRGB(210, 210, 215)
            feature("Nose", Vector3.new(0.6, 0.4, 0.4), Vector3.new(0, 2.8, -2.3), Color3.fromRGB(245, 140, 170))
            feature("Tail", Vector3.new(0.7, 0.7, 5), Vector3.new(0, -1, 3), brown)
            for _, x in ipairs({-1.6, 1.6}) do
                feature("Whiskers", Vector3.new(2, 0.1, 0.1), Vector3.new(x, 2.5, -2.25), Color3.new(1, 1, 1))
            end
        end
        if level.BossKind == "Wolf" then
            bear.LeftEar.Size = Vector3.new(1.2, 2.5, 1.2)
            bear.RightEar.Size = Vector3.new(1.2, 2.5, 1.2)
            bear.Muzzle:Destroy()
            feature("WolfSnout", Vector3.new(2, 1.5, 2.5), Vector3.new(0, 2.5, -2), Color3.fromRGB(210, 210, 215))
            feature("Nose", Vector3.new(1, 0.6, 0.5), Vector3.new(0, 2.7, -3.4), Color3.fromRGB(25, 25, 30))
            feature("BushyTail", Vector3.new(1.5, 1.5, 5), Vector3.new(0, -1, 3), brown)
        end
        if level.BossKind == "Rat" then
            bear.LeftEar.Size = Vector3.new(2.2, 2.2, 0.8)
            bear.RightEar.Size = Vector3.new(2.2, 2.2, 0.8)
            bear.LeftEar.Color = Color3.fromRGB(220, 150, 160)
            bear.RightEar.Color = Color3.fromRGB(220, 150, 160)
            bear.Muzzle:Destroy()
            feature("RatSnout", Vector3.new(1.7, 1.2, 2), Vector3.new(0, 2.5, -2), brown)
            feature("PinkNose", Vector3.new(0.7, 0.5, 0.5), Vector3.new(0, 2.6, -3.1), Color3.fromRGB(245, 145, 165))
            feature("RatTail", Vector3.new(0.4, 0.4, 6), Vector3.new(0, -1.5, 4), Color3.fromRGB(220, 150, 160))
            for _, x in ipairs({-1.5, 1.5}) do
                feature("Whiskers", Vector3.new(2, 0.1, 0.1), Vector3.new(x, 2.5, -2.8), Color3.new(1, 1, 1))
            end
        end
        if level.BossKind == "Lion" then
            local maneColor = Color3.fromRGB(135, 75, 25)
            for n = 0, 7 do
                local angle = n * math.pi / 4
                feature("Mane", Vector3.new(1.6, 1.6, 1.6), Vector3.new(math.cos(angle) * 2.1, 3 + math.sin(angle) * 2.1, 0.4), maneColor)
            end
            bear.Muzzle.Color = Color3.fromRGB(240, 205, 135)
            feature("LionNose", Vector3.new(0.8, 0.5, 0.5), Vector3.new(0, 2.8, -2.3), Color3.fromRGB(45, 30, 20))
            feature("LionTail", Vector3.new(0.6, 0.6, 4), Vector3.new(0, -1, 3), brown)
            feature("TailTuft", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, -1, 5), maneColor)
        end
        if level.BossKind == "Horse" then
            bear.LeftEar.Size = Vector3.new(0.8, 2.5, 0.8)
            bear.RightEar.Size = Vector3.new(0.8, 2.5, 0.8)
            bear.Muzzle:Destroy()
            feature("HorseMuzzle", Vector3.new(2.5, 2, 3), Vector3.new(0, 2.2, -2.2), Color3.fromRGB(165, 115, 80))
            feature("LeftNostril", Vector3.new(0.4, 0.5, 0.2), Vector3.new(-0.7, 2.2, -3.75), Color3.fromRGB(30, 22, 18))
            feature("RightNostril", Vector3.new(0.4, 0.5, 0.2), Vector3.new(0.7, 2.2, -3.75), Color3.fromRGB(30, 22, 18))
            feature("Mane", Vector3.new(1.2, 5, 1), Vector3.new(0, 1.5, 1.6), Color3.fromRGB(35, 25, 20))
            feature("HorseTail", Vector3.new(1, 3, 1), Vector3.new(0, -1, 2), Color3.fromRGB(35, 25, 20))
        end
        guardian:SetNetworkOwner(nil)
        task.spawn(function()
            while bear.Parent do
                local target, nearest = nil, math.huge
                for player, state in pairs(progress) do
                    local character = player.Character
                    local root = character and character:FindFirstChild("HumanoidRootPart")
                    local health = character and character:FindFirstChildOfClass("Humanoid")
                    if state.level == index and not state.inLobby and root and health and health.Health > 0 then
                        local distance = (root.Position - guardian.Position).Magnitude
                        if distance < nearest then target, nearest = root, distance end
                    end
                end
                if target then
                    local path = PathfindingService:CreatePath({AgentRadius = 2.5, AgentHeight = 9, AgentCanJump = false, WaypointSpacing = 5})
                    local ok = pcall(function() path:ComputeAsync(guardian.Position, target.Position) end)
                    if ok and path.Status == Enum.PathStatus.Success then
                        local started = os.clock()
                        for n, waypoint in ipairs(path:GetWaypoints()) do
                            if n > 1 then
                                humanoid:MoveTo(waypoint.Position)
                                local deadline = os.clock() + 1
                                repeat task.wait(0.05) until not bear.Parent or (guardian.Position - waypoint.Position).Magnitude < 3 or os.clock() > deadline
                                if os.clock() - started > 0.8 then break end
                            end
                        end
                    end
                else
                    humanoid:MoveTo(guardian.Position)
                end
                task.wait(0.15)
            end
        end)

    end
end

SilverShop.start(function(player)
    local state = progress[player]
    if not state then return end
    local skips = player:GetAttribute("SkipUses") or 0
    if state.skipUses and skips > state.skipUses and not state.inLobby then
        returnToLobby(player)
        player:SetAttribute("EconomyMessage", "Stage skipped! Its wins are saved. Choose a stage in the lobby.")
    end
    state.skipUses = skips
    local stats = player:FindFirstChild("leaderstats")
    if stats then stats.Wins.Value = player:GetAttribute("Wins") or 0 end
    applyTrail(player)
    setStatus(player)
end, #Levels, function(offer, available)
    if offer.Price then shopFolder:SetAttribute(offer.Key .. "Price", offer.Price) end
    shopFolder:SetAttribute(offer.Key .. "Available", available)
end, stageRewards)

purchaseRequest.OnServerEvent:Connect(function(player, key)
    if key ~= "MillionSpeed" and key ~= "SkipLevel" then return end
    local state = progress[player]
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not state or not humanoid or humanoid.Health <= 0 then return end
    local now = os.clock()
    if now - (shopRequests[player] or -math.huge) < 1 then return end
    shopRequests[player] = now
    SilverShop.prompt(player, key)
end)

trailRequest.OnServerEvent:Connect(function(player, key, action)
    if type(key) ~= "string" or type(action) ~= "string" or not progress[player] then return end
    local now = os.clock()
    if now - (shopRequests[player] or -math.huge) < 0.5 then return end
    shopRequests[player] = now
    SilverShop.selectTrail(player, key, action)
end)

local function join(player)
    local stats = Instance.new("Folder")
    stats.Name, stats.Parent = "leaderstats", player
    local wins = Instance.new("IntValue")
    wins.Name, wins.Parent = "Wins", stats
    progress[player] = {level = 1, inLobby = true, speed = BASE_SPEED, lastTraining = os.clock()}
    setStatus(player)
    SilverShop.load(player)
    player.CharacterAdded:Connect(function(character)
        character:WaitForChild("HumanoidRootPart")
        local humanoid = character:WaitForChild("Humanoid")
        if not progress[player] then return end
        applySpeed(player)
        applyTrail(player)
        teleport(player)
        setStatus(player)
    end)
    if player.Character then
        local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then applySpeed(player); applyTrail(player) end
        teleport(player)
    end
    setStatus(player)
end
Players.PlayerAdded:Connect(join)
Players.PlayerRemoving:Connect(function(player) progress[player] = nil; shopRequests[player] = nil end)
for _, player in ipairs(Players:GetPlayers()) do join(player) end
