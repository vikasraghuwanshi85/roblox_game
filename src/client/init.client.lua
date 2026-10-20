local Players = game:GetService("Players")
local shop = game:GetService("ReplicatedStorage"):WaitForChild("MazeShop")
local purchaseRequest = shop:WaitForChild("PurchaseRequest")
local trailRequest = shop:WaitForChild("TrailRequest")
local TrailCatalog = require(game:GetService("ReplicatedStorage"):WaitForChild("TrailCatalog"))
local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "MazeHUD"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")
local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, -32, 0, 160)
label.Position = UDim2.fromOffset(16, 16)
label.BackgroundColor3 = Color3.fromRGB(16, 23, 35)
label.BackgroundTransparency = 0.15
label.TextColor3 = Color3.fromRGB(240, 245, 255)
label.Font = Enum.Font.GothamBold
label.TextSize = 18
label.TextWrapped = true
label.Parent = gui
Instance.new("UICorner", label).CornerRadius = UDim.new(0, 12)
local function refresh()
    local status = player:GetAttribute("MazeStatus") or "Loading maze…"
    local speed = player:GetAttribute("TrainingSpeed") or 16
    label.Text = "Wins: " .. (player:GetAttribute("Wins") or 0) .. "\n" .. status .. "\nSpeed: " .. speed .. " studs/sec — train +16 base speed (max 640)."
        .. "\n" .. (player:GetAttribute("EconomyMessage") or player:GetAttribute("ShopMessage") or "Treadmills: Silver 2.5x / 15 Robux; Gold 5x / 30; God 99x / 50. Highest boost applies.")
end
player:GetAttributeChangedSignal("MazeStatus"):Connect(refresh)
player:GetAttributeChangedSignal("TrainingSpeed"):Connect(refresh)
player:GetAttributeChangedSignal("ShopMessage"):Connect(refresh)
player:GetAttributeChangedSignal("Wins"):Connect(refresh)
player:GetAttributeChangedSignal("EconomyMessage"):Connect(refresh)
refresh()

local buttons = {}
for index, key in ipairs({"MillionSpeed", "SkipLevel"}) do
    local button = Instance.new("TextButton")
    button.Name = key
    button.Size = UDim2.new(0.5, -20, 0, 48)
    button.Position = UDim2.new((index - 1) * 0.5, 16, 0, 184)
    button.BackgroundColor3 = Color3.fromRGB(40, 95, 140)
    button.TextColor3 = Color3.new(1, 1, 1)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 16
    button.TextWrapped = true
    button.Parent = gui
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 10)
    buttons[key] = button
    button.Activated:Connect(function()
        if button.Active then purchaseRequest:FireServer(key) end
    end)
end
local function refreshShop()
    for key, button in pairs(buttons) do
        local name = key == "MillionSpeed" and "1m base speed" or "Skip level"
        local price = shop:GetAttribute(key .. "Price")
        local available = shop:GetAttribute(key .. "Available") and player:GetAttribute("ShopReady") and price ~= nil
        local credits = player:GetAttribute("SkipCredits") or 0
        if key == "MillionSpeed" and player:GetAttribute("MillionSpeedOwned") then
            button.Text, button.Active = name .. " — Owned", false
        elseif key == "SkipLevel" and (player:GetAttribute("CurrentMazeLevel") or 0) < 1 then
            button.Text, button.Active = "Enter a stage to skip", false
        elseif key == "SkipLevel" and credits > 0 and player:GetAttribute("ShopReady") then
            button.Text, button.Active = "Use skip level (" .. credits .. " saved)", true
        else
            button.Text = name .. (available and (" — " .. price .. " Robux") or " — Unavailable")
            button.Active = available and price ~= nil or false
        end
        button.AutoButtonColor = button.Active
        button.BackgroundTransparency = button.Active and 0 or 0.45
    end
end
for _, attribute in ipairs({"ShopReady", "MillionSpeedOwned", "SkipCredits", "MazeWon", "CurrentMazeLevel"}) do
    player:GetAttributeChangedSignal(attribute):Connect(refreshShop)
end
shop.AttributeChanged:Connect(refreshShop)
refreshShop()

-- Trail purchases spend wins; equipment is saved and restored on respawn.
local openTrails = Instance.new("TextButton")
openTrails.Name = "OpenTrailShop"
openTrails.Size = UDim2.fromOffset(190, 42)
openTrails.Position = UDim2.new(1, -206, 0, 244)
openTrails.BackgroundColor3 = Color3.fromRGB(85, 60, 140)
openTrails.TextColor3 = Color3.new(1, 1, 1)
openTrails.Font, openTrails.TextSize = Enum.Font.GothamBold, 16
openTrails.Parent = gui
Instance.new("UICorner", openTrails).CornerRadius = UDim.new(0, 10)
local panel = Instance.new("Frame")
panel.Name = "TrailShop"
panel.Size = UDim2.new(0.9, 0, 0.85, 0)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.BackgroundColor3 = Color3.fromRGB(24, 30, 45)
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
local constraint = Instance.new("UISizeConstraint")
constraint.MaxSize = Vector2.new(540, 330)
constraint.Parent = panel
local title = Instance.new("TextLabel")
title.Size, title.Position = UDim2.new(1, -80, 0, 48), UDim2.fromOffset(16, 4)
title.BackgroundTransparency = 1
title.TextColor3, title.Font, title.TextSize = Color3.new(1, 1, 1), Enum.Font.GothamBold, 20
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel
local close = Instance.new("TextButton")
close.Size, close.Position = UDim2.fromOffset(40, 36), UDim2.new(1, -52, 0, 10)
close.Text = "X"
close.Parent = panel
openTrails.Activated:Connect(function() panel.Visible = not panel.Visible end)
close.Activated:Connect(function() panel.Visible = false end)
local rows = Instance.new("ScrollingFrame")
rows.Name = "Trails"
rows.Position = UDim2.fromOffset(0, 58)
rows.Size = UDim2.new(1, 0, 1, -68)
rows.BackgroundTransparency = 1
rows.BorderSizePixel = 0
rows.ScrollBarThickness = 6
rows.ScrollingDirection = Enum.ScrollingDirection.Y
rows.CanvasSize = UDim2.fromOffset(0, #TrailCatalog * 62)
rows.Parent = panel
local trailButtons = {}
for index, config in ipairs(TrailCatalog) do
    local button = Instance.new("TextButton")
    button.Name = config.Key
    button.Size = UDim2.new(1, -32, 0, 52)
    button.Position = UDim2.fromOffset(16, (index - 1) * 62)
    local rgb = config.Colors[1]
    button.BackgroundColor3 = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
    button.TextColor3, button.Font, button.TextSize = Color3.fromRGB(15, 20, 30), Enum.Font.GothamBold, 17
    button.TextWrapped = true
    button.Parent = rows
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 10)
    trailButtons[config.Key] = button
    button.Activated:Connect(function()
        if not button.Active then return end
        local owned = player:GetAttribute("OwnsTrail_" .. config.Key)
        local equipped = player:GetAttribute("EquippedTrail") == config.Key
        local action = not owned and "Buy" or (equipped and "Unequip" or "Equip")
        trailRequest:FireServer(config.Key, action)
    end)
end
local function refreshTrails()
    local wins = player:GetAttribute("Wins") or 0
    openTrails.Text = "Trails — " .. wins .. " wins"
    title.Text = "Trail shop — " .. wins .. " wins"
    for _, config in ipairs(TrailCatalog) do
        local button = trailButtons[config.Key]
        local owned = player:GetAttribute("OwnsTrail_" .. config.Key)
        local equipped = player:GetAttribute("EquippedTrail") == config.Key
        button.Text = config.Name .. (equipped and " — Equipped (remove)" or (owned and " — Equip" or (" — Buy: " .. config.Price .. " wins")))
        button.Active = player:GetAttribute("ShopReady") and true or false
        button.AutoButtonColor = button.Active
        button.BackgroundTransparency = (owned or wins >= config.Price) and 0 or 0.4
    end
end
for _, name in ipairs({"Wins", "EquippedTrail", "ShopReady"}) do
    player:GetAttributeChangedSignal(name):Connect(refreshTrails)
end
for _, config in ipairs(TrailCatalog) do
    player:GetAttributeChangedSignal("OwnsTrail_" .. config.Key):Connect(refreshTrails)
end
refreshTrails()
