#Requires -Version 5.1
<#
.SYNOPSIS
  Cai dat goi "Fix Xanh Man Khoi Dong lai" vao D:\TOOL\...

.DESCRIPTION
  Tao thu muc dich, copy tu thu muc script (neu co san) hoac tai tu GitHub raw.
  TLS 1.2, uu tien curl.exe, tao parent dirs, echo thanh cong, mo Explorer.
#>

[CmdletBinding()]
param(
    [string]$TargetRoot = 'D:\TOOL\Fix Xanh Màn Khởi Động lại',

    [string]$RepoOwner = 'mobjle2',
    [string]$RepoName = 'TG82-VoLTE-Release',
    [string]$Branch = 'cursor/adb-safe-bsod-tool-e134',
    [string]$RepoSubdir = 'Fix-Xanh-Man'
)

$ErrorActionPreference = 'Stop'

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {
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
    'CaiDat-Ve-O-D.ps1',
    'Fix.bat',
    'Fix.ps1'
)

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Cai dat Fix Xanh Man Khoi Dong lai" -ForegroundColor Green
Write-Host "  -> $TargetRoot" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

Write-Step "Tao thu muc dich..."

Ensure-ParentDir -Path (Join-Path $TargetRoot '_placeholder')
if (-not (Test-Path -LiteralPath $TargetRoot)) {
    New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
}

$scriptDir = $PSScriptRoot
if (-not $scriptDir) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$localManifest = Join-Path $scriptDir 'Fix.bat'
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
    Write-Step "Copy file tu thu muc script..."
    foreach ($rel in $ProjectFiles) {
        $src = Join-Path $scriptDir $rel
        $dst = Join-Path $TargetRoot $rel
        Ensure-ParentDir -Path $dst
        Copy-Item -LiteralPath $src -Destination $dst -Force
        Write-Host ("  OK  " + $rel) -ForegroundColor DarkGreen
    }
} else {
    Write-Step "Tai file tu GitHub..."
    $base = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Branch/$RepoSubdir"
    foreach ($rel in $ProjectFiles) {
        $urlRel = ($rel -replace '\\', '/')
        $url = "$base/$urlRel"
        $dst = Join-Path $TargetRoot $rel
        Write-Host ("  GET " + $urlRel) -ForegroundColor DarkYellow
        Download-File -Url $url -OutFile $dst
        Write-Host ("  OK  " + $rel) -ForegroundColor DarkGreen
    }
}

# Xoa ban cu (menu AdbSafe) neu con trong thu muc dich
$legacy = @(
    (Join-Path $TargetRoot 'Chay-AdbSafe.bat'),
    (Join-Path $TargetRoot 'adb-safe')
)
foreach ($old in $legacy) {
    if (Test-Path -LiteralPath $old) {
        Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host ("  Da xoa ban cu: " + $old) -ForegroundColor DarkGray
    }
}

$required = @(
    (Join-Path $TargetRoot 'Fix.bat'),
    (Join-Path $TargetRoot 'Fix.ps1'),
    (Join-Path $TargetRoot 'README.md')
)
foreach ($p in $required) {
    if (-not (Test-Path -LiteralPath $p)) {
        throw "Thieu file bat buoc: $p"
    }
}

Write-Host ""
Write-Host "THANH CONG — da cai vao:" -ForegroundColor Green
Write-Host "  $TargetRoot" -ForegroundColor White
Write-Host ""
Write-Host "Chay: double-click Fix.bat" -ForegroundColor Cyan
Write-Host "Giam rui ro BSOD — KHONG chua 100%." -ForegroundColor DarkYellow

try {
    Start-Process explorer.exe -ArgumentList $TargetRoot
} catch {
    Write-Warning "Khong mo duoc Explorer: $($_.Exception.Message)"
}

Write-Host ""
