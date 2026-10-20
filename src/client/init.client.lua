local Players = game:GetService("Players")
local shop = game:GetService("ReplicatedStorage"):WaitForChild("MazeShop")
local purchaseRequest = shop:WaitForChild("PurchaseRequest")
local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "MazeHUD"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")
local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, -32, 0, 140)
label.Position = UDim2.fromOffset(16, 16)
label.BackgroundColor3 = Color3.fromRGB(16, 23, 35)
label.BackgroundTransparency = 0.15
label.TextColor3 = Color3.fromRGB(240, 245, 255)
label.Font = Enum.Font.GothamBold
label.TextSize = 20
label.TextWrapped = true
label.Parent = gui
Instance.new("UICorner", label).CornerRadius = UDim.new(0, 12)
local function refresh()
    local status = player:GetAttribute("MazeStatus") or "Loading maze…"
    local speed = player:GetAttribute("TrainingSpeed") or 16
    label.Text = status .. "\nSpeed: " .. speed .. " studs/sec — train +16 base speed (max 640)."
        .. "\n" .. (player:GetAttribute("ShopMessage") or "Treadmills: Silver 2.5x / 15 Robux; Gold 5x / 30; God 99x / 50. Highest boost applies.")
end
player:GetAttributeChangedSignal("MazeStatus"):Connect(refresh)
player:GetAttributeChangedSignal("TrainingSpeed"):Connect(refresh)
player:GetAttributeChangedSignal("ShopMessage"):Connect(refresh)
refresh()

local buttons = {}
for index, key in ipairs({"MillionSpeed", "SkipLevel"}) do
    local button = Instance.new("TextButton")
    button.Name = key
    button.Size = UDim2.new(0.5, -20, 0, 48)
    button.Position = UDim2.new((index - 1) * 0.5, 16, 0, 164)
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
        elseif key == "SkipLevel" and player:GetAttribute("MazeWon") then
            button.Text, button.Active = "All levels complete", false
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
for _, attribute in ipairs({"ShopReady", "MillionSpeedOwned", "SkipCredits", "MazeWon"}) do
    player:GetAttributeChangedSignal(attribute):Connect(refreshShop)
end
shop.AttributeChanged:Connect(refreshShop)
refreshShop()
