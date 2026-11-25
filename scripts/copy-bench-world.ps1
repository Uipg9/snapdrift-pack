<#
.SYNOPSIS
  Copies the benchmark world and saved route start from one profile to all the others, so every
  setup flies the same route over the same terrain. Also keeps a pristine copy in _pristine for
  "cold" runs (re-run with -Reset to restore every profile's world from it).
#>
param(
	[string]$World = "Snapdrift Bench",
	[string]$From = "A-vanilla",
	[string]$Root = "$env:APPDATA\.snapdrift",
	[switch]$Reset
)
$ErrorActionPreference = "Stop"
$pristine = Join-Path $Root "_pristine"
if (-not $Reset) {
	$src = Join-Path $Root "$From\saves\$World"
	$route = Join-Path $Root "$From\snapdrift\route.txt"
	if (-not (Test-Path $src)) { throw "World '$World' not found in $From. Create it there first." }
	if (-not (Test-Path $route)) { throw "No route start in $From. Run /snapdrift setstart in that world first." }
	if (Test-Path $pristine) { Remove-Item -Recurse -Force $pristine }
	New-Item -ItemType Directory -Force "$pristine\saves" | Out-Null
	Copy-Item -Recurse $src "$pristine\saves\$World"
	Copy-Item $route "$pristine\route.txt"
}
foreach ($dir in Get-ChildItem $Root -Directory | Where-Object Name -NotLike "_*") {
	if (-not $Reset -and $dir.Name -eq $From) { continue }
	$dest = Join-Path $dir.FullName "saves\$World"
	if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
	New-Item -ItemType Directory -Force (Join-Path $dir.FullName "saves"), (Join-Path $dir.FullName "snapdrift") | Out-Null
	Copy-Item -Recurse "$pristine\saves\$World" $dest
	Copy-Item "$pristine\route.txt" (Join-Path $dir.FullName "snapdrift\route.txt")
	"copied to $($dir.Name)"
}
