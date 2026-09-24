#Requires -Version 5.1
<#
.SYNOPSIS
  Fix — tat ADB sach truoc khi Share / Unshare TG82 Auto (giam rui ro xanh man).

.PARAMETER SauXanhMan
  Sau BSOD: tat ADB + nhac Unshare session treo trong TG82.
#>
[CmdletBinding()]
param(
    [Alias('Recover', 'AfterBsod')]
    [switch]$SauXanhMan,

    [switch]$NoPause
)

$ErrorActionPreference = 'Continue'

function Find-Adb {
    $candidates = @()
    if ($env:ANDROID_HOME) {
        $candidates += (Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe')
    }
    if ($env:ANDROID_SDK_ROOT) {
        $candidates += (Join-Path $env:ANDROID_SDK_ROOT 'platform-tools\adb.exe')
    }
    $localApp = [Environment]::GetFolderPath('LocalApplicationData')
    $candidates += @(
        (Join-Path $localApp 'Android\Sdk\platform-tools\adb.exe'),
        "$env:ProgramFiles\Android\android-sdk\platform-tools\adb.exe",
        "${env:ProgramFiles(x86)}\Android\android-sdk\platform-tools\adb.exe",
        (Join-Path $PSScriptRoot 'adb.exe')
    )
    foreach ($p in $candidates) {
        if ($p -and (Test-Path -LiteralPath $p)) {
            return (Resolve-Path -LiteralPath $p).Path
        }
    }
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }
    return $null
}

function Stop-AdbClean {
    Write-Host ""
    Write-Host "Dang tat ADB..." -ForegroundColor Cyan

    $adb = Find-Adb
    if ($adb) {
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $adb
            $psi.Arguments = 'kill-server'
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $p = [Diagnostics.Process]::Start($psi)
            if (-not $p.WaitForExit(10000)) {
                try { $p.Kill() } catch {}
            }
            $p.Dispose()
            Write-Host "  adb kill-server: OK ($adb)" -ForegroundColor DarkGreen
        }
        catch {
            Write-Host "  adb kill-server: loi — $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  Khong thay adb.exe trong PATH (van se kill process adb neu con)." -ForegroundColor Yellow
    }

    $killed = 0
    Get-Process -Name 'adb' -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Stop-Process -Id $_.Id -Force -ErrorAction Stop
            $killed++
        }
        catch {}
    }
    if ($killed -gt 0) {
        Write-Host "  Da kill $killed process adb." -ForegroundColor DarkGreen
    }
    else {
        Write-Host "  Khong con process adb." -ForegroundColor DarkGray
    }
}

# --- main --------------------------------------------------------------------

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  FIX — ADB + TG82 (giam rui ro BSOD)" -ForegroundColor Cyan
Write-Host "  KHONG chua 100% xanh man" -ForegroundColor DarkYellow
Write-Host "========================================" -ForegroundColor Cyan

Stop-AdbClean

if ($SauXanhMan) {
    Write-Host ""
    Write-Host "SAU XANH MAN:" -ForegroundColor Yellow
    Write-Host "  1) Mo TG82 Auto → Unshare / Release session treo"
    Write-Host "  2) Chi Share lai SAU KHI chay Fix.bat (ADB da tat)"
    Write-Host "  3) Roi moi connect ADB / lam VoLTE"
}
else {
    Write-Host ""
    Write-Host "Tiep theo:" -ForegroundColor Green
    Write-Host "  1) TG82 Auto → Share (1 may) → cho 3–5s → lam viec"
    Write-Host "  2) Xong: chay lai Fix.bat → roi Unshare trong TG82"
}

Write-Host ""
Write-Host "Giam rui ro — khong bao hanh het BSOD." -ForegroundColor DarkYellow
Write-Host ""

if (-not $NoPause) {
    Write-Host "Nhan Enter de dong..."
    [void][Console]::ReadLine()
}
