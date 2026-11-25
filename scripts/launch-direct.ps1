<#
.SYNOPSIS
  Starts a Snapdrift profile directly (no launcher) with the launcher's native ARM64 Java, in offline mode.
  Meant for unattended runs, e.g. snapdrift autobench:

    .\launch-direct.ps1 -Profile C-core -World "Snapdrift Bench" -Plan "warmup20@20,rd20@20x3"

  Uses the libraries/assets the official launcher already downloaded (play each profile once first).
  The profile's options.txt is restored afterwards, so autobench render-distance changes do not stick.
  Blocks until the game exits.
#>
param(
	[string]$Profile,
	# Any game dir instead of a bench profile, e.g. "$env:APPDATA\Snapdrift" for the installed pack.
	[string]$GameDir,
	[string]$World,
	[string]$Plan,
	[int]$Seconds = 60,
	[int]$Settle = 30,
	[string]$Root = "$env:APPDATA\.snapdrift",
	[string]$Minecraft = "$env:APPDATA\.minecraft",
	[string]$VersionId = "fabric-loader-0.20.1-26.3",
	[string]$Java = "$env:LOCALAPPDATA\Packages\Microsoft.4297127D64EC6_8wekyb3d8bbwe\LocalCache\Local\runtime\java-runtime-epsilon\windows-arm64\java-runtime-epsilon\bin\java.exe",
	[string]$PlayerName = "Player",
	# options.txt keys to set for this session only, e.g. @{ renderDistance = "20" } (restored afterwards).
	[hashtable]$Options = @{}
)
$ErrorActionPreference = "Stop"
$gameDir = if ($GameDir) { $GameDir } elseif ($Profile) { Join-Path $Root $Profile } else { throw "Pass -Profile or -GameDir" }
if (-not $Profile) { $Profile = Split-Path -Leaf $gameDir }
if (-not (Test-Path $gameDir)) { throw "No game folder $gameDir" }
if (-not (Test-Path $Java)) { throw "ARM64 Java not found at $Java (start any 26.x version once from the launcher)" }

function Read-Version([string]$id) { Get-Content (Join-Path $Minecraft "versions\$id\$id.json") -Raw | ConvertFrom-Json }

# Launcher rule semantics: no rules = allowed; otherwise the last matching rule decides.
function Test-Rules($rules) {
	if (-not $rules) { return $true }
	$allowed = $false
	foreach ($r in $rules) {
		$match = $true
		if ($r.os) {
			if ($r.os.name -and $r.os.name -ne "windows") { $match = $false }
			if ($r.os.arch -and $r.os.arch -ne "arm64") { $match = $false }
		}
		if ($r.features) { $match = $false }
		if ($match) { $allowed = $r.action -eq "allow" }
	}
	return $allowed
}

function Get-MavenPath([string]$coords) {
	$p = $coords.Split(":")
	$file = "$($p[1])-$($p[2])" + $(if ($p.Count -gt 3) { "-$($p[3])" } else { "" }) + ".jar"
	return "$($p[0].Replace('.', '\'))\$($p[1])\$($p[2])\$file"
}

$fabric = Read-Version $VersionId
$vanilla = Read-Version $fabric.inheritsFrom

# Classpath: Fabric's libraries win over vanilla's for the same group:artifact(:classifier).
$cp = [ordered]@{}
foreach ($lib in @($fabric.libraries) + @($vanilla.libraries)) {
	if (-not (Test-Rules $lib.rules)) { continue }
	$p = $lib.name.Split(":")
	$key = "$($p[0]):$($p[1])" + $(if ($p.Count -gt 3) { ":$($p[3])" } else { "" })
	if ($cp.Contains($key)) { continue }
	$rel = if ($lib.downloads.artifact.path) { $lib.downloads.artifact.path.Replace('/', '\') } else { Get-MavenPath $lib.name }
	$path = Join-Path $Minecraft "libraries\$rel"
	if (-not (Test-Path $path)) { throw "Missing library $path (play this profile once from the launcher)" }
	$cp[$key] = $path
}
$clientJar = Join-Path $Minecraft "versions\$($vanilla.id)\$($vanilla.id).jar"
$classpath = (@($cp.Values) + $clientJar) -join ";"

$natives = Join-Path $env:TEMP "snapdrift-natives"
New-Item -ItemType Directory -Force $natives | Out-Null
$vars = @{
	natives_directory = $natives; launcher_name = "snapdrift"; launcher_version = "1"; classpath = $classpath
	auth_player_name = $PlayerName; version_name = $VersionId; game_directory = $gameDir
	assets_root = (Join-Path $Minecraft "assets"); assets_index_name = $vanilla.assetIndex.id
	auth_uuid = "00000000-0000-0000-0000-000000000000"; auth_access_token = "0"; clientid = "0"; auth_xuid = "0"
	version_type = "release"; user_type = "msa"
}
function Expand-Arg([string]$a) { [regex]::Replace($a, '\$\{(\w+)\}', { param($m) if ($vars.ContainsKey($m.Groups[1].Value)) { $vars[$m.Groups[1].Value] } else { $m.Value } }) }
function Get-Args($list) {
	foreach ($a in $list) {
		if ($a -is [string]) { Expand-Arg $a }
		elseif (Test-Rules $a.rules) { foreach ($v in @($a.value)) { Expand-Arg $v } }
	}
}

$jvm = @("-Xms4G", "-Xmx6G", "-XX:+UseG1GC") + @(Get-Args $vanilla.arguments.jvm) + @(Get-Args $fabric.arguments.jvm)
if ($World) {
	$jvm += "-Dsnapdrift.autobench.world=$World", "-Dsnapdrift.autobench.seconds=$Seconds", "-Dsnapdrift.autobench.settle=$Settle"
	if ($Plan) { $jvm += "-Dsnapdrift.autobench.plan=$Plan" }
}
$game = @(Get-Args $vanilla.arguments.game) + @(Get-Args $fabric.arguments.game)
# Drop "--flag ${unresolved}" pairs and empty values.
$clean = @()
for ($i = 0; $i -lt $game.Count; $i++) {
	if ($game[$i] -like "--*" -and $i + 1 -lt $game.Count -and $game[$i + 1] -notlike "--*") {
		if ($game[$i + 1] -notmatch '\$\{' -and $game[$i + 1] -ne "") { $clean += $game[$i], $game[$i + 1] }
		$i++
	} elseif ($game[$i] -notmatch '\$\{') { $clean += $game[$i] }
}

$options = Join-Path $gameDir "options.txt"
$optionsBackup = "$options.launch-direct"
if (Test-Path $options) { Copy-Item -Force $options $optionsBackup }
try {
	if ($Options.Count -gt 0) {
		$lines = @(if (Test-Path $options) { Get-Content $options })
		$lines = foreach ($l in $lines) { $k = $l.Split(":", 2)[0]; if ($Options.ContainsKey($k)) { "${k}:$($Options[$k])" } else { $l } }
		foreach ($k in $Options.Keys) { if (-not ($lines -match "^${k}:")) { $lines += "${k}:$($Options[$k])" } }
		Set-Content -Encoding UTF8 $options $lines
	}
	$argFile = Join-Path $env:TEMP "snapdrift-launch-$Profile.args"
	# Java @argfiles: quote every argument, escape backslashes and quotes.
	(@($jvm) + $fabric.mainClass + @($clean)) | ForEach-Object { '"' + ($_ -replace '\\', '\\' -replace '"', '\"') + '"' } |
		Set-Content -Encoding ASCII $argFile
	$proc = Start-Process -FilePath $Java -ArgumentList "@`"$argFile`"" -WorkingDirectory $gameDir -PassThru -Wait
	"exit code $($proc.ExitCode)"
} finally {
	if (Test-Path $optionsBackup) { Move-Item -Force $optionsBackup $options }
}
