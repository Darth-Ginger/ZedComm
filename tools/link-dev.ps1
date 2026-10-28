<#
.SYNOPSIS
Links the game's Workshop folder to the repo for day-to-day testing.

.DESCRIPTION
Creates a directory junction %USERPROFILE%\Zomboid\Workshop\ZedComm pointing
at workshop\ZedComm in this repo, so the game loads the mod straight from the
working copy. Only that folder is reachable through the link; docs, tests and
tools stay out of the game. A junction needs no administrator rights.

-Remove deletes the link only, never the folder it points at.

.EXAMPLE
.\tools\link-dev.ps1
.\tools\link-dev.ps1 -Remove
#>
[CmdletBinding()]
param(
    [switch]$Remove,
    [string]$WorkshopDir = (Join-Path $env:USERPROFILE 'Zomboid\Workshop')
)
$ErrorActionPreference = 'Stop'

$Repo   = Split-Path -Parent $PSScriptRoot
$Source = Join-Path $Repo 'workshop\ZedComm'
$target = Join-Path $WorkshopDir 'ZedComm'
$item   = Get-Item $target -Force -ErrorAction SilentlyContinue

if ($Remove) {
    if (-not $item) { Write-Host "Nothing at $target."; return }
    if (-not $item.LinkType) { throw "$target is a real folder, not the dev link. Not removing it." }
    # Non-recursive delete of a junction removes the link and leaves the repo alone.
    [System.IO.Directory]::Delete($target, $false)
    Write-Host "Removed link $target"
    return
}

if ($item) {
    $current = "$(@($item.Target)[0])".TrimEnd('\')
    if ($item.LinkType -and $current -ieq $Source.TrimEnd('\')) {
        Write-Host "Already linked: $target -> $Source"
        return
    }
    throw "$target already exists. Move it aside, or run .\tools\link-dev.ps1 -Remove if it is an old link, then rerun."
}

New-Item -ItemType Directory -Force $WorkshopDir | Out-Null
New-Item -ItemType Junction -Path $target -Target $Source | Out-Null
Write-Host "Linked $target -> $Source"
