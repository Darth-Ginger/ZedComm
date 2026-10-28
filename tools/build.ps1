<#
.SYNOPSIS
Builds the ZedComm Workshop item into dist\ZedComm.

.DESCRIPTION
Copies workshop\ZedComm to dist\ZedComm, leaving out .gitkeep files and
OS or file-sync droppings (@eaDir, Thumbs.db, desktop.ini, .DS_Store). Stops
before copying if the mod holds a file type the game does not use, mod.info
lacks a required key, or tests\run.ps1 (when present) fails.

-Zip also writes dist\ZedComm-<modversion>.zip.
-Deploy also copies the build into the game's Workshop folder. It refuses when
that folder is the dev link from tools\link-dev.ps1, because copying through
the link would overwrite the repo.

.EXAMPLE
.\tools\build.ps1
.\tools\build.ps1 -Zip
.\tools\build.ps1 -Deploy
#>
[CmdletBinding()]
param(
    [switch]$Deploy,
    [switch]$Zip,
    [string]$WorkshopDir = (Join-Path $env:USERPROFILE 'Zomboid\Workshop')
)
$ErrorActionPreference = 'Stop'

$Repo    = Split-Path -Parent $PSScriptRoot
$Source  = Join-Path $Repo 'workshop\ZedComm'
$Dist    = Join-Path $Repo 'dist'
$Out     = Join-Path $Dist 'ZedComm'
$ModInfo = Join-Path $Source 'Contents\mods\ZedComm\42\mod.info'

# File types a Project Zomboid mod ships. Anything else is a stray.
$Allowed = '.lua', '.txt', '.info', '.png', '.ogg', '.wav', '.bank', '.x', '.fbx', '.xml'
$problems = @()

if (-not (Test-Path $ModInfo)) { throw "mod.info not found at $ModInfo" }
$info = @{}
foreach ($line in Get-Content $ModInfo) {
    if ($line -match '^\s*([^=#]+?)\s*=\s*(.*)$') { $info[$Matches[1]] = $Matches[2].Trim() }
}
foreach ($key in 'name', 'id', 'versionMin') {
    if (-not $info[$key]) { $problems += "mod.info is missing $key" }
}

# OS and file-sync droppings are skipped rather than reported.
$Junk = '.gitkeep', 'Thumbs.db', 'desktop.ini', '.DS_Store'
$files = @(Get-ChildItem $Source -Recurse -File -Force |
    Where-Object { $Junk -notcontains $_.Name -and $_.FullName -notmatch '[\\/]@eaDir[\\/]' })
foreach ($f in $files) {
    if ($Allowed -notcontains $f.Extension.ToLower()) {
        $problems += "not a mod file: $($f.FullName.Substring($Source.Length + 1))"
    }
}
if (-not (Test-Path (Join-Path $Source 'preview.png'))) {
    Write-Warning 'workshop\ZedComm\preview.png is missing; the Workshop uploader needs it.'
}

$runner = Join-Path $Repo 'tests\run.ps1'
if (Test-Path $runner) {
    & $runner
    if ($LASTEXITCODE) { $problems += "tests failed (exit $LASTEXITCODE)" }
}

if ($problems) {
    $problems | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    throw "Build stopped: $($problems.Count) problem(s)."
}

if (Test-Path $Out) { Remove-Item $Out -Recurse -Force }
# Folders first, so required empty ones such as common\ survive.
Get-ChildItem $Source -Recurse -Directory -Force |
    Where-Object { $_.FullName -notmatch '[\\/]@eaDir([\\/]|$)' } | ForEach-Object {
    New-Item -ItemType Directory -Force (Join-Path $Out $_.FullName.Substring($Source.Length + 1)) | Out-Null
}
foreach ($f in $files) {
    Copy-Item $f.FullName (Join-Path $Out $f.FullName.Substring($Source.Length + 1))
}
Write-Host "Built $Out ($($files.Count) files, modversion $($info.modversion))"

if ($Zip) {
    $zipPath = Join-Path $Dist "ZedComm-$($info.modversion).zip"
    Compress-Archive -Path $Out -DestinationPath $zipPath -Force
    Write-Host "Zipped $zipPath"
}

if ($Deploy) {
    $target = Join-Path $WorkshopDir 'ZedComm'
    $item = Get-Item $target -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType) {
        throw "$target is the dev link to the repo. Run .\tools\link-dev.ps1 -Remove first, then deploy."
    }
    if ($item) { Remove-Item $target -Recurse -Force }
    New-Item -ItemType Directory -Force $WorkshopDir | Out-Null
    Copy-Item $Out $target -Recurse
    Write-Host "Deployed to $target"
}
