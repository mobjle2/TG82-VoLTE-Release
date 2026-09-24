#Requires -Version 5.1
<#
.SYNOPSIS
  Cai dat TG82_USB_REDIRECTOR_FIX vao D:\TOOL\TG82_USB_REDIRECTOR_FIX
#>
[CmdletBinding()]
param(
    [string]$TargetRoot = 'D:\TOOL\TG82_USB_REDIRECTOR_FIX',
    [string]$RepoOwner = 'mobjle2',
    [string]$RepoName = 'TG82-VoLTE-Release',
    [string]$Branch = 'cursor/tg82-usb-redirector-fix-e29a',
    [string]$RepoSubdir = 'TG82_USB_REDIRECTOR_FIX'
)

$ErrorActionPreference = 'Stop'

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}
catch {
    Write-Warning "Khong set duoc TLS12: $($_.Exception.Message)"
}

function Write-Step {
    param([string]$Msg)
    Write-Host ""
    Write-Host $Msg -ForegroundColor Cyan
}

function Ensure-ParentDir {
    param([Parameter(Mandatory)][string]$Path)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function Get-CurlExe {
    $cmd = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $sys = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (Test-Path -LiteralPath $sys) { return $sys }
    return $null
}

function Download-File {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$OutFile
    )
    Ensure-ParentDir -Path $OutFile
    $curl = Get-CurlExe
    if ($curl) {
        & $curl -fsSL --retry 3 --retry-delay 2 -o $OutFile $Url
        if ($LASTEXITCODE -ne 0) {
            throw "curl.exe failed ($LASTEXITCODE) for $Url"
        }
        return
    }
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
}

$ProjectFiles = @(
    'README.md',
    'Install-To-D.ps1',
    'TG82_USB_REDIRECTOR_FIX.bat',
    'TG82_USB_REDIRECTOR_FIX.ps1',
    'lib\Common.ps1',
    'lib\AutoFix.ps1',
    'lib\CollectLog.ps1'
)

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Cai dat TG82_USB_REDIRECTOR_FIX" -ForegroundColor Green
Write-Host "  -> $TargetRoot" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

Write-Step "Tao thu muc dich..."
Ensure-ParentDir -Path (Join-Path $TargetRoot '_placeholder')
if (-not (Test-Path -LiteralPath $TargetRoot)) {
    New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
}
$libDir = Join-Path $TargetRoot 'lib'
if (-not (Test-Path -LiteralPath $libDir)) {
    New-Item -ItemType Directory -Path $libDir -Force | Out-Null
}
$logsDir = Join-Path $TargetRoot 'logs'
if (-not (Test-Path -LiteralPath $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

$scriptDir = $PSScriptRoot
if (-not $scriptDir) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$localManifest = Join-Path $scriptDir 'TG82_USB_REDIRECTOR_FIX.bat'
$useLocalCopy = $false
if ($scriptDir -and (Test-Path -LiteralPath $localManifest)) {
    $missing = @()
    foreach ($rel in $ProjectFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $scriptDir $rel))) {
            $missing += $rel
        }
    }
    if ($missing.Count -eq 0) {
        $useLocalCopy = $true
    }
}

if ($useLocalCopy) {
    Write-Step "Copy tu thu muc local: $scriptDir"
    foreach ($rel in $ProjectFiles) {
        $src = Join-Path $scriptDir $rel
        $dst = Join-Path $TargetRoot $rel
        Ensure-ParentDir -Path $dst
        Copy-Item -LiteralPath $src -Destination $dst -Force
        Write-Host "  OK $rel"
    }
}
else {
    Write-Step "Tai tu GitHub raw ($Branch)..."
    $base = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Branch/$RepoSubdir"
    foreach ($rel in $ProjectFiles) {
        $url = "$base/$($rel -replace '\\','/')"
        $dst = Join-Path $TargetRoot $rel
        Write-Host "  GET $rel"
        Download-File -Url $url -OutFile $dst
    }
}

Write-Host ""
Write-Host "Cai dat xong:" -ForegroundColor Green
Write-Host "  $TargetRoot"
Write-Host ""
Write-Host "Double-click:" -ForegroundColor Yellow
Write-Host "  $(Join-Path $TargetRoot 'TG82_USB_REDIRECTOR_FIX.bat')"
Write-Host ""

try {
    Start-Process explorer.exe -ArgumentList $TargetRoot
}
catch {}

Write-Host "Nhan Enter de dong..."
[void][Console]::ReadLine()
