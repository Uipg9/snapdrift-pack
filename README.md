# Snapdrift pack

Measured performance setup for Minecraft 26.3 (Fabric) on a Surface Laptop 7 (Snapdragon X Elite, Adreno X1-85).
Every mod in it earned its place in benchmarks on that laptop. The bench tool is the [snapdrift](https://github.com/Uipg9/snapdrift) mod.

## The pack

| | |
|---|---|
| Mods | Sodium, Lithium, FerriteCore, ImmediatelyFast, EntityCulling, More Culling (+ Cloth Config), Dynamic FPS, Fabric API, snapdrift |
| Render / simulation distance | 20 / 6 |
| Memory | `-Xms4G -Xmx6G -XX:+UseG1GC` |

Install into the official launcher: close the launcher, then `.\scripts\install-pack.ps1` (profile **Snapdrift**,
game dir `%APPDATA%\Snapdrift`, your keybinds and settings copied from your normal `options.txt`).
Or import `dist\Snapdrift-26.3-1.0.0.mrpack` into Prism Launcher (use its ARM64 build) or the Modrinth App.
Mods are referenced by Modrinth URL and hash, not re-bundled.

## Why this setup (Surface Laptop 7, 2026-11-25)

The GPU has no native OpenGL driver: Minecraft's OpenGL runs through Microsoft's GL-on-D3D12 translation, and vanilla's
Vulkan backend rejects the GPU (missing `VK_KHR_push_descriptor`). Java itself runs natively on ARM64.

**Mods, render distance 12** (median of 3 x 60 s flights, VSync off):

| Setup | Avg FPS | 1% low | Verdict |
|---|---|---|---|
| Vanilla | 177 | 34 | baseline |
| + Sodium | 228 | 41 | **+29%, kept** |
| + Lithium, FerriteCore, ImmediatelyFast, EntityCulling, More Culling | 229 | 41 | FPS-neutral, kept (memory, ticking, entity/HUD scenes) |
| + C2ME + ScalableLux | 229 | 42 | no gain, alpha builds: dropped |
| + Distant Horizons (default) | 5 | 4 | dropped |
| + Distant Horizons (64 chunks, cheapest settings) | 26 | 19 | dropped, also looked bad |
| + Voxy | crash | | x64-only RocksDB/LMDB natives, cannot load on ARM64 Java |

**Render distance, core set** (one fresh launch per distance, automated, median of 3):

| Render distance | Avg FPS | 1% low |
|---|---|---|
| 12 | 192 | 127 |
| 16 | 137 | 87 |
| **20 (pack default)** | **97** | **69** |
| 24 | ~70 | ~43 (warmup only) |
| 32 | ~41 | ~26 (single run) |

20 keeps a long view at a smooth frame rate. With VSync on, frames lock to an even fraction of the refresh rate;
drop to 16 for a near-locked 120 Hz.

Lessons:
- The first run in a freshly copied world is inflated (terrain not generated yet): always do a warmup run.
- Changing render distance mid-session does not fully apply (12 -> 32 at runtime measured ~220 fps; a fresh launch at
  32 measures ~41). Benchmark each distance in its own launch (`rd-sweep.ps1`).
- The dev boot test runs on emulated x64 Java, so it cannot catch x64-only native libraries (Voxy).

## Scripts

| Script | What it does |
|---|---|
| `install-pack.ps1` | Installs the pack as launcher profile **Snapdrift** (launcher closed). `-ResetOptions` reapplies `pack\options.txt` |
| `export-mrpack.ps1` | Builds `dist\Snapdrift-<mc>-<version>.mrpack` |
| `setup-bench-profiles.ps1` | Creates/refreshes the benchmark launcher profiles (launcher closed). Backs up `launcher_profiles.json` once |
| `boot-test-setups.ps1` | Boots each benchmark setup in snapdrift's client gametest and checks every mod loaded |
| `copy-bench-world.ps1` | Copies the benchmark world + route start from A-vanilla to every profile (`-Reset` restores the pristine copy) |
| `launch-direct.ps1` | Starts a profile without the launcher (launcher's ARM64 Java, offline), with optional autobench plan and per-session `-Options` |
| `rd-sweep.ps1` | One fresh launch per render distance, warmup + N runs each |
| `summarize-bench.ps1` | Median avg FPS / 1% low / p99 per setup, % vs vanilla; ignores runs with VSync on or capped FPS |

## Benchmarking by hand

1. Plug in, set Windows power mode to **Best performance**, close other apps.
2. Launcher -> profile **Snapdrift A-vanilla** -> new world `Snapdrift Bench`, Creative, **Allow cheats ON**, seed `snapdrift`.
3. Fly to a spot with varied terrain, face the direction to fly, `/snapdrift setstart`, quit.
4. `.\scripts\copy-bench-world.ps1`
5. For each profile: open the world, wait ~30 s, `/snapdrift bench warmup 60` once, then `/snapdrift bench run 60` three times.
6. `.\scripts\summarize-bench.ps1`
