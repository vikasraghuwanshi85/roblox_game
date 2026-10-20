# Maze Quest

A Roblox maze adventure with six deterministic, fully connected mazes.

- Level 1: The Forgotten Garden. Find the green exit; no boss.
- Level 2: Bruno's Labyrinth. Bruno the Bear chases players at **29 studs per second**. Strike Bruno three times using its proximity prompt, then reach the green exit. Yellow signals an incoming damage pulse: step back or take cover.
- Level 3: Cally's Green Maze. Green walls and Cally the Cat, who chases players at **45 studs per second**. Defeat Cally with three strikes, then find the exit to reach Level 4.
- Level 4: Wiskey's Wolf Maze. Wiskey the Wolf chases players at **90 studs per second**. Defeat Wiskey with three strikes and reach the exit to enter Level 5. Level 4 walls are blue.
- Level 5: Randy's Red Maze. Red walls and Randy the Rat, with a configured speed of **150 studs per second**. Defeat Randy with three strikes and reach the exit to enter Level 6.
- Level 6: Leo's Golden Maze. Yellow walls and Leo the Lion, with a configured speed of **320 studs per second**. Defeat Leo with three strikes and reach the exit to win.
- Progress is independent for each player. Death returns you to your current level's entrance; leaving resets progress. Boss completion is per player.

Level 1 has no boss. Level 2 features Bruno the Bear with a configured WalkSpeed of 29 studs per second; walls and turns can reduce actual travel speed.

## Play in Roblox Studio

No plugins or external services are required for manual setup.

1. Open a new Baseplate place in Roblox Studio. Remove the default Baseplate and SpawnLocation.
2. Create a Script named `MazeGame` in ServerScriptService and paste `src/server/init.server.lua` into it.
3. Add a ModuleScript named `Levels` as a child of MazeGame and paste `src/server/Levels.lua` into it.
4. Create a LocalScript named `MazeHUD` under StarterPlayer > StarterPlayerScripts and paste `src/client/init.client.lua` into it.
5. Press Play. Walk through the maze using normal Roblox movement. The green exit advances your level; complete the final maze to win.

Alternatively, with Rojo 7 installed, run `rojo build default.project.json -o build/MazeQuest.rbxlx` (create `build` first), then open the generated place in Studio. Use `rojo serve default.project.json` with the Rojo Studio plugin for live syncing.

## Customize

Edit `src/server/Levels.lua` to change maze names, sizes, deterministic random seeds, and boss presence. Add entries to extend progression. Use `WallColor` for each level's wall color and `BossSpeed` for its boss speed. Keep the first level's `Boss = false`. Sizes should be integers between 3 and 25; levels are spaced 500 studs apart.

## Validation

Source syntax and project JSON can be checked outside Studio. Actual movement, touch-based exits, multiplayer sessions, prompt timing, and guardian damage require Roblox Studio playtesting. Roblox Studio is not available in the Linux cloud environment, so gameplay has not yet been verified there.
