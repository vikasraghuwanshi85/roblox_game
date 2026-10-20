local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local Levels = require(script.Levels)
local CELL, HEIGHT = 16, 14
local world = Instance.new("Folder")
world.Name = "MazeQuest"
world.Parent = workspace
local maps, progress, cooldowns = {}, {}, {}

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

local function setStatus(player)
    local state = progress[player]
    if not state then return end
    if state.won then
        player:SetAttribute("MazeStatus", "Victory! You escaped every maze. Rejoin to play again.")
    else
        local level = Levels[state.level]
        local hint = level.Boss and (state.bossDefeated and "Guardian defeated! Find the green exit." or (level.BossName .. " runs at " .. level.BossSpeed .. " studs/sec! Hold E nearby three times to win!")) or "No boss. Find the green exit!"
        player:SetAttribute("MazeStatus", "Level " .. state.level .. " — " .. level.Name .. "\n" .. hint)
    end
end

local function teleport(player)
    local state = progress[player]
    local character = player.Character
    if state and character then character:PivotTo(CFrame.new(maps[state.level].spawn)) end
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
    wall(pos((size + 1) / 2, 1, HEIGHT / 2) - Vector3.new(0, 0, CELL / 2), Vector3.new(size * CELL, HEIGHT, 1))
    maps[index] = {spawn = pos(1, 1, 4)}
    local exit = part(folder, "Exit", Vector3.new(9, 1, 9), pos(size, size, 0.5), Color3.fromRGB(60, 255, 130))
    exit.Material = Enum.Material.Neon
    exit.Touched:Connect(function(hit)
        local player = Players:GetPlayerFromCharacter(hit:FindFirstAncestorOfClass("Model"))
        local state = player and progress[player]
        if not state or state.level ~= index or state.won then return end
        if level.Boss and not state.bossDefeated then return end
        if index == #Levels then state.won = true
        else state.level = index + 1; state.bossDefeated = false; state.hits = 0; teleport(player) end
        setStatus(player)
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
        bear.PrimaryPart = guardian
        local humanoid = Instance.new("Humanoid")
        humanoid.RequiresNeck = false
        humanoid.WalkSpeed = level.BossSpeed or 29
        humanoid.HipHeight = 1
        humanoid.DisplayName = bear.Name
        humanoid.Parent = bear
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
        guardian:SetNetworkOwner(nil)
        task.spawn(function()
            while bear.Parent do
                local target, nearest = nil, math.huge
                for player, state in pairs(progress) do
                    local character = player.Character
                    local root = character and character:FindFirstChild("HumanoidRootPart")
                    local health = character and character:FindFirstChildOfClass("Humanoid")
                    if state.level == index and not state.bossDefeated and root and health and health.Health > 0 then
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
        local prompt = Instance.new("ProximityPrompt")
        prompt.ActionText = "Strike " .. (string.match(bear.Name, "^%S+") or bear.Name)
        prompt.ObjectText = bear.Name .. " — 3 strikes"
        prompt.HoldDuration = 0.6
        prompt.MaxActivationDistance = 11
        prompt.RequiresLineOfSight = true
        prompt.Parent = guardian
        prompt.Triggered:Connect(function(player)
            local state = progress[player]
            local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            local now = os.clock()
            if not state or state.level ~= index or state.bossDefeated or not root then return end
            if (root.Position - guardian.Position).Magnitude > 13 or now - (cooldowns[player] or 0) < 0.6 then return end
            cooldowns[player] = now
            state.hits = state.hits + 1
            state.bossDefeated = state.hits >= 3
            setStatus(player)
        end)
        -- Telegraph a short-range pulse; taking cover or stepping back avoids damage.
        task.spawn(function()
            while guardian.Parent do
                task.wait(3)
                guardian.Color = Color3.fromRGB(255, 210, 60)
                task.wait(1)
                guardian.Color = Color3.fromRGB(255, 65, 70)
                for player, state in pairs(progress) do
                    local character = player.Character
                    local root = character and character:FindFirstChild("HumanoidRootPart")
                    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                    if state.level == index and not state.bossDefeated and root and humanoid and (root.Position - guardian.Position).Magnitude < 12 then
                        local params = RaycastParams.new()
                        params.FilterType = Enum.RaycastFilterType.Exclude
                        params.FilterDescendantsInstances = {bear}
                        local hit = workspace:Raycast(guardian.Position, root.Position - guardian.Position, params)
                        if hit and hit.Instance:IsDescendantOf(character) then humanoid:TakeDamage(25) end
                    end
                end
            end
        end)
    end
end

local function join(player)
    progress[player] = {level = 1, hits = 0, bossDefeated = false}
    player.CharacterAdded:Connect(function(character)
        character:WaitForChild("HumanoidRootPart")
        teleport(player)
        setStatus(player)
    end)
    if player.Character then teleport(player) end
    setStatus(player)
end
Players.PlayerAdded:Connect(join)
Players.PlayerRemoving:Connect(function(player) progress[player] = nil; cooldowns[player] = nil end)
for _, player in ipairs(Players:GetPlayers()) do join(player) end
