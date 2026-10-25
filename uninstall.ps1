<#
.SYNOPSIS
  uninstall.ps1 - remove empite-ci-agent from Windows.

.DESCRIPTION
  The mirror of install.ps1: stops and uninstalls the "empite-ci-agent"
  Windows service, removes %ProgramFiles%\empite-ci and its PATH entry and,
  with -Purge (or PURGE=1), %ProgramData%\empite-ci (env file + agent state).
  Must run elevated.

    irm https://raw.githubusercontent.com/EmpiteHenry/empite-ci-agent-dist/main/uninstall.ps1 | iex
#>
[CmdletBinding()]
param([switch]$Purge)

$ErrorActionPreference = "Stop"
if ($env:PURGE -eq "1") { $Purge = $true }
$Name = "empite-ci-agent"

function Bold($m) { Write-Host $m -ForegroundColor White }
function Ok($m)   { Write-Host "  [ok] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [! ] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "  [x] $m" -ForegroundColor Red; exit 1 }

Bold "empite-ci-agent uninstaller (Windows)"

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Die "run this from an elevated (Administrator) PowerShell"
}

$destDir = Join-Path $env:ProgramFiles "empite-ci"
$dest = Join-Path $destDir "$Name.exe"

# -- service -----------------------------------------------------------------
if (Test-Path $dest) {
    try { & $dest service stop 2>$null | Out-Null } catch {}
    try { & $dest service uninstall 2>$null | Out-Null } catch {}
}
# Fallback when the binary is already gone but the service is still registered.
if (Get-Service -Name $Name -ErrorAction SilentlyContinue) {
    Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
    & sc.exe delete $Name | Out-Null
}
Ok "service removed"

# -- binary + PATH -----------------------------------------------------------
if (Test-Path $destDir) {
    Remove-Item -Recurse -Force $destDir
    Ok "removed $destDir"
} else {
    Warn "no $destDir found"
}
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$kept = ($machinePath -split ';') | Where-Object { $_ -and $_ -ne $destDir }
if (($kept -join ';') -ne $machinePath) {
    [Environment]::SetEnvironmentVariable("Path", ($kept -join ';'), "Machine")
    Ok "removed $destDir from the system PATH"
}

# -- config + state ----------------------------------------------------------
$pd = if ($env:ProgramData) { $env:ProgramData } else { "C:\ProgramData" }
$confDir = Join-Path $pd "empite-ci"
if ($Purge) {
    if (Test-Path $confDir) { Remove-Item -Recurse -Force $confDir }
    Ok "purged $confDir"
} elseif (Test-Path $confDir) {
    Warn "kept $confDir (re-run with -Purge to remove it)"
}

Bold "Done."
