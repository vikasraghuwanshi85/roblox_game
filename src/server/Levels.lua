-- Add levels here. Level 1 deliberately has no boss.
return {
    {Name = "The Forgotten Garden", Size = 9, Seed = 142, Boss = false},
    {Name = "Bruno's Labyrinth", Size = 13, Seed = 987, Boss = true, BossName = "Bruno the Bear", BossSpeed = 29},
    {Name = "Cally's Green Maze", Size = 17, Seed = 2045, Boss = true, BossName = "Cally the Cat", BossSpeed = 45, BossKind = "Cat", WallColor = Color3.fromRGB(45, 150, 65)},
    {Name = "Wiskey's Wolf Maze", Size = 21, Seed = 4090, Boss = true, BossName = "Wiskey the Wolf", BossSpeed = 90, BossKind = "Wolf"},
}
