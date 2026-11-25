<#
.SYNOPSIS
  Reads every profile's snapdrift\bench\results.csv and prints one line per setup and run name:
  the median of avg FPS, 1% low and p99 over its runs, plus the change against A-vanilla.
  Rows whose run conditions were not controlled (VSync on, FPS capped) are listed separately and ignored.
#>
param([string]$Root = "$env:APPDATA\.snapdrift")

function Get-Median([double[]]$xs) {
	$s = $xs | Sort-Object
	$n = $s.Count
	if ($n -eq 0) { return [double]::NaN }
	if ($n % 2) { return $s[($n - 1) / 2] }
	return ($s[$n / 2 - 1] + $s[$n / 2]) / 2
}

$rows = foreach ($dir in Get-ChildItem $Root -Directory | Where-Object Name -NotLike "_*") {
	$f = Join-Path $dir.FullName "snapdrift\bench\results.csv"
	if (Test-Path $f) { Import-Csv $f | ForEach-Object { $_ | Add-Member -PassThru setup $dir.Name } }
}
if (-not $rows) { "No results yet."; return }

$bad = $rows | Where-Object { $_.vsync -eq "true" -or [int]$_.fps_limit -lt 260 }
$good = $rows | Where-Object { $_.vsync -ne "true" -and [int]$_.fps_limit -ge 260 }

$table = foreach ($g in $good | Group-Object setup, name) {
	$r = $g.Group
	[pscustomobject]@{
		Setup = $r[0].setup; Run = $r[0].name; N = $r.Count
		AvgFps = [math]::Round((Get-Median ($r | ForEach-Object { [double]$_.avg_fps })), 1)
		Low1 = [math]::Round((Get-Median ($r | ForEach-Object { [double]$_.low1_fps })), 1)
		P99ms = [math]::Round((Get-Median ($r | ForEach-Object { [double]$_.p99_ms })), 1)
		RD = $r[0].render_distance
		Mods = $r[0].perf_mods
	}
}
$base = $table | Where-Object Setup -eq "A-vanilla" | Select-Object -First 1
$table | Sort-Object Setup, Run | ForEach-Object {
	$delta = if ($base -and $base.AvgFps -gt 0) { "{0:+0;-0}%" -f (100 * ($_.AvgFps / $base.AvgFps - 1)) } else { "" }
	$_ | Add-Member -PassThru VsVanilla $delta
} | Format-Table Setup, Run, N, AvgFps, Low1, P99ms, VsVanilla, RD, Mods -AutoSize | Out-String -Width 220

if ($bad) { "Ignored $($bad.Count) uncontrolled run(s) (VSync on or FPS capped): " + (($bad | ForEach-Object { "$($_.setup)/$($_.name)" }) -join ", ") }
$few = $table | Where-Object N -lt 3
if ($few) { "Fewer than 3 runs: " + (($few | ForEach-Object { "$($_.Setup)/$($_.Run)" }) -join ", ") }
