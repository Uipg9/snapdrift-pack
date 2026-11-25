<#
.SYNOPSIS
  Creates the Snapdrift benchmark profiles in the official Minecraft launcher.

  Each profile gets its own game directory under %APPDATA%\.snapdrift\<id> with:
    - Fabric Loader for 26.3, Fabric API and the snapdrift bench mod
    - the mods of that setup, resolved from Modrinth for 26.3/fabric (required dependencies included)
    - a copy of your options.txt with identical benchmark settings (RD 12, sim 6, VSync off, unlimited FPS)
    - files from configs\<id>\ (e.g. mod configs), copied over the game dir
  Re-running is safe: mods folders are rebuilt, profiles are overwritten, other profiles are untouched.
  The launcher must be closed (it rewrites launcher_profiles.json on exit).
#>
param(
	[string]$McVersion = "26.3",
	[string]$LoaderVersion = "0.20.1",
	[string]$SnapdriftJar = "$env:USERPROFILE\Desktop\mods\snapdrift\build\libs\snapdrift-1.0.0.jar",
	[string]$Root = "$env:APPDATA\.snapdrift",
	[string]$Minecraft = "$env:APPDATA\.minecraft"
)
. (Join-Path $PSScriptRoot "common.ps1")

$core = @("sodium", "lithium", "ferrite-core", "immediatelyfast", "entityculling", "moreculling")
$setups = [ordered]@{
	"A-vanilla" = @()
	"B-sodium"  = @("sodium")
	"C-core"    = $core
	"D-core-dh" = $core + @("distanthorizons")
	# No E-core-voxy: Voxy 0.2.20 bundles RocksDB/LMDB natives for x64 Windows only, so it crashes on native
	# ARM64 Java ("Can't load AMD 64-bit .dll on a ARM 64-bit platform"). Revisit if Voxy ships arm64 natives.
	"F-core-c2me" = $core + @("c2me-fabric", "scalablelux")
	# Same mods as D; configs\G-core-dh-lite lowers DH to 64 chunks, coarse LODs, no SSAO/clouds/transparency.
	"G-core-dh-lite" = $core + @("distanthorizons")
}
$configRoot = Join-Path $PSScriptRoot "..\configs"
$benchOptions = @{ renderDistance = "12"; simulationDistance = "6"; enableVsync = "false"; maxFps = "260" }

Assert-LauncherClosed
if (-not (Test-Path $SnapdriftJar)) { throw "Build snapdrift first: $SnapdriftJar not found." }
Install-FabricVersion
$baseOptions = if (Test-Path "$Minecraft\options.txt") { Get-Content "$Minecraft\options.txt" } else { @() }

$report = @()
foreach ($id in $setups.Keys) {
	$gameDir = Join-Path $Root $id
	$modsDir = Join-Path $gameDir "mods"
	New-Item -ItemType Directory -Force $modsDir | Out-Null
	Get-ChildItem $modsDir -Filter *.jar | Remove-Item -Force
	$mods = Get-ModClosure (@("fabric-api") + $setups[$id])
	foreach ($m in $mods) { Copy-Item (Get-ModFile $m) $modsDir }
	Copy-Item $SnapdriftJar $modsDir
	$options = Join-Path $gameDir "options.txt"
	if (-not (Test-Path $options)) { Write-Options $options $baseOptions $benchOptions }
	$overlay = Join-Path $configRoot $id
	if (Test-Path $overlay) { Copy-Item -Recurse -Force "$overlay\*" $gameDir }

	Set-LauncherProfile "snapdrift-$id" "Snapdrift $id" $gameDir "-Xms4G -Xmx6G -XX:+UseG1GC"
	$report += "{0,-12} {1}" -f $id, (($mods | ForEach-Object { "$($_.Slug)@$($_.Version)" }) -join ", ")
}
# Drop bench profiles of setups that no longer exist (their game dirs are left alone).
$report += Remove-LauncherProfiles { $_.Name -like "snapdrift-*" -and $_.Name -ne "snapdrift" -and $_.Name.Substring(10) -notin $setups.Keys } |
	ForEach-Object { "removed profile $_" }
$report
"Profiles written. Backup of the original: $Minecraft\launcher_profiles.json.snapdrift-backup"
