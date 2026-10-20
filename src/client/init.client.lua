local Players = game:GetService("Players")
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
