<#
.SYNOPSIS
  Boots each benchmark setup's mods inside snapdrift's client gametest (dev environment) to catch
  crashes and mixin conflicts before playing. Mods are passed with -PextraMods (fabric.addMods),
  because the gametest wipes its run directory. Fabric API and snapdrift are already on the dev
  classpath, so they are skipped. Fails a setup if any of its mods is missing from the loaded mod list.
#>
param(
	[string]$Root = "$env:APPDATA\.snapdrift",
	[string]$Project = "$env:USERPROFILE\Desktop\mods\snapdrift",
	[string[]]$Only
)
$staging = Join-Path $Root "_boottest"
$log = Join-Path $Project "build\run\clientGameTest\logs\latest.log"
$csv = Join-Path $Project "build\run\clientGameTest\snapdrift\bench\results.csv"
Push-Location $Project
try {
	foreach ($dir in Get-ChildItem $Root -Directory | Where-Object Name -NotLike "_*") {
		if ($Only -and $dir.Name -notin $Only) { continue }
		if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
		New-Item -ItemType Directory -Force $staging | Out-Null
		$jars = Get-ChildItem "$($dir.FullName)\mods" -Filter *.jar |
			Where-Object { $_.Name -notlike "fabric-api-*" -and $_.Name -notlike "snapdrift-*" }
		$jars | Copy-Item -Destination $staging

		$start = Get-Date
		$out = & .\gradlew.bat runClientGameTest --console=plain "-PextraMods=$staging" 2>&1
		$ok = $LASTEXITCODE -eq 0
		$secs = [int]((Get-Date) - $start).TotalSeconds

		# Every jar's mod id must appear in the loader's mod list.
		$loaded = (Get-Content $log | Select-String "^\s+- (\S+) " | ForEach-Object { $_.Matches.Groups[1].Value })
		$missing = foreach ($j in $jars) {
			$id = $null
			try {
				Add-Type -AssemblyName System.IO.Compression.FileSystem
				$zip = [System.IO.Compression.ZipFile]::OpenRead($j.FullName)
				$entry = $zip.GetEntry("fabric.mod.json")
				$id = ((New-Object IO.StreamReader($entry.Open())).ReadToEnd() | ConvertFrom-Json).id
				$zip.Dispose()
			} catch { $id = $j.Name }
			if ($id -notin $loaded) { $id }
		}
		$perf = if (Test-Path $csv) { (Import-Csv $csv | Select-Object -Last 1).perf_mods } else { "" }
		$hit = Select-String -Path $log -Pattern "\[gametest\] gametest: (.*)" | Select-Object -Last 1
		$bench = if ($hit) { $hit.Matches.Groups[1].Value } else { "(no benchmark result)" }
		if (-not $hit) { $ok = $false }
		$crash = Get-ChildItem (Join-Path $Project "build\run\clientGameTest\crash-reports") -ErrorAction SilentlyContinue |
			Where-Object LastWriteTime -gt $start | Select-Object -First 1
		if ($crash) {
			$ok = $false
			Get-Content $crash.FullName | Select-String "^Description:|^Caused by:|Exception:" | Select-Object -First 3 |
				ForEach-Object { "             ! crash: $($_.Line.Trim())" }
		}
		$status = if ($ok -and -not $missing) { "BOOT OK" } else { "FAILED " }
		"{0,-12} {1} ({2}s) perf_mods=[{3}] {4}" -f $dir.Name, $status, $secs, $perf, $bench
		if ($missing) { "             ! not loaded: $($missing -join ', ')" }
		Select-String -Path $log -Pattern "Mixin apply failed|Incompatible mod|Exception in thread|Mod resolution failed" |
			Select-Object -First 3 | ForEach-Object { "             ! $($_.Line.Trim())" }
		if (-not $ok) { $out | Select-String "FAILED|Error|Exception" | Select-Object -First 5 | ForEach-Object { "             > $_" } }
	}
} finally {
	if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
	Pop-Location
}
