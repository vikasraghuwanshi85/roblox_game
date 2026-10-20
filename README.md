# Maze Quest

A Roblox maze adventure with seven deterministic, fully connected mazes.

- Level 1: The Forgotten Garden. No boss. Step on its green button to return to the lobby (0 wins).
- Level 2: Bruno's Labyrinth. Brown walls and immortal Bruno the Bear, speed **1,000 studs per second**. Step on its green button to collect wins and return to the lobby.
- Level 3: Cally's Green Maze. Green walls and immortal Cally the Cat, speed **2,500 studs per second**. Step on its green button to collect wins and return to the lobby.
- Level 4: Wiskey's Wolf Maze. Blue walls and immortal Wiskey the Wolf, speed **10,000 studs per second**. Step on its green button to collect wins and return to the lobby.
- Level 5: Randy's Red Maze. Red walls and immortal Randy the Rat, speed **50,000 studs per second**. Step on its green button to collect wins and return to the lobby.
- Level 6: Leo's Golden Maze. Yellow walls and immortal Leo the Lion, speed **1,000,000 studs per second**. Step on its green button to collect wins and return to the lobby.
- Level 7: Han's Horse Maze. Brown walls and immortal Han the Horse, speed **10,000,000 studs per second**. Step on its green button to collect wins and return to the lobby.
- Speed training: a treadmill at every entrance adds **16 studs/sec** per two-second interaction, starting at 16 and capped at 640. Hold E nearby (or use the touch/gamepad prompt). Upgrades survive death and level changes during the session; leaving resets speed. The HUD shows your current speed.
- Players start in a shared lobby. Step on an unlocked stage pad to enter its maze. Death returns you to your current stage entrance. Completed stages unlock the next stage; unlocked stages can be replayed for wins. Wins, unlocked stages, purchased boosts, and owned/equipped trails persist across sessions.

Level 1 has no boss. Every other boss is immortal and only chases players: there are no strike prompts or damage attacks. Reward buttons are available without fighting. Configured speeds are WalkSpeed values; walls and turns can reduce actual travel speed.

## Play in Roblox Studio

No plugins or external services are required for manual setup.

1. Open a new Baseplate place in Roblox Studio. Remove the default Baseplate and SpawnLocation.
2. Create a Script named `MazeGame` in ServerScriptService and paste `src/server/init.server.lua` into it.
3. Add ModuleScripts named `Levels`, `ShopConfig`, and `SilverShop` as children of MazeGame. Paste each matching file from `src/server/` into its ModuleScript.
4. Add a ModuleScript named `TrailCatalog` under ReplicatedStorage and paste `src/shared/TrailCatalog.lua` into it.
5. Create a LocalScript named `MazeHUD` under StarterPlayer > StarterPlayerScripts and paste `src/client/init.client.lua` into it.
6. Publish to a private test experience and enable Studio API access there to test saved rewards and shop ownership. Press Play, step on the Level 1 lobby pad, find its reward button, and step on it to return to the lobby and unlock Level 2. A successful profile load is required before entering stages.

Alternatively, with Rojo 7 installed, run `rojo build default.project.json -o build/MazeQuest.rbxlx` (create `build` first), then open the generated place in Studio. Use `rojo serve default.project.json` with the Rojo Studio plugin for live syncing.

## Stage rewards and trails

Stepping on a maze's green **WinButton** saves its reward and unlocks the next stage, then teleports the player to the shared lobby. Level 1 unlocks Level 2 even though its reward is zero. Level 7 also returns to the lobby. Stage pads can be used again to replay an unlocked maze and earn its reward again; duplicate body touches or save retries cannot pay twice for the same entry. If saving fails, the player stays in the maze and can step off and retry the button.

| Stage | Wins |
| --- | --- |
| 1 | 0 |
| 2 | 1 |
| 3 | 5 |
| 4 | 15 |
| 5 | 50 |
| 6 | 100 |
| 7 | 200 |

Open **Trails** in the HUD to buy cosmetics with saved wins. Buying deducts wins once and equips the trail. Owned trails can be equipped or removed for free; equipment returns after death and rejoining. The HUD and Roblox player list show the remaining spendable wins. Trails do not change speed.

| Trail | Cost in wins |
| --- | --- |
| White | 100 |
| Green | 300 |
| Blue | 1,000 |
| Red | 10,000 |

The server owns reward amounts and prices and uses atomic DataStore writes for rewards, unlocks, and purchases. Wins and trail ownership share the existing shop profile so old Robux purchases are preserved. Reward entry records and purchase receipt records must be retained for retry deduplication.

## Customize

Edit `src/server/Levels.lua` to change maze names, sizes, deterministic random seeds, and boss presence. Add entries to extend progression. Use `WallColor` for each level's wall color, `BossSpeed` for its boss speed, and `WinReward` for its reward amount. Trail prices and colors are in `src/shared/TrailCatalog.lua`. Keep the first level's `Boss = false`. Sizes should be integers between 3 and 25; levels are spaced 500 studs apart.

## Validation

Source syntax and project JSON can be checked outside Studio. Actual movement, touch-based exits, multiplayer sessions, prompt timing, boss immortality, and chase behavior require Roblox Studio playtesting. Roblox Studio is not available in the Linux cloud environment, so gameplay has not yet been verified there.

### Treadmill playtest

In Studio, train at the first entrance and verify speed rises from 16 to 32. Repeat training, die, and advance a level to confirm upgrades remain. With two clients, confirm training affects only its user. Check that dead or distant players cannot train and that speed stops at 640. These gameplay checks require Studio and have not been run in the cloud.

## Paid products

The shared lobby and every level entrance have a training area with free, silver, gold, and god treadmills. Purchased boosts are permanent and do not stack: the highest owned multiplier applies to current base speed and future training gains. Base training speed resets when leaving; purchased tiers persist. Buying a lower or already owned tier is blocked when an equal or higher boost is active.

| Product | Effect | Price | Developer Product ID |
| --- | --- | --- | --- |
| Silver | 2.5x | 15 Robux | 3720262741 |
| Gold | 5x | 30 Robux | 3720265337 |
| God | 99x | 50 Robux | 3720265626 |
| 1m speed | Permanent 1,000,000 base speed | Read from Roblox | 3720266025 |
| Skip level | Skip one level per purchase | Read from Roblox | 3720265823 |

All five Developer Product IDs are configured in `src/server/ShopConfig.lua`. Ensure each belongs to this experience. Treadmill prices must match the listed fixed prices. The two new product buttons show prices fetched from Roblox at server startup; they stay disabled if the lookup fails. Zero disables only that tier's purchase prompt. Silver retains its configured ID and existing saved ownership.

Roblox controls checkout prices. The server checks fixed treadmill prices before enabling those prompts. Keep the treadmill prices fixed as listed; disable regional pricing and price optimization for these fixed-price products. The configured products must belong to this experience.

Receipt processing stores ownership before acknowledging payment; retried receipts never multiply a boost again. Cancelled or merely closed checkout windows grant nothing. Failed storage writes defer acknowledgment for Roblox to retry. The existing `MazeQuestSilverV1` DataStore now preserves every tier, including legacy silver ownership and the 1m speed entitlement. `SilverShop` handles every product through one `ProcessReceipt` callback; integrate future products there instead of replacing it.

Publish the experience before testing purchases. Use an isolated test experience and supported Studio purchase testing; enable Studio API access only for that test experience when testing persistence. Check cancelled and successful purchases, rejoining, lower-tier purchase prevention, both new shop buttons, all four treadmill positions, boss immortality, exits without combat, and high-speed movement through maze turns. At the 640 base speed cap, the configured maximums are 1,600 (silver), 3,200 (gold), and 63,360 (god) studs/sec; actual motion depends on Roblox physics and maze geometry. Live purchases, DataStore behavior, and movement have not been verified in Roblox Studio.

### 1m speed and skip level

The **1m speed** button unlocks a permanent base-speed floor of 1,000,000 studs/sec. It does not stack with repeat purchases, and the app blocks another checkout after ownership loads. Owned treadmill multipliers apply on top (God produces a configured 99,000,000 speed). Free training stops when base speed exceeds its 640 cap. These configured values require Studio testing for movement and collision behavior.

The **Skip level** button buys one skip, completing the current stage, awarding its configured wins, unlocking the next stage, and returning to the lobby after its receipt is saved. Each purchase ID is stored so a retried receipt cannot grant another credit. Skipping Level 7 awards 200 wins and returns to the lobby. Skip purchases are blocked while in the lobby and during a reward-button save. If a player disconnects or storage is temporarily unavailable, a paid credit remains saved; the button changes to **Use skip level** so it can be used without paying again. Consuming a credit saves the reward and unlocked stage atomically. Rejoining always starts in the lobby with saved unlocks. Existing paid checkpoints are preserved and count toward stage unlocks. Receipt records must be retained to prevent duplicate grants.

### Automated shop tests

`tests/shop_spec.lua` runs with Lua 5.3+ (`lua tests/shop_spec.lua`) or the Fengari Lua runner, from the repository root. It mocks Roblox services and makes no purchases or network requests. The tests cover receipt retries, failed storage, cancelled checkouts, price checks, highest-tier selection, legacy ownership, rejoining, offline grants, a concurrent ownership read, the 1m speed floor, skip-credit deduplication, offline skips, failed consumption, saved destinations, and dynamic product prices. The suite also checks all stage rewards, zero-win stage unlocks, insufficient balances, exact trail prices, equipment persistence, and retry-safe spending. `tests/game_spec.lua` runs the server script against mocked services and checks lobby entries, all seven reward buttons, duplicate touches, storage failure/retry, trail visuals on respawn, rejoining, skipped stages, and immortal boss setup. Run it with `lua tests/game_spec.lua` or Fengari from the repository root. These checks do not simulate Roblox physics or replace Studio playtesting.

### Studio reward and trail checks

Complete Level 1: expect 0 wins, a return to the lobby, and Level 2 unlocked. Complete each later stage and check the table above (one full pass totals 371 wins). Buy White: expect 271 wins remaining and a white movement trail. Respawn and rejoin to check balance, unlocks, ownership, and equipment persistence. Verify locked stage pads refuse entry, unaffordable purchases give no trail, and replaying a completed stage earns its reward once per completion. Test these with two clients to confirm each balance belongs to its player. Live DataStore operations, touch physics, UI layout, trail rendering, and high-speed movement still require Studio verification.
