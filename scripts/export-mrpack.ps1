<#
.SYNOPSIS
  Builds dist\Snapdrift-<mc>-<version>.mrpack (Modrinth modpack format) from pack\mods.txt.
  Mods are referenced by Modrinth URL + hashes (not re-bundled, so mod licenses are respected).
  The snapdrift jar and pack\options.txt go in overrides/. Import it in Prism Launcher or the Modrinth App.
#>
param(
	[string]$McVersion = "26.3",
	[string]$LoaderVersion = "0.20.1",
	[string]$PackVersion = "1.0.0",
	[string]$SnapdriftJar = "$env:USERPROFILE\Desktop\mods\snapdrift\build\libs\snapdrift-1.0.0.jar",
	[string]$Root = "$env:APPDATA\.snapdrift",
	[string]$Minecraft = "$env:APPDATA\.minecraft"
)
. (Join-Path $PSScriptRoot "common.ps1")
$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
$packDir = Join-Path $repo "pack"

$slugs = Get-Content (Join-Path $packDir "mods.txt") | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith("#") }
$mods = Get-ModClosure $slugs

$index = [ordered]@{
	formatVersion = 1; game = "minecraft"; versionId = $PackVersion; name = "Snapdrift"
	summary = "Measured performance setup for Minecraft $McVersion on Snapdragon X laptops"
	files = @($mods | ForEach-Object {
		[ordered]@{ path = "mods/$($_.FileName)"; hashes = [ordered]@{ sha1 = $_.Sha1; sha512 = $_.Sha512 }
			env = [ordered]@{ client = "required"; server = "unsupported" }; downloads = @($_.Url); fileSize = $_.Size } })
	dependencies = [ordered]@{ minecraft = $McVersion; "fabric-loader" = $LoaderVersion }
}

$stage = Join-Path $env:TEMP "snapdrift-mrpack"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force "$stage\overrides\mods" | Out-Null
$index | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8NoBOM "$stage\modrinth.index.json"
Copy-Item $SnapdriftJar "$stage\overrides\mods\"
Copy-Item (Join-Path $packDir "options.txt") "$stage\overrides\options.txt"
$overlay = Join-Path $packDir "overrides"
if (Test-Path $overlay) { Copy-Item -Recurse -Force "$overlay\*" "$stage\overrides\" }

$dist = Join-Path $repo "dist"
New-Item -ItemType Directory -Force $dist | Out-Null
$out = Join-Path $dist "Snapdrift-$McVersion-$PackVersion.mrpack"
if (Test-Path $out) { Remove-Item $out }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $out)
Remove-Item -Recurse -Force $stage
"{0} ({1} mods from Modrinth + snapdrift)" -f $out, $mods.Count
