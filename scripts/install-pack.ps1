<#
.SYNOPSIS
  Installs the Snapdrift pack as a profile "Snapdrift" in the official Minecraft launcher.

  Game dir: %APPDATA%\Snapdrift. Mods come from pack\mods.txt (resolved on Modrinth, hash-checked) plus the
  snapdrift jar. options.txt starts as a copy of your normal one (keybinds etc.) with the keys in
  pack\options.txt applied (render distance 32, simulation distance 6). Existing options are kept unless
  -ResetOptions is given. The launcher must be closed.
#>
param(
	[string]$McVersion = "26.3",
	[string]$LoaderVersion = "0.20.1",
	[string]$SnapdriftJar = "$env:USERPROFILE\Desktop\mods\snapdrift\build\libs\snapdrift-1.0.0.jar",
	[string]$GameDir = "$env:APPDATA\Snapdrift",
	[string]$Root = "$env:APPDATA\.snapdrift",
	[string]$Minecraft = "$env:APPDATA\.minecraft",
	[switch]$ResetOptions
)
. (Join-Path $PSScriptRoot "common.ps1")
$packDir = Join-Path $PSScriptRoot "..\pack"

Assert-LauncherClosed
if (-not (Test-Path $SnapdriftJar)) { throw "Build snapdrift first: $SnapdriftJar not found." }
Install-FabricVersion

$slugs = Get-Content (Join-Path $packDir "mods.txt") | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith("#") }
$mods = Get-ModClosure $slugs
$modsDir = Join-Path $GameDir "mods"
New-Item -ItemType Directory -Force $modsDir | Out-Null
Get-ChildItem $modsDir -Filter *.jar | Remove-Item -Force
foreach ($m in $mods) { Copy-Item (Get-ModFile $m) $modsDir }
Copy-Item $SnapdriftJar $modsDir

$options = Join-Path $GameDir "options.txt"
if ($ResetOptions -or -not (Test-Path $options)) {
	$base = if (Test-Path "$Minecraft\options.txt") { Get-Content "$Minecraft\options.txt" } else { @() }
	$overrides = @{}
	Get-Content (Join-Path $packDir "options.txt") | Where-Object { $_ -match ":" } |
		ForEach-Object { $k, $v = $_.Split(":", 2); $overrides[$k] = $v }
	Write-Options $options $base $overrides
}
$overlay = Join-Path $packDir "overrides"
if (Test-Path $overlay) { Copy-Item -Recurse -Force "$overlay\*" $GameDir }

Set-LauncherProfile "snapdrift" "Snapdrift" $GameDir "-Xms4G -Xmx6G -XX:+UseG1GC"
$mods | ForEach-Object { "{0,-18} {1}" -f $_.Slug, $_.Version }
"Installed profile 'Snapdrift' -> $GameDir"
