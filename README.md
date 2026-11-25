# Snapdrift pack (work in progress)

Performance setup for Minecraft 26.3 (Fabric) on a Surface Laptop 7 (Snapdragon X Elite, Adreno X1-85).
Measure first, keep only mods that win. The bench tool is the [snapdrift](https://github.com/Uipg9/snapdrift) mod.

## Benchmark setups (official launcher profiles, game dirs in `%APPDATA%\.snapdrift\<id>`)

| Profile | Mods (plus Fabric API + snapdrift) |
|---|---|
| A-vanilla | none |
| B-sodium | Sodium 0.9.3 |
| C-core | Sodium, Lithium, FerriteCore, ImmediatelyFast, EntityCulling, More Culling (+ Cloth Config) |
| D-core-dh | core + Distant Horizons |
| E-core-voxy | core + Voxy, **with Sodium 0.9.2 and without More Culling** (Voxy 0.2.20 pins Sodium 0.9.2; More Culling 1.9.2 refuses it) |
| F-core-c2me | core + C2ME (alpha) + ScalableLux (alpha) |

All six boot with every mod loaded (`scripts\boot-test-setups.ps1`).

## Scripts

| Script | What it does |
|---|---|
| `setup-bench-profiles.ps1` | Creates/refreshes the six launcher profiles (launcher must be closed). Backs up `launcher_profiles.json` once |
| `boot-test-setups.ps1` | Boots each setup in snapdrift's client gametest and checks every mod loaded |
| `copy-bench-world.ps1` | Copies the benchmark world + route start from A-vanilla to every profile (`-Reset` restores the pristine copy) |
| `summarize-bench.ps1` | Median avg FPS / 1% low / p99 per setup, % vs vanilla; ignores runs with VSync on or capped FPS |

## Running the benchmark

1. Plug in, set Windows power mode to **Best performance**, close other apps.
2. Launcher -> profile **Snapdrift A-vanilla** -> new world named `Snapdrift Bench`, Creative, **Allow cheats ON**, seed `snapdrift`.
3. Fly to a spot with varied terrain, face the direction to fly, `/snapdrift setstart`, quit the game.
4. `.\scripts\copy-bench-world.ps1`
5. For each profile A-F: open the world, wait ~30 s (D/E: until LOD building finishes), then run
   `/snapdrift bench run 60` three times, keeping the window focused and hands off.
6. `.\scripts\summarize-bench.ps1`
