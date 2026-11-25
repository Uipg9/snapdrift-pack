<#
.SYNOPSIS
  Creates the Snapdrift benchmark profiles (A-F) in the official Minecraft launcher.

  Each profile gets its own game directory under %APPDATA%\.snapdrift\<id> with:
    - Fabric Loader for 26.3, Fabric API and the snapdrift bench mod
    - the mods of that setup, resolved from Modrinth for 26.3/fabric (required dependencies included)
    - a copy of your options.txt with identical benchmark settings (RD 12, sim 6, VSync off, unlimited FPS)
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
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$ua = @{ "User-Agent" = "snapdrift-bench-setup/1.0" }

# Sodium beta builds are skipped on purpose: Iris/Voxy target the stable line.
$core = @("sodium", "lithium", "ferrite-core", "immediatelyfast", "entityculling", "moreculling")
$setups = [ordered]@{
	"A-vanilla" = @()
	"B-sodium"  = @("sodium")
	"C-core"    = $core
	"D-core-dh" = $core + @("distanthorizons")
	# Voxy 0.2.20 pins Sodium 0.9.2, and More Culling 1.9.2 refuses Sodium <= 0.9.3-beta.1: drop More Culling here.
	"E-core-voxy" = @($core | Where-Object { $_ -ne "moreculling" }) + @("voxy")
	"F-core-c2me" = $core + @("c2me-fabric", "scalablelux")
}

if (Get-Process -Name "Minecraft*" -ErrorAction SilentlyContinue) { throw "Close the Minecraft launcher first." }
if (-not (Test-Path $SnapdriftJar)) { throw "Build snapdrift first: $SnapdriftJar not found." }

# --- Fabric loader version json (what the Fabric installer would write) ---
$versionId = "fabric-loader-$LoaderVersion-$McVersion"
$versionDir = Join-Path $Minecraft "versions\$versionId"
if (-not (Test-Path "$versionDir\$versionId.json")) {
	New-Item -ItemType Directory -Force $versionDir | Out-Null
	Invoke-WebRequest -Headers $ua -OutFile "$versionDir\$versionId.json" `
		"https://meta.fabricmc.net/v2/versions/loader/$McVersion/$LoaderVersion/profile/json"
}

# --- Modrinth resolution (cached per run) ---
$cache = @{}
function ConvertTo-Mod($v, [string]$label) {
	$file = ($v.files | Where-Object primary | Select-Object -First 1)
	if (-not $file) { $file = $v.files[0] }
	[pscustomobject]@{ Slug = $label; ProjectId = $v.project_id; Version = $v.version_number; Type = $v.version_type
		Url = $file.url; FileName = $file.filename; Sha1 = $file.hashes.sha1
		Deps = @($v.dependencies | Where-Object dependency_type -eq "required" |
			ForEach-Object { [pscustomobject]@{ Project = $_.project_id; VersionId = $_.version_id } }) }
}

# Latest release for 26.3/fabric (falls back to the newest beta/alpha when there is no release).
function Resolve-Mod([string]$idOrSlug) {
	if ($cache.ContainsKey($idOrSlug)) { return $cache[$idOrSlug] }
	$q = "game_versions=" + [uri]::EscapeDataString("[`"$McVersion`"]") + "&loaders=" + [uri]::EscapeDataString('["fabric"]')
	$versions = Invoke-RestMethod -Headers $ua "https://api.modrinth.com/v2/project/$idOrSlug/version?$q"
	if (-not $versions) { throw "No $McVersion fabric build for '$idOrSlug'" }
	$pick = ($versions | Where-Object version_type -eq "release" | Select-Object -First 1)
	if (-not $pick) { $pick = $versions | Select-Object -First 1 }
	$cache[$idOrSlug] = ConvertTo-Mod $pick $idOrSlug
	return $cache[$idOrSlug]
}

# An exact version a dependency pins (e.g. Voxy 0.2.20 requires Sodium 0.9.2 exactly).
function Resolve-ModVersion([string]$versionId) {
	if ($cache.ContainsKey($versionId)) { return $cache[$versionId] }
	$v = Invoke-RestMethod -Headers $ua "https://api.modrinth.com/v2/version/$versionId"
	$project = Invoke-RestMethod -Headers $ua "https://api.modrinth.com/v2/project/$($v.project_id)"
	$cache[$versionId] = ConvertTo-Mod $v $project.slug
	return $cache[$versionId]
}

# One jar per project. A pinned dependency version replaces the latest build of that project.
function Get-ModClosure([string[]]$slugs) {
	$byProject = [ordered]@{}
	$pinned = @{}
	$queue = [System.Collections.Generic.Queue[object]]::new()
	foreach ($s in $slugs) { $queue.Enqueue([pscustomobject]@{ Project = $s; VersionId = $null }) }
	while ($queue.Count -gt 0) {
		$req = $queue.Dequeue()
		$m = if ($req.VersionId) { Resolve-ModVersion $req.VersionId } else { Resolve-Mod $req.Project }
		if ($byProject.Contains($m.ProjectId)) {
			$existing = $byProject[$m.ProjectId]
			if (-not $req.VersionId -or $existing.FileName -eq $m.FileName) { continue }
			if ($pinned.ContainsKey($m.ProjectId)) { throw "Conflicting pins for $($m.Slug): $($existing.Version) vs $($m.Version)" }
		}
		if ($req.VersionId) { $pinned[$m.ProjectId] = $true }
		$byProject[$m.ProjectId] = $m
		foreach ($d in $m.Deps) { $queue.Enqueue($d) }
	}
	return $byProject.Values
}

$downloads = Join-Path $Root "_downloads"
New-Item -ItemType Directory -Force $downloads | Out-Null
function Get-ModFile($m) {
	$path = Join-Path $downloads $m.FileName
	if (-not (Test-Path $path) -or (Get-FileHash -Algorithm SHA1 $path).Hash -ne $m.Sha1.ToUpper()) {
		Invoke-WebRequest -Headers $ua -OutFile $path $m.Url
		if ((Get-FileHash -Algorithm SHA1 $path).Hash -ne $m.Sha1.ToUpper()) { throw "SHA1 mismatch for $($m.FileName)" }
	}
	return $path
}

# --- Shared benchmark options ---
$overrides = @{ renderDistance = "12"; simulationDistance = "6"; enableVsync = "false"; maxFps = "260" }
$baseOptions = if (Test-Path "$Minecraft\options.txt") { Get-Content "$Minecraft\options.txt" } else { @() }
function Write-Options([string]$gameDir) {
	$lines = foreach ($l in $baseOptions) {
		$k = $l.Split(":", 2)[0]
		if ($overrides.ContainsKey($k)) { "${k}:$($overrides[$k])" } else { $l }
	}
	foreach ($k in $overrides.Keys) { if (-not ($lines -match "^${k}:")) { $lines += "${k}:$($overrides[$k])" } }
	Set-Content -Encoding UTF8 (Join-Path $gameDir "options.txt") $lines
}

# --- Profiles ---
$profilesPath = Join-Path $Minecraft "launcher_profiles.json"
$backup = "$profilesPath.snapdrift-backup"
if (-not (Test-Path $backup)) { Copy-Item $profilesPath $backup }
$launcher = Get-Content $profilesPath -Raw | ConvertFrom-Json

$report = @()
foreach ($id in $setups.Keys) {
	$gameDir = Join-Path $Root $id
	$modsDir = Join-Path $gameDir "mods"
	New-Item -ItemType Directory -Force $modsDir | Out-Null
	Get-ChildItem $modsDir -Filter *.jar | Remove-Item -Force
	$mods = Get-ModClosure (@("fabric-api") + $setups[$id])
	foreach ($m in $mods) { Copy-Item (Get-ModFile $m) $modsDir }
	Copy-Item $SnapdriftJar $modsDir
	if (-not (Test-Path (Join-Path $gameDir "options.txt"))) { Write-Options $gameDir }

	$key = "snapdrift-$id"
	$profile = [pscustomobject]@{
		name = "Snapdrift $id"; type = "custom"; lastVersionId = $versionId; gameDir = $gameDir
		javaArgs = "-Xms4G -Xmx6G -XX:+UseG1GC"; icon = "Grass"
		created = (Get-Date).ToString("o"); lastUsed = (Get-Date).ToString("o")
	}
	$launcher.profiles | Add-Member -Force -NotePropertyName $key -NotePropertyValue $profile
	$report += "{0,-12} {1}" -f $id, (($mods | ForEach-Object { "$($_.Slug)@$($_.Version)" }) -join ", ")
}
$launcher | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 $profilesPath
$report
"Profiles written. Backup of the original: $backup"
