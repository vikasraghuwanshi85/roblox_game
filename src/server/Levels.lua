-- Add levels here. Level 1 deliberately has no boss.
return {
    {Name = "The Forgotten Garden", Size = 9, Seed = 142, Boss = false, WinReward = 0},
    {Name = "Bruno's Labyrinth", Size = 13, Seed = 987, Boss = true, WinReward = 1, BossName = "Bruno the Bear", BossSpeed = 1000},
    {Name = "Cally's Green Maze", Size = 17, Seed = 2045, Boss = true, WinReward = 5, BossName = "Cally the Cat", BossSpeed = 2500, BossKind = "Cat", WallColor = Color3.fromRGB(45, 150, 65)},
    {Name = "Wiskey's Wolf Maze", Size = 21, Seed = 4090, Boss = true, WinReward = 15, BossName = "Wiskey the Wolf", BossSpeed = 10000, BossKind = "Wolf", WallColor = Color3.fromRGB(45, 100, 220)},
    {Name = "Randy's Red Maze", Size = 25, Seed = 5150, Boss = true, WinReward = 50, BossName = "Randy the Rat", BossSpeed = 50000, BossKind = "Rat", WallColor = Color3.fromRGB(205, 40, 40)},
    {Name = "Leo's Golden Maze", Size = 25, Seed = 6320, Boss = true, WinReward = 100, BossName = "Leo the Lion", BossSpeed = 1000000, BossKind = "Lion", WallColor = Color3.fromRGB(245, 210, 40)},
    {Name = "Han's Horse Maze", Size = 25, Seed = 7600, Boss = true, WinReward = 200, BossName = "Han the Horse", BossSpeed = 10000000, BossKind = "Horse"},
}
