<#
.SYNOPSIS
  Render-distance sweep: one fresh game launch per render distance (changing it mid-session does not fully
  apply), each running a warmup plus N timed runs via snapdrift autobench. VSync off, FPS uncapped.
  Results land in the profile's bench CSV as rows named rd<N>; summarize with summarize-bench.ps1.
#>
param(
	[string]$Profile = "C-core",
	[int[]]$Distances = @(12, 16, 20, 24, 32),
	[int]$Runs = 3,
	[int]$Seconds = 60,
	[int]$Settle = 30,
	[string]$World = "Snapdrift Bench"
)
foreach ($rd in $Distances) {
	"[{0:HH:mm}] RD {1}" -f (Get-Date), $rd
	& (Join-Path $PSScriptRoot "launch-direct.ps1") -Profile $Profile -World $World -Seconds $Seconds -Settle $Settle `
		-Plan "warmup-rd$rd@$rd,rd$rd@${rd}x$Runs" `
		-Options @{ renderDistance = "$rd"; enableVsync = "false"; maxFps = "260" }
}
