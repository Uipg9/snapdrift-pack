# Shared helpers, dot-sourced by the other scripts. Expects $McVersion, $LoaderVersion, $Minecraft and $Root.
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$ua = @{ "User-Agent" = "snapdrift-pack/1.0 (github.com/Uipg9/snapdrift-pack)" }
$versionId = "fabric-loader-$LoaderVersion-$McVersion"

# Fabric loader version json (what the Fabric installer would write).
function Install-FabricVersion {
	$dir = Join-Path $Minecraft "versions\$versionId"
	if (-not (Test-Path "$dir\$versionId.json")) {
		New-Item -ItemType Directory -Force $dir | Out-Null
		Invoke-WebRequest -Headers $ua -OutFile "$dir\$versionId.json" `
			"https://meta.fabricmc.net/v2/versions/loader/$McVersion/$LoaderVersion/profile/json"
	}
}

# --- Modrinth resolution (cached per run) ---
$cache = @{}
function ConvertTo-Mod($v, [string]$label) {
	$file = ($v.files | Where-Object primary | Select-Object -First 1)
	if (-not $file) { $file = $v.files[0] }
	[pscustomobject]@{ Slug = $label; ProjectId = $v.project_id; Version = $v.version_number; Type = $v.version_type
		Url = $file.url; FileName = $file.filename; Sha1 = $file.hashes.sha1; Sha512 = $file.hashes.sha512; Size = $file.size
		Deps = @($v.dependencies | Where-Object dependency_type -eq "required" |
			ForEach-Object { [pscustomobject]@{ Project = $_.project_id; VersionId = $_.version_id } }) }
}

# Latest release for the MC version on fabric (falls back to the newest beta/alpha when there is no release).
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
function Resolve-ModVersion([string]$id) {
	if ($cache.ContainsKey($id)) { return $cache[$id] }
	$v = Invoke-RestMethod -Headers $ua "https://api.modrinth.com/v2/version/$id"
	$project = Invoke-RestMethod -Headers $ua "https://api.modrinth.com/v2/project/$($v.project_id)"
	$cache[$id] = ConvertTo-Mod $v $project.slug
	return $cache[$id]
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

function Get-ModFile($m) {
	$downloads = Join-Path $Root "_downloads"
	New-Item -ItemType Directory -Force $downloads | Out-Null
	$path = Join-Path $downloads $m.FileName
	if (-not (Test-Path $path) -or (Get-FileHash -Algorithm SHA1 $path).Hash -ne $m.Sha1.ToUpper()) {
		Invoke-WebRequest -Headers $ua -OutFile $path $m.Url
		if ((Get-FileHash -Algorithm SHA1 $path).Hash -ne $m.Sha1.ToUpper()) { throw "SHA1 mismatch for $($m.FileName)" }
	}
	return $path
}

# options.txt from a base file with some keys overridden (keeps keybinds and everything else).
function Write-Options([string]$path, [string[]]$base, [hashtable]$overrides) {
	$lines = foreach ($l in $base) {
		$k = $l.Split(":", 2)[0]
		if ($overrides.ContainsKey($k)) { "${k}:$($overrides[$k])" } else { $l }
	}
	foreach ($k in $overrides.Keys) { if (-not ($lines -match "^${k}:")) { $lines += "${k}:$($overrides[$k])" } }
	Set-Content -Encoding UTF8 $path $lines
}

# Adds or replaces one launcher profile. The launcher must be closed (it rewrites the file on exit).
function Set-LauncherProfile([string]$key, [string]$name, [string]$gameDir, [string]$javaArgs) {
	$profilesPath = Join-Path $Minecraft "launcher_profiles.json"
	$backup = "$profilesPath.snapdrift-backup"
	if (-not (Test-Path $backup)) { Copy-Item $profilesPath $backup }
	$launcher = Get-Content $profilesPath -Raw | ConvertFrom-Json
	$launcher.profiles | Add-Member -Force -NotePropertyName $key -NotePropertyValue ([pscustomobject]@{
		name = $name; type = "custom"; lastVersionId = $versionId; gameDir = $gameDir; javaArgs = $javaArgs
		icon = "Grass"; created = (Get-Date).ToString("o"); lastUsed = (Get-Date).ToString("o") })
	$launcher | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 $profilesPath
}

function Remove-LauncherProfiles([scriptblock]$where) {
	$profilesPath = Join-Path $Minecraft "launcher_profiles.json"
	$launcher = Get-Content $profilesPath -Raw | ConvertFrom-Json
	$removed = @()
	foreach ($p in @($launcher.profiles.PSObject.Properties | Where-Object $where)) {
		$launcher.profiles.PSObject.Properties.Remove($p.Name); $removed += $p.Name
	}
	if ($removed) { $launcher | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 $profilesPath }
	return $removed
}

function Assert-LauncherClosed {
	if (Get-Process -Name "Minecraft" -ErrorAction SilentlyContinue) { throw "Close the Minecraft launcher first." }
}
