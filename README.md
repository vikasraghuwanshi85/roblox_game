# Maze Quest

A Roblox maze adventure with seven deterministic, fully connected mazes.

- Level 1: The Forgotten Garden. Find the green exit; no boss.
- Level 2: Bruno's Labyrinth. Bruno the Bear chases players at **29 studs per second**. Strike Bruno three times using its proximity prompt, then reach the green exit. Yellow signals an incoming damage pulse: step back or take cover.
- Level 3: Cally's Green Maze. Green walls and Cally the Cat, who chases players at **45 studs per second**. Defeat Cally with three strikes, then find the exit to reach Level 4.
- Level 4: Wiskey's Wolf Maze. Wiskey the Wolf chases players at **90 studs per second**. Defeat Wiskey with three strikes and reach the exit to enter Level 5. Level 4 walls are blue.
- Level 5: Randy's Red Maze. Red walls and Randy the Rat, with a configured speed of **150 studs per second**. Defeat Randy with three strikes and reach the exit to enter Level 6.
- Level 6: Leo's Golden Maze. Yellow walls and Leo the Lion, with a configured speed of **320 studs per second**. Defeat Leo with three strikes and reach the exit to enter Level 7.
- Level 7: Han's Horse Maze. Han the Horse has a configured speed of **600 studs per second**. Walls use the default brown color. Defeat Han with three strikes and reach the exit to win.
- Speed training: a treadmill at every entrance adds **16 studs/sec** per two-second interaction, starting at 16 and capped at 640. Hold E nearby (or use the touch/gamepad prompt). Upgrades survive death and level changes during the session; leaving resets speed. The HUD shows your current speed.
- Progress is independent for each player. Death returns you to your current level's entrance; leaving resets progress. Boss completion is per player.

Level 1 has no boss. Level 2 features Bruno the Bear with a configured WalkSpeed of 29 studs per second; walls and turns can reduce actual travel speed.

## Play in Roblox Studio

No plugins or external services are required for manual setup.

1. Open a new Baseplate place in Roblox Studio. Remove the default Baseplate and SpawnLocation.
2. Create a Script named `MazeGame` in ServerScriptService and paste `src/server/init.server.lua` into it.
3. Add ModuleScripts named `Levels`, `ShopConfig`, and `SilverShop` as children of MazeGame. Paste each matching file from `src/server/` into its ModuleScript.
4. Create a LocalScript named `MazeHUD` under StarterPlayer > StarterPlayerScripts and paste `src/client/init.client.lua` into it.
5. Press Play. Walk through the maze using normal Roblox movement. The green exit advances your level; complete the final maze to win.

Alternatively, with Rojo 7 installed, run `rojo build default.project.json -o build/MazeQuest.rbxlx` (create `build` first), then open the generated place in Studio. Use `rojo serve default.project.json` with the Rojo Studio plugin for live syncing.

## Customize

Edit `src/server/Levels.lua` to change maze names, sizes, deterministic random seeds, and boss presence. Add entries to extend progression. Use `WallColor` for each level's wall color and `BossSpeed` for its boss speed. Keep the first level's `Boss = false`. Sizes should be integers between 3 and 25; levels are spaced 500 studs apart.

## Validation

Source syntax and project JSON can be checked outside Studio. Actual movement, touch-based exits, multiplayer sessions, prompt timing, and guardian damage require Roblox Studio playtesting. Roblox Studio is not available in the Linux cloud environment, so gameplay has not yet been verified there.

### Treadmill playtest

In Studio, train at the first entrance and verify speed rises from 16 to 32. Repeat training, die, and advance a level to confirm upgrades remain. With two clients, confirm training affects only its user. Check that dead or distant players cannot train and that speed stops at 640. These gameplay checks require Studio and have not been run in the cloud.

## Paid treadmill purchase setup

Each level entrance has a training lobby with free, silver, gold, and god treadmills. Purchased boosts are permanent and do not stack: the highest owned multiplier applies to current base speed and future training gains. Base training speed resets when leaving; purchased tiers persist. Buying a lower or already owned tier is blocked when an equal or higher boost is active.

| Treadmill | Speed multiplier | Price | Developer Product ID |
| --- | --- | --- | --- |
| Silver | 2.5x | 15 Robux | 3720262741 |
| Gold | 5x | 30 Robux | 3720265337 |
| God | 99x | 50 Robux | 3720265626 |

All three Developer Product IDs are configured in `src/server/ShopConfig.lua`. Ensure each belongs to this experience and has the listed price in Creator Dashboard. Zero disables only that tier's purchase prompt. Silver retains its configured ID and existing saved ownership.

Roblox controls checkout prices. The server checks each configured product's price before enabling its prompts. Keep the prices fixed as listed; disable regional pricing and price optimization for these fixed-price products. The configured products must belong to this experience.

Receipt processing stores ownership before acknowledging payment; retried receipts never multiply a boost again. Cancelled or merely closed checkout windows grant nothing. Failed storage writes defer acknowledgment for Roblox to retry. The existing `MazeQuestSilverV1` DataStore now preserves every tier, including legacy silver ownership. `SilverShop` handles every product through one `ProcessReceipt` callback; integrate future products there instead of replacing it.

Publish the experience before testing purchases. Use an isolated test experience and supported Studio purchase testing; enable Studio API access only for that test experience when testing persistence. Check cancelled and successful purchases, rejoining, lower-tier purchase prevention, all four treadmill positions, and high-speed movement through maze turns. At the 640 base speed cap, the configured maximums are 1,600 (silver), 3,200 (gold), and 63,360 (god) studs/sec; actual motion depends on Roblox physics and maze geometry. Live purchases, DataStore behavior, and movement have not been verified in Roblox Studio.

### Automated shop tests

`tests/shop_spec.lua` runs with Lua 5.3+ (`lua tests/shop_spec.lua`) or the Fengari Lua runner, from the repository root. It mocks Roblox services and makes no purchases or network requests. The tests cover receipt retries, failed storage, cancelled checkouts, price checks, highest-tier selection, legacy ownership, rejoining, offline grants, and a concurrent ownership read. These checks do not replace Studio purchase testing.
