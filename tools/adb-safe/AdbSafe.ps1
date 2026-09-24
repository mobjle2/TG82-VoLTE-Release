#Requires -Version 5.1
<#
.SYNOPSIS
  ADB Safe Session — reduce BSOD risk when connecting customer phones over USB/ADB.

.DESCRIPTION
  Small Windows helper for phone-repair / VoLTE support desks.
  Stops ADB before connect, isolates one device, clean disconnect, recovery helpers.
  Does NOT guarantee no BSOD — faulty cables, ports, or drivers can still crash Windows.

.NOTES
  Prefer: one known-good USB port, stock Google USB / OEM driver only, no random driver packs.
#>

[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Prepare', 'Connect', 'Status', 'Disconnect', 'Recover', 'Tips', 'Kill')]
    [string]$Action = 'Menu',

    [string]$Serial,

    [switch]$NoPause
)

$ErrorActionPreference = 'Continue'
$Script:PreferredSerial = $Serial

# --- Bilingual helpers -------------------------------------------------------

function Write-Bi {
    param(
        [Parameter(Mandatory)][string]$Vi,
        [Parameter(Mandatory)][string]$En,
        [ValidateSet('Info', 'Ok', 'Warn', 'Err', 'Title')]
        [string]$Level = 'Info'
    )
    $color = switch ($Level) {
        'Ok'    { 'Green' }
        'Warn'  { 'Yellow' }
        'Err'   { 'Red' }
        'Title' { 'Cyan' }
        default { 'White' }
    }
    Write-Host ""
    Write-Host ("[VI] " + $Vi) -ForegroundColor $color
    Write-Host ("[EN] " + $En) -ForegroundColor $color
}

function Write-Banner {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  ADB Safe Session / Phien ADB An Toan" -ForegroundColor Cyan
    Write-Host "  Risk reducer — NOT a BSOD cure" -ForegroundColor DarkYellow
    Write-Host "  Giam rui ro — KHONG chua het BSOD" -ForegroundColor DarkYellow
    Write-Host "========================================" -ForegroundColor Cyan
}

# --- ADB discovery -----------------------------------------------------------

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
        (Join-Path $PSScriptRoot 'adb.exe'),
        (Join-Path (Split-Path $PSScriptRoot -Parent) 'platform-tools\adb.exe')
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

function Invoke-Adb {
    param(
        [Parameter(Mandatory)][string[]]$AdbArgs,
        [int]$TimeoutSec = 20
    )
    $adb = Find-Adb
    if (-not $adb) {
        Write-Bi -Level Err `
            -Vi "Khong tim thay adb.exe. Cai Android platform-tools va them vao PATH." `
            -En "adb.exe not found. Install Android platform-tools and add to PATH."
        return @{ Ok = $false; ExitCode = -1; Output = @(); Adb = $null }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $adb
    $psi.Arguments = ($AdbArgs -join ' ')
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    try {
        [void]$p.Start()
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill() } catch {}
            Write-Bi -Level Warn `
                -Vi "Lenh adb het thoi gian cho ($TimeoutSec s)." `
                -En "adb command timed out ($TimeoutSec s)."
            return @{ Ok = $false; ExitCode = -2; Output = @(); Adb = $adb }
        }
        $out = @()
        $stdout = $p.StandardOutput.ReadToEnd()
        $stderr = $p.StandardError.ReadToEnd()
        if ($stdout) { $out += ($stdout -split "`r?`n" | Where-Object { $_ -ne '' }) }
        if ($stderr) { $out += ($stderr -split "`r?`n" | Where-Object { $_ -ne '' }) }
        return @{ Ok = ($p.ExitCode -eq 0); ExitCode = $p.ExitCode; Output = $out; Adb = $adb }
    }
    catch {
        Write-Bi -Level Err -Vi "Loi chay adb: $_" -En "Failed to run adb: $_"
        return @{ Ok = $false; ExitCode = -3; Output = @(); Adb = $adb }
    }
    finally {
        if ($p) { $p.Dispose() }
    }
}

function Get-AdbDevices {
    $r = Invoke-Adb -AdbArgs @('devices', '-l')
    $devices = @()
    foreach ($line in $r.Output) {
        if ($line -match '^\s*List of devices') { continue }
        if ($line -match '^\s*$') { continue }
        if ($line -match '^(\S+)\s+(\S+)(.*)$') {
            $devices += [pscustomobject]@{
                Serial = $Matches[1]
                State  = $Matches[2]
                Extra  = $Matches[3].Trim()
            }
        }
    }
    return $devices
}

function Select-OneDevice {
    param([string]$Prefer)
    $devices = Get-AdbDevices | Where-Object { $_.State -eq 'device' }
    if ($Prefer) {
        $hit = $devices | Where-Object { $_.Serial -eq $Prefer } | Select-Object -First 1
        if ($hit) { return $hit.Serial }
        Write-Bi -Level Warn `
            -Vi "Serial uu tien '$Prefer' khong online. Dang quet lai..." `
            -En "Preferred serial '$Prefer' not online. Scanning..."
    }
    if ($devices.Count -eq 0) { return $null }
    if ($devices.Count -eq 1) { return $devices[0].Serial }

    Write-Bi -Level Warn `
        -Vi "Nhieu may dang ket noi. Chi chon MOT thiet bi." `
        -En "Multiple devices connected. Pick ONE device only."
    for ($i = 0; $i -lt $devices.Count; $i++) {
        Write-Host ("  [{0}] {1}  {2}" -f ($i + 1), $devices[$i].Serial, $devices[$i].Extra)
    }
    $choice = Read-Host "Chon so / Enter number (1-$($devices.Count))"
    $idx = 0
    if (-not [int]::TryParse($choice, [ref]$idx)) { return $null }
    if ($idx -lt 1 -or $idx -gt $devices.Count) { return $null }
    return $devices[$idx - 1].Serial
}

# --- Core actions ------------------------------------------------------------

function Stop-AdbServer {
    Write-Bi -Level Info `
        -Vi "Dang dung adb server..." `
        -En "Stopping adb server..."
    $null = Invoke-Adb -AdbArgs @('kill-server') -TimeoutSec 15
    Start-Sleep -Seconds 1
}

function Start-AdbServer {
    Write-Bi -Level Info `
        -Vi "Dang khoi dong adb server..." `
        -En "Starting adb server..."
    $r = Invoke-Adb -AdbArgs @('start-server') -TimeoutSec 20
    if ($r.Ok) {
        Write-Bi -Level Ok -Vi "ADB server da chay." -En "ADB server is running."
    }
    else {
        Write-Bi -Level Warn -Vi "start-server tra ve ma $($r.ExitCode)." -En "start-server exit code $($r.ExitCode)."
    }
}

function Clear-StuckAdbProcesses {
    Write-Bi -Level Info `
        -Vi "Dang don process adb bi ket..." `
        -En "Clearing stuck adb processes..."
    $procs = Get-Process -Name 'adb' -ErrorAction SilentlyContinue
    if (-not $procs) {
        Write-Bi -Level Ok -Vi "Khong co process adb nao." -En "No adb processes found."
        return
    }
    foreach ($proc in $procs) {
        try {
            Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            Write-Host ("  Killed PID {0}" -f $proc.Id) -ForegroundColor Yellow
        }
        catch {
            Write-Host ("  Could not kill PID {0}: {1}" -f $proc.Id, $_) -ForegroundColor Red
        }
    }
    Start-Sleep -Seconds 1
    Write-Bi -Level Ok -Vi "Da xu ly process adb." -En "adb processes handled."
}

function Show-UsbHints {
    Write-Bi -Level Title `
        -Vi "Goi y khoi phuc USB (an toan, khong can malware/driver pack):" `
        -En "USB recovery hints (safe; no driver packs / malware):"
    Write-Host @"
  1) Rut day USB, doi sang 1 cong USB da biet on dinh (uu tien USB 2.0 sau).
     Unplug cable; use ONE known-good port (prefer a rear USB 2.0 port).
  2) Mo Device Manager (devmgmt.msc) -> Universal Serial Bus controllers
     -> chuot phai tung "USB Root Hub" / "USB Composite Device" lien quan -> Disable, roi Enable.
     Or: right-click problematic hub/composite device -> Disable, then Enable.
  3) Neu thiet bi hien "! " / Unknown: Go to phone Settings -> Developer options
     -> revoke USB debugging authorizations, roi cam lai va bam Allow.
  4) Tranh: Driver Genius / Driver Booster / Random USB driver packs.
     Avoid random driver update tools.
  5) Neu BSOD lap lai tren CUNG cong USB: doi cong / doi day / thu may khac
     de phan biet loi phan cung vs driver.
     If BSOD repeats on the SAME port: swap port/cable/PC to separate HW vs driver.
"@
}

function Invoke-UsbPnPRefresh {
    # Optional, documented-safe: restart PnP for USB hubs via pnputil / Disable-PnpDevice when admin.
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Bi -Level Warn `
            -Vi "Khong co quyen Admin — bo qua reset PnP USB. Chay PowerShell as Admin neu can." `
            -En "Not elevated — skipping USB PnP reset. Re-run as Admin if needed."
        Show-UsbHints
        return
    }

    Write-Bi -Level Info `
        -Vi "Dang thu Enable/Disable USB Root Hub (can Admin)..." `
        -En "Attempting USB Root Hub disable/enable (requires Admin)..."
    try {
        $hubs = Get-PnpDevice -Class 'USB' -Status OK -ErrorAction SilentlyContinue |
            Where-Object { $_.FriendlyName -match 'USB Root Hub|Generic USB Hub' }
        if (-not $hubs) {
            Write-Bi -Level Warn `
                -Vi "Khong tim thay hub USB phu hop. Xem goi y thu cong." `
                -En "No matching USB hubs found. See manual hints."
            Show-UsbHints
            return
        }
        $count = 0
        foreach ($h in ($hubs | Select-Object -First 4)) {
            try {
                Disable-PnpDevice -InstanceId $h.InstanceId -Confirm:$false -ErrorAction Stop
                Start-Sleep -Milliseconds 400
                Enable-PnpDevice -InstanceId $h.InstanceId -Confirm:$false -ErrorAction Stop
                $count++
                Write-Host ("  Reset: {0}" -f $h.FriendlyName) -ForegroundColor Green
            }
            catch {
                Write-Host ("  Skip {0}: {1}" -f $h.FriendlyName, $_.Exception.Message) -ForegroundColor Yellow
            }
        }
        Write-Bi -Level Ok `
            -Vi "Da thu reset $count hub(s). Cam lai may." `
            -En "Attempted reset on $count hub(s). Reconnect the phone."
    }
    catch {
        Write-Bi -Level Warn `
            -Vi "Reset PnP that bai: $_. Dung Device Manager thu cong." `
            -En "PnP reset failed: $_. Use Device Manager manually."
        Show-UsbHints
    }
}

function Show-HardeningTips {
    Write-Bi -Level Title `
        -Vi "Cung hoa / Hardening (giam rui ro BSOD khi ADB):" `
        -En "Hardening tips (reduce BSOD risk with ADB):"
    Write-Host @"
  * Mot cong USB on dinh — danh dau bang bang keo; dung lai moi lan.
    One known-good USB port — label it; reuse every time.
  * Day data ngan, chat luong tot; tranh hub USB re / dai.
    Short quality data cable; avoid cheap hubs / long extensions.
  * Chi cai Google USB Driver / OEM (Samsung, Xiaomi...) — khong cai driver spam.
    Install only Google USB Driver or OEM drivers — no driver spam tools.
  * Windows: Settings -> Windows Update -> Advanced -> optional updates
    -> tranh tu dong cai driver thu nghiem. Co the tat "automatic driver download":
    System Properties -> Hardware -> Device Installation Settings -> No.
    Optional: block automatic unsigned/experimental driver installs there.
  * Rut may khi khong dung; luon Disconnect sach (menu 4) truoc khi rut.
    Unplug when idle; always clean-disconnect (menu 4) before unplug.
  * Sau BSOD: Recover (menu 5) truoc khi cam lai may khach.
    After BSOD: run Recover (menu 5) before reconnecting a customer phone.
  * Tool nay GIAM RUI RO — khong bao hanh het BSOD (phan cung/driver van co the loi).
    This tool REDUCES RISK — it does not guarantee no BSOD (HW/driver can still fail).
"@
}

function Action-Prepare {
    Write-Bi -Level Title `
        -Vi "CHUAN BI phien an toan — CHUA cam may." `
        -En "PREPARE safe session — do NOT plug phone yet."
    Clear-StuckAdbProcesses
    Stop-AdbServer
    Show-HardeningTips
    Write-Bi -Level Ok `
        -Vi "San sang. Cam may vao CONG USB da chon, bat USB debugging, roi chon Connect (2)." `
        -En "Ready. Plug into the chosen USB port, enable USB debugging, then Connect (2)."
}

function Action-Connect {
    Write-Bi -Level Title `
        -Vi "Ket noi an toan (1 thiet bi)." `
        -En "Safe connect (single device)."
    Stop-AdbServer
    Start-Sleep -Milliseconds 500
    Start-AdbServer
    Start-Sleep -Seconds 1

    Write-Bi -Level Info `
        -Vi "Cam may bay gio neu chua cam. Cho 3 giay..." `
        -En "Plug the phone now if not already. Waiting 3s..."
    Start-Sleep -Seconds 3

    $serial = Select-OneDevice -Prefer $Script:PreferredSerial
    if (-not $serial) {
        Write-Bi -Level Err `
            -Vi "Khong thay thiet bi 'device'. Kiem tra cap, USB debugging, Allow RSA." `
            -En "No authorized 'device' found. Check cable, USB debugging, RSA Allow prompt."
        return
    }

    $Script:PreferredSerial = $serial
    $env:ANDROID_SERIAL = $serial
    Write-Bi -Level Ok `
        -Vi "Da chot 1 may: $serial (ANDROID_SERIAL). Chi thao tac may nay." `
        -En "Locked to one device: $serial (ANDROID_SERIAL). Work only on this phone."

    $r = Invoke-Adb -AdbArgs @('-s', $serial, 'get-state')
    Write-Host ("  get-state: " + ($r.Output -join ' '))
    Write-Bi -Level Info `
        -Vi "Khi xong viec: chon Disconnect (4), roi rut day." `
        -En "When finished: choose Disconnect (4), then unplug."
}

function Action-Status {
    $adb = Find-Adb
    if ($adb) {
        Write-Bi -Level Ok -Vi "adb: $adb" -En "adb: $adb"
    }
    else {
        Write-Bi -Level Err -Vi "Khong tim thay adb." -En "adb not found."
        return
    }
    $devices = Get-AdbDevices
    if (-not $devices -or $devices.Count -eq 0) {
        Write-Bi -Level Warn -Vi "Khong co thiet bi nao." -En "No devices listed."
    }
    else {
        Write-Bi -Level Info -Vi "Danh sach thiet bi:" -En "Device list:"
        $devices | ForEach-Object {
            Write-Host ("  {0,-24} {1,-12} {2}" -f $_.Serial, $_.State, $_.Extra)
        }
    }
    if ($Script:PreferredSerial) {
        Write-Host ("  Preferred / Dang chot: {0}" -f $Script:PreferredSerial) -ForegroundColor Cyan
    }
    $adbProcs = @(Get-Process -Name 'adb' -ErrorAction SilentlyContinue)
    Write-Host ("  adb processes: {0}" -f $adbProcs.Count)
}

function Action-Disconnect {
    Write-Bi -Level Title `
        -Vi "Ngat ket noi sach." `
        -En "Clean disconnect."
    $serial = $Script:PreferredSerial
    if (-not $serial) {
        $serial = Select-OneDevice
    }
    if ($serial) {
        Write-Bi -Level Info `
            -Vi "Thu disconnect may $serial..." `
            -En "Disconnecting device $serial..."
        $null = Invoke-Adb -AdbArgs @('-s', $serial, 'disconnect') -TimeoutSec 10
    }
    Stop-AdbServer
    Clear-StuckAdbProcesses
    Remove-Item Env:ANDROID_SERIAL -ErrorAction SilentlyContinue
    $Script:PreferredSerial = $null
    Write-Bi -Level Ok `
        -Vi "Da ngat. Ban co the RUT day USB an toan." `
        -En "Done. You may safely UNPLUG the USB cable."
}

function Action-Recover {
    Write-Bi -Level Title `
        -Vi "Khoi phuc sau ket noi loi / BSOD." `
        -En "Recovery after bad connect / BSOD."
    Write-Bi -Level Warn `
        -Vi "Doi Windows on dinh xong. Rut may khach neu van dang cam." `
        -En "Wait until Windows is stable. Unplug the customer phone if still connected."
    Clear-StuckAdbProcesses
    Stop-AdbServer
    Start-Sleep -Seconds 1
    Start-AdbServer
    Invoke-UsbPnPRefresh
    Write-Bi -Level Ok `
        -Vi "Khoi phuc co ban xong. Cam lai chi khi can, dung Prepare -> Connect." `
        -En "Basic recovery done. Reconnect only when needed via Prepare -> Connect."
}

function Action-Kill {
    Clear-StuckAdbProcesses
    Stop-AdbServer
}

# --- Menu --------------------------------------------------------------------

function Show-Menu {
    Write-Banner
    $adb = Find-Adb
    if ($adb) {
        Write-Host "  adb: $adb" -ForegroundColor DarkGray
    }
    else {
        Write-Host "  WARNING: adb.exe not found in PATH" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "  1) Prepare   — dung ADB, tips; CHUA cam may"
    Write-Host "               stop ADB + tips; do NOT plug yet"
    Write-Host "  2) Connect   — start ADB, chot 1 thiet bi"
    Write-Host "               start ADB, lock one device"
    Write-Host "  3) Status    — liet ke thiet bi / list devices"
    Write-Host "  4) Disconnect— ngat sach + kill ADB / clean unplug"
    Write-Host "  5) Recover   — sau BSOD / USB ket / after crash"
    Write-Host "  6) Tips      — hardening / meo an toan"
    Write-Host "  7) Kill ADB  — chi kill process + kill-server"
    Write-Host "  0) Exit"
    Write-Host ""
}

function Invoke-MenuLoop {
    while ($true) {
        Show-Menu
        $sel = Read-Host "Chon / Choose"
        switch ($sel) {
            '1' { Action-Prepare }
            '2' { Action-Connect }
            '3' { Action-Status }
            '4' { Action-Disconnect }
            '5' { Action-Recover }
            '6' { Show-HardeningTips }
            '7' { Action-Kill }
            '0' { break }
            'q' { break }
            'Q' { break }
            default {
                Write-Bi -Level Warn -Vi "Lua chon khong hop le." -En "Invalid choice."
            }
        }
        if (-not $NoPause) {
            Write-Host ""
            Read-Host "Nhan Enter de tiep / Press Enter" | Out-Null
        }
    }
}

# --- Entry -------------------------------------------------------------------

Write-Banner
if (-not (Find-Adb)) {
    Write-Bi -Level Warn `
        -Vi "Chua thay adb.exe — mot so chuc nang se that bai cho den khi cai platform-tools." `
        -En "adb.exe missing — some actions will fail until platform-tools are installed."
}

switch ($Action) {
    'Prepare'    { Action-Prepare }
    'Connect'    { Action-Connect }
    'Status'     { Action-Status }
    'Disconnect' { Action-Disconnect }
    'Recover'    { Action-Recover }
    'Tips'       { Show-HardeningTips }
    'Kill'       { Action-Kill }
    default      { Invoke-MenuLoop }
}

if ($Action -ne 'Menu' -and -not $NoPause) {
    Write-Host ""
    Read-Host "Nhan Enter de thoat / Press Enter to exit" | Out-Null
}
