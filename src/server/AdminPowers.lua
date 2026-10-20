local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GroupService = game:GetService("GroupService")
local Config = require(script.Parent.AdminConfig)
local Powers = {}
local states, groupOwner, resolvedAdminIds = {}, nil, {}
local onChanged
local function listed(ids, id)
    if id <= 0 then return false end
    for _, allowed in ipairs(ids) do if type(allowed) == "number" and allowed == id then return true end end
    return false
end
function Powers.role(player)
    if listed(Config.OwnerUserIds, player.UserId) then return "Owner" end
    if Config.AutoDetectOwner and player.UserId > 0 then
        if game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId then return "Owner" end
        if groupOwner == player.UserId then return "Owner" end
    end
    if listed(Config.AdminUserIds, player.UserId) or resolvedAdminIds[player.UserId] then return "Admin" end
    return "Player"
end
function Powers.allowed(player) return Powers.role(player) ~= "Player" end
function Powers.godEnabled(player)
    return Powers.allowed(player) and states[player] and states[player].god or false
end
function Powers.speed(player, normal)
    if Powers.allowed(player) and states[player] and states[player].infinite then
        return math.max(normal, Config.InfiniteWalkSpeed)
    end
    return normal
end
local function publish(player)
    local state = states[player]
    player:SetAttribute("AdminRole", Powers.role(player))
    player:SetAttribute("CanAdminPowers", Powers.allowed(player))
    player:SetAttribute("AdminGodActive", state and state.god or false)
    player:SetAttribute("AdminInfiniteActive", state and state.infinite or false)
    player:SetAttribute("AdminFlying", state and state.flying or false)
end
local function stopFlight(player)
    local state = states[player]
    if not state then return end
    if state.deathConnection then state.deathConnection:Disconnect(); state.deathConnection = nil end
    for _, object in ipairs(state.objects or {}) do object:Destroy() end
    state.objects, state.flying = nil, false
    if state.root and state.root.Parent then state.root:SetNetworkOwnershipAuto() end
    if state.humanoid and state.humanoid.Parent then
        state.humanoid.PlatformStand = state.wasPlatformStand
        state.humanoid.AutoRotate = state.wasAutoRotate
        if state.humanoid.Health > 0 then state.humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end
    end
    state.root, state.humanoid, state.velocity = nil, nil, nil
    publish(player)
end
local function startFlight(player)
    local state = states[player]
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not state or not root or not humanoid or humanoid.Health <= 0 then return false end
    local attachment = Instance.new("Attachment")
    attachment.Name, attachment.Parent = "AdminFlightAttachment", root
    local velocity = Instance.new("LinearVelocity")
    velocity.Name, velocity.Attachment0 = "AdminFlightVelocity", attachment
    velocity.RelativeTo = Enum.ActuatorRelativeTo.World
    velocity.MaxForce = 1000000
    velocity.VectorVelocity = Vector3.new(0, 0, 0)
    velocity.Parent = root
    local orientation = Instance.new("AlignOrientation")
    orientation.Name, orientation.Attachment0 = "AdminFlightOrientation", attachment
    orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
    orientation.MaxTorque, orientation.Responsiveness = 1000000, 20
    orientation.CFrame = root.CFrame
    orientation.Parent = root
    state.root, state.humanoid, state.velocity = root, humanoid, velocity
    state.wasPlatformStand, state.wasAutoRotate = humanoid.PlatformStand, humanoid.AutoRotate
    state.objects, state.flying = {velocity, orientation, attachment}, true
    state.direction, state.lastInput = Vector3.new(0, 0, 0), os.clock()
    humanoid.PlatformStand, humanoid.AutoRotate = true, false
    root:SetNetworkOwner(nil)
    state.deathConnection = humanoid.Died:Connect(function() stopFlight(player) end)
    publish(player)
    return true
end
function Powers.register(player)
    states[player] = {god = false, infinite = false, flying = false, lastToggle = -math.huge, lastInput = -math.huge}
    publish(player)
end
function Powers.respawn(player) stopFlight(player) end
function Powers.remove(player) stopFlight(player); states[player] = nil end
function Powers.enableGod(player)
    if not Powers.allowed(player) or not states[player] then return false end
    states[player].god = true
    publish(player)
    if onChanged then onChanged(player) end
    return true
end
local function validDirection(value)
    if typeof(value) ~= "Vector3" then return false end
    for _, number in ipairs({value.X, value.Y, value.Z}) do
        if number ~= number or math.abs(number) > 1000 then return false end
    end
    return true
end
-- The sender is supplied by Roblox's server event, never a client-selected user.
-- Replicated attributes only drive UI; authorization uses server config and state.
function Powers.handle(player, action, direction)
    local state = states[player]
    if not Powers.allowed(player) or not state then return false end
    local now = os.clock()
    if action == "FlightInput" then
        if not state.flying or not validDirection(direction) or now - state.lastInput < 1 / 30 then return false end
        state.direction = direction.Magnitude > 1 and direction.Unit or direction
        state.lastInput = now
        return true
    end
    if action ~= "ToggleGod" and action ~= "ToggleInfinite" and action ~= "ToggleFlight" then return false end
    if now - state.lastToggle < 0.2 then return false end
    state.lastToggle = now
    if action == "ToggleGod" then state.god = not state.god
    elseif action == "ToggleInfinite" then state.infinite = not state.infinite
    elseif state.flying then stopFlight(player)
    elseif not startFlight(player) then return false end
    publish(player)
    if onChanged then onChanged(player) end
    return true
end
function Powers.start(changed)
    onChanged = changed
    RunService.Heartbeat:Connect(function()
        local now = os.clock()
        for player, state in pairs(states) do
            if not Powers.allowed(player) and (state.god or state.infinite or state.flying) then
                state.god, state.infinite = false, false
                stopFlight(player)
                if onChanged then onChanged(player) end
            elseif state.flying then
                if not state.root or not state.root.Parent or state.humanoid.Health <= 0 then
                    stopFlight(player)
                else
                    local direction = now - state.lastInput <= 0.5 and state.direction or Vector3.new(0, 0, 0)
                    state.velocity.VectorVelocity = direction * Config.FlySpeed
                end
            end
        end
    end)
    for _, username in ipairs(Config.AdminUsernames or {}) do
        task.spawn(function()
            local ok, id = pcall(function() return Players:GetUserIdFromNameAsync(username) end)
            if ok and type(id) == "number" and id > 0 then
                resolvedAdminIds[id] = true
                for player in pairs(states) do publish(player) end
            else warn("Admin username could not be resolved: " .. username .. ". No access was granted.") end
        end)
    end
    if Config.AutoDetectOwner and game.CreatorType == Enum.CreatorType.Group and game.CreatorId > 0 then
        task.spawn(function()
            local ok, info = pcall(function() return GroupService:GetGroupInfoAsync(game.CreatorId) end)
            if ok and type(info) == "table" and info.Owner and type(info.Owner.Id) == "number" then
                groupOwner = info.Owner.Id
                for player in pairs(states) do publish(player) end
            else warn("Group owner could not be resolved. Configure OwnerUserIds in AdminConfig if needed.") end
        end)
    end
end
return Powers
