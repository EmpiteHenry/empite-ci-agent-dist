<#
.SYNOPSIS
  install.ps1 - one-line installer for empite-ci-agent on Windows.

.DESCRIPTION
  The Windows counterpart to bootstrap.sh. Works two ways:

    1. One-liner (downloads the release bundle, then installs):
         irm https://raw.githubusercontent.com/EmpiteHenry/empite-ci-agent-dist/main/install.ps1 | iex

    2. From an unzipped release bundle (empite-ci-agent.exe sits next to this script):
         powershell -ExecutionPolicy Bypass -File .\install.ps1

  Installs the binary into %ProgramFiles%\empite-ci, writes
  %ProgramData%\empite-ci\agent.env (readable by SYSTEM + Administrators only)
  and installs + starts the "empite-ci-agent" Windows service (automatic,
  delayed start, restart on failure). Must run elevated.

  Settings come from parameters or, for the irm | iex one-liner, env vars:
    EMPITE_SERVER        server gRPC address, host:port (required)
    EMPITE_AGENT_SECRET  shared agent secret or org enrolment token (required)
    EMPITE_ENROLL_TOKEN  alias for EMPITE_AGENT_SECRET
    EMPITE_AGENT_LABELS  extra labels, comma-separated key=value
    EMPITE_BACKEND       auto-detect (default), docker, local or dummy
    EMPITE_GRPC_SECURE   true to dial the server with TLS
    VERSION / REPO / BASE_URL   release tag, releases repo, download base override
    ASSUME_YES=1         never prompt; fail on missing values
#>
[CmdletBinding()]
param(
    [string]$Server  = $env:EMPITE_SERVER,
    [string]$Secret  = $(if ($env:EMPITE_AGENT_SECRET) { $env:EMPITE_AGENT_SECRET } else { $env:EMPITE_ENROLL_TOKEN }),
    [string]$Labels  = $env:EMPITE_AGENT_LABELS,
    [string]$Backend = $(if ($env:EMPITE_BACKEND) { $env:EMPITE_BACKEND } else { "auto-detect" }),
    [string]$Version = $(if ($env:VERSION) { $env:VERSION } else { "latest" }),
    [string]$Repo    = $(if ($env:REPO) { $env:REPO } else { "EmpiteHenry/empite-ci-agent-dist" }),
    [string]$BaseUrl = $env:BASE_URL,
    [switch]$AssumeYes
)

$ErrorActionPreference = "Stop"
$Bin = "empite-ci-agent.exe"
if ($env:ASSUME_YES -eq "1") { $AssumeYes = $true }

function Bold($m) { Write-Host $m -ForegroundColor White }
function Ok($m)   { Write-Host "  [ok] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [! ] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "  [x] $m" -ForegroundColor Red; exit 1 }
function Ask($value, $prompt, [switch]$Secret) {
    if ($value -or $AssumeYes) { return $value }
    if ($Secret) {
        $s = Read-Host "  $prompt" -AsSecureString
        return [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
    }
    return Read-Host "  $prompt"
}

Bold "empite-ci-agent installer (Windows)"

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Die "run this from an elevated (Administrator) PowerShell"
}

# -- platform ----------------------------------------------------------------
$arch = switch ($env:PROCESSOR_ARCHITECTURE) {
    "AMD64" { "amd64" }
    default { Die "unsupported CPU arch '$($env:PROCESSOR_ARCHITECTURE)' (releases ship windows/amd64)" }
}
Ok "platform: windows/$arch"

$work = Join-Path ([IO.Path]::GetTempPath()) "empite-ci-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force -Path $work | Out-Null
try {
    # -- get the binary --------------------------------------------------------
    # Under irm | iex there is no script file, so $PSScriptRoot is empty.
    $src = $null
    if ($PSScriptRoot -and -not $BaseUrl) {
        $local = Join-Path $PSScriptRoot $Bin
        if (Test-Path $local) { $src = $local; Ok "using bundled $local" }
    }
    if (-not $src) {
        if ($BaseUrl) { $base = $BaseUrl.TrimEnd('/') }
        elseif ($Version -eq "latest") { $base = "https://github.com/$Repo/releases/latest/download" }
        else { $base = "https://github.com/$Repo/releases/download/$Version" }
        $zipName = "empite-ci-agent-windows-$arch.zip"
        $zip = Join-Path $work "bundle.zip"
        Bold "Downloading $zipName from $base"
        try {
            if ($base -like "file://*") { Copy-Item ($base.Substring(7) + "/$zipName") $zip }
            else {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -Uri "$base/$zipName" -OutFile $zip -UseBasicParsing
            }
        } catch { Die "download failed: $base/$zipName ($_)" }
        Expand-Archive -Path $zip -DestinationPath (Join-Path $work "bundle") -Force
        $src = Get-ChildItem -Path (Join-Path $work "bundle") -Recurse -Filter $Bin | Select-Object -First 1 -ExpandProperty FullName
        if (-not $src) { Die "bundle did not contain $Bin" }
        Ok "downloaded and unpacked"
    }

    # -- settings --------------------------------------------------------------
    Bold "Configuration"
    $Server = Ask $Server "server gRPC address (host:port)"
    $Secret = Ask $Secret "agent secret or org enrolment token" -Secret
    $Labels = Ask $Labels "extra labels (key=value,...; empty for none)"
    if (-not $Server) { Die "EMPITE_SERVER is required" }
    if (-not $Secret) { Die "EMPITE_AGENT_SECRET (or EMPITE_ENROLL_TOKEN) is required" }
    if ($Backend -notin @("auto-detect","docker","local","dummy")) { Die "EMPITE_BACKEND must be auto-detect, docker, local or dummy" }
    foreach ($v in @($Server, $Secret, $Labels)) { if ($v -match "[`r`n]") { Die "settings must be single-line values" } }
    $labelNote = if ($Labels) { "  labels: $Labels" } else { "" }
    Ok "server: $Server  backend: $Backend$labelNote"

    # -- install ---------------------------------------------------------------
    Bold "Installing"
    $destDir = Join-Path $env:ProgramFiles "empite-ci"
    $dest = Join-Path $destDir $Bin
    # Upgrade path: stop + drop an existing service before replacing the binary.
    if (Test-Path $dest) {
        try { & $dest service stop 2>$null | Out-Null } catch {}
        try { & $dest service uninstall 2>$null | Out-Null } catch {}
    }
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    Copy-Item -Force $src $dest
    Ok "binary -> $dest"

    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if (($machinePath -split ';') -notcontains $destDir) {
        [Environment]::SetEnvironmentVariable("Path", "$machinePath;$destDir", "Machine")
        Ok "added $destDir to the system PATH"
    }

    $pd = if ($env:ProgramData) { $env:ProgramData } else { "C:\ProgramData" }
    $confDir = Join-Path $pd "empite-ci"
    $envFile = Join-Path $confDir "agent.env"
    New-Item -ItemType Directory -Force -Path $confDir | Out-Null
    $lines = @(
        "# empite-ci-agent settings - written by install.ps1",
        "EMPITE_SERVER=$Server",
        "EMPITE_AGENT_SECRET=$Secret",
        "EMPITE_BACKEND=$Backend"
    )
    if ($Labels) { $lines += "EMPITE_AGENT_LABELS=$Labels" }
    if ($env:EMPITE_GRPC_SECURE) { $lines += "EMPITE_GRPC_SECURE=$($env:EMPITE_GRPC_SECURE)" }
    # UTF-8 without BOM: a BOM would corrupt the first key for the env parser.
    [IO.File]::WriteAllText($envFile, (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
    # The 0600 equivalent: SYSTEM + Administrators only, no inherited ACEs.
    & icacls.exe $envFile /inheritance:r /grant:r "*S-1-5-18:F" "*S-1-5-32-544:F" | Out-Null
    if ($LASTEXITCODE -ne 0) { Die "could not restrict permissions on $envFile" }
    Ok "config -> $envFile (SYSTEM + Administrators only)"

    & $dest service --config $envFile install | Out-Null
    if ($LASTEXITCODE -ne 0) { Die "service install failed" }
    & $dest service --config $envFile start | Out-Null
    if ($LASTEXITCODE -ne 0) { Die "service start failed" }
    Ok "service installed and started"
    & $dest service status
    if ($LASTEXITCODE -ne 0) { Warn "service is not running yet - check the Windows event log" }

    Write-Host ""
    Bold "Done. Uninstall with: uninstall.ps1 (add -Purge to also remove $confDir)"
} finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
