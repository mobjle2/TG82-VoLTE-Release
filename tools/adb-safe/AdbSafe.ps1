#Requires -Version 5.1
<#
.SYNOPSIS
  ADB Safe Session — reduce BSOD risk with local USB or TG82 Auto / USB Redirector + ADB.

.DESCRIPTION
  Windows helper for phone-repair / VoLTE desks.
  Operator evidence: BSOD can happen immediately when attaching a phone via
  "USB Redirector TG82 Auto" then using ADB — treat redirect as a first-class path.

  Workflow-friendly: stop ADB before attach, one device only, kill ADB before
  releasing redirect, recovery after crash. Does NOT guarantee no BSOD.

.NOTES
  Redirect stacks use kernel USB filter/virtual-bus drivers; attach+ADB races
  are a known risk class for USB-over-IP tools in general. Prefer ordered steps.
#>

[CmdletBinding()]
param(
    [ValidateSet(
        'Menu', 'Prepare', 'PrepareTg82', 'Connect', 'Status',
        'Disconnect', 'DisconnectTg82', 'Recover', 'Tips', 'Kill', 'Checklist'
    )]
    [string]$Action = 'Menu',

    [string]$Serial,

    [switch]$NoPause
)

$ErrorActionPreference = 'Continue'
$Script:PreferredSerial = $Serial
$Script:SessionMode = $null  # 'Local' | 'Tg82'

# Process / window name hints for TG82 Auto / USB Redirector (best-effort).
$Script:RedirectProcessHints = @(
    'TG82',
    'TG82 Auto',
    'TG82Auto',
    'USB Redirector',
    'USBRedirector',
    'usbredirector',
    'tusbd',
    'IncentivesPro'
)

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
    Write-Host "  Local USB  +  TG82 Auto / USB Redirector" -ForegroundColor Cyan
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
        -Vi "Nhieu may dang ket noi. Chi chon MOT thiet bi (redirect + ADB de crash hon)." `
        -En "Multiple devices connected. Pick ONE only (redirect + ADB raises crash risk)."
    for ($i = 0; $i -lt $devices.Count; $i++) {
        Write-Host ("  [{0}] {1}  {2}" -f ($i + 1), $devices[$i].Serial, $devices[$i].Extra)
    }
    $choice = Read-Host "Chon so / Enter number (1-$($devices.Count))"
    $idx = 0
    if (-not [int]::TryParse($choice, [ref]$idx)) { return $null }
    if ($idx -lt 1 -or $idx -gt $devices.Count) { return $null }
    return $devices[$idx - 1].Serial
}

# --- Redirect / TG82 detection -----------------------------------------------

function Get-RedirectHints {
    $found = @()
    try {
        $procs = Get-Process -ErrorAction SilentlyContinue
        foreach ($proc in $procs) {
            $name = $proc.ProcessName
            $title = ''
            try { $title = $proc.MainWindowTitle } catch {}
            foreach ($hint in $Script:RedirectProcessHints) {
                if ($name -like "*$hint*" -or ($title -and $title -like "*$hint*")) {
                    $found += [pscustomobject]@{
                        Pid     = $proc.Id
                        Name    = $name
                        Title   = $title
                        Matched = $hint
                    }
                    break
                }
            }
        }
    }
    catch {}

    # Kernel driver / service names commonly shipped with USB Redirector products
    # (IncentivesPro uses tusbd.sys / dpnptls — presence alone is not a bug).
    $driverHints = @('tusbd', 'dpnptls', 'usbredirector')
    foreach ($svcName in $driverHints) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc) {
            $found += [pscustomobject]@{
                Pid     = $null
                Name    = ("service:" + $svc.Name)
                Title   = $svc.Status
                Matched = $svcName
            }
        }
    }
    return $found
}

function Show-RedirectStatus {
    $hits = @(Get-RedirectHints)
    if ($hits.Count -eq 0) {
        Write-Bi -Level Info `
            -Vi "Chua thay process/service TG82 Auto / USB Redirector (co the ten khac)." `
            -En "No TG82 Auto / USB Redirector process/service detected (name may differ)."
        return $false
    }
    Write-Bi -Level Warn `
        -Vi "Phat hien goi y redirect/TG82 (kernel USB stack dang/co the chay):" `
        -En "Redirect/TG82 hints detected (USB redirect stack may be active):"
    foreach ($h in $hits) {
        if ($h.Pid) {
            Write-Host ("  PID {0}  {1}  [{2}]  {3}" -f $h.Pid, $h.Name, $h.Matched, $h.Title)
        }
        else {
            Write-Host ("  {0}  status={1}  [{2}]" -f $h.Name, $h.Title, $h.Matched)
        }
    }
    return $true
}

# --- Core ADB helpers --------------------------------------------------------

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
        -Vi "Goi y khoi phuc USB (an toan):" `
        -En "USB recovery hints (safe):"
    Write-Host @"
  1) Neu dung TG82 Auto: kill ADB (menu 9) TRUOC, roi Unshare trong app,
     roi moi rut day o may khach.
     If using TG82 Auto: kill ADB (menu 9) FIRST, then Unshare in the app,
     then unplug the customer-side cable.
  2) Rut day / Unshare, doi 5-10s, dung 1 thiet bi duy nhat.
     Unplug / Unshare, wait 5-10s, keep a single device only.
  3) Device Manager -> USB controllers: Disable/Enable USB Root Hub lien quan.
  4) Tranh Driver Genius / Driver Booster / random USB packs.
  5) Neu BSOD lap lai ngay khi Share tren TG82: doi cong/cap o may khach,
     thu Share khi ADB da kill (menu 8), ghi lai STOP code.
"@
}

function Invoke-UsbPnPRefresh {
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
            -Vi "Da thu reset $count hub(s)." `
            -En "Attempted reset on $count hub(s)."
    }
    catch {
        Write-Bi -Level Warn `
            -Vi "Reset PnP that bai: $_. Dung Device Manager thu cong." `
            -En "PnP reset failed: $_. Use Device Manager manually."
        Show-UsbHints
    }
}

function Show-Tg82OrderedSteps {
    Write-Bi -Level Title `
        -Vi "THU TU BAT BUOC (TG82 Auto Share + ADB):" `
        -En "REQUIRED ORDER (TG82 Auto Share + ADB):"
    Write-Host @"

  kill ADB  ->  TG82 Share  ->  Connect(ADB)  ->  work
       ->  Disconnect/kill ADB  ->  TG82 Unshare

  === KET NOI / CONNECT ===
  A1. Menu 8 Prepare TG82  =  kill ADB (+ kill-server). BAT BUOC truoc Share.
  A2. TG82 Auto: Share / Attach DUNG MOT may khach. (chua chay adb)
  A3. Doi 3-5s cho device on dinh.
  A4. Menu 2 Connect       =  start ADB, chot 1 serial, roi lam viec VoLTE.

  === NGAT / DISCONNECT ===
  B1. Dong tool VoLTE / lenh adb dang chay.
  B2. Menu 9 Disconnect TG82  =  kill ADB TRUOC.
  B3. TG82 Auto: Unshare / Release / Stop session.
  B4. Doi 2-3s; rut day o may khach chi SAU Unshare.

  === SAU BSOD (crash ngay khi connect qua TG82 Auto) ===
  C1. Boot xong — CHUA Share lai.
  C2. Menu 5 Recover.
  C3. TG82: Unshare moi session treo / Exit app neu can.
  C4. Chi Share lai sau menu 8 (ADB da tat).

  Van DUNG duoc TG82 (can remote USB) — chi can dung DUNG THU TU.
"@
}

function Show-HardeningTips {
    Write-Bi -Level Title `
        -Vi "Cung hoa / Hardening (Local USB + TG82 Redirect):" `
        -En "Hardening tips (Local USB + TG82 Redirect):"
    Write-Host @"
  * Xu huong rui ro cao: USB Redirector TG82 Auto + phien ADB (bang chung
    operator: BSOD + reboot NGAY khi connect qua TG82 Auto).
    High-risk path: TG82 Auto USB Redirector + ADB session (operator: BSOD
    immediately on connect via TG82 Auto).
  * Luon kill ADB truoc Share va truoc Unshare (menu 8 / 9).
    Always stop ADB before Share and before Unshare (menus 8 / 9).
  * Mot thiet bi duy nhat — khong tron may local + redirect.
    One device only — never mix local USB phone + redirected phone.
  * Tranh adb push/file lon ngay sau Share; doi on dinh roi moi transfer.
    Avoid large adb push right after Share; wait until stable.
  * Mot cong USB on dinh o may KHACH; day data ngan.
    One known-good port on the CUSTOMER PC; short data cable.
  * Chi Google USB / OEM driver — khong Driver Booster.
  * Sau BSOD: ghi STOP code (vd. tu Automatic Repair / Event Viewer) de
    doi chieu driver (redirect filter vs hub). Tool khong doc dump giup ban.
  * Tool GIAM RUI RO — khong bao hanh het BSOD.
"@
    Show-Tg82OrderedSteps
}

function Show-PublicNotes {
    Write-Bi -Level Title `
        -Vi "Ghi chu cong khai (tham khao — khong ket luan TG82 rieng):" `
        -En "Public notes (context — not a verdict on TG82 itself):"
    Write-Host @"
  * San pham USB Redirector (IncentivesPro) ship kernel drivers (vd. tusbd.sys)
    va release notes cua ho da ghi nhieu lan "fixed BSOD" lien quan stub /
    virtual USB bus / unplug khi con connected — cho thay lop driver nay
    NHAY CAM voi Attach/Release. Nguon: https://www.incentivespro.com/news.html
  * Lop USB-over-IP + ADB (vd. usbipd-win + adb push) co bao cao BSOD cong khai
    khi gan thiet bi Android / transfer lon:
    https://github.com/dorssel/usbipd-win/issues/461
  * Ket luan thuc dung: thu tu kill-ADB -> Attach -> ADB, va kill-ADB -> Release
    la mitigation hop ly; khong thay the viec cap nhat TG82/redirect neu vendor co ban.
  * Chung toi KHONG co dump chung minh driver nao gay BSOD tren may operator.
    Neu co Memory.dmp: WinDbg !analyze -v de xem MODULE_NAME.
"@
}

# --- Actions -----------------------------------------------------------------

function Action-Checklist {
    Show-Tg82OrderedSteps
    Show-PublicNotes
    $null = Show-RedirectStatus
}

function Action-Prepare {
    Write-Bi -Level Title `
        -Vi "CHUAN BI phien LOCAL USB — CHUA cam may." `
        -En "PREPARE local USB session — do NOT plug phone yet."
    $Script:SessionMode = 'Local'
    Clear-StuckAdbProcesses
    Stop-AdbServer
    Show-HardeningTips
    Write-Bi -Level Ok `
        -Vi "San sang LOCAL. Cam may vao cong USB da chon, roi Connect (2)." `
        -En "LOCAL ready. Plug into chosen USB port, then Connect (2)."
}

function Action-PrepareTg82 {
    Write-Bi -Level Title `
        -Vi "CHUAN BI TG82 — kill ADB xong, SAN SANG Share." `
        -En "PREPARE TG82 — ADB killed; READY to Share."
    $Script:SessionMode = 'Tg82'
    Clear-StuckAdbProcesses
    Stop-AdbServer
    $null = Show-RedirectStatus

    Write-Host ""
    Write-Host "  ORDER NOW:  [kill ADB ✓]  ->  TG82 Share  ->  Connect(2)  ->  work" -ForegroundColor Yellow
    Write-Bi -Level Warn `
        -Vi "Bay gio: TG82 Auto -> Share/Attach DUNG 1 may. CHUA chay adb/VoLTE." `
        -En "Now: TG82 Auto -> Share/Attach ONE phone. Do NOT start adb/VoLTE yet."
    Write-Host @"
  Checklist Share:
  [x] ADB da kill (buoc nay vua xong)
  [ ] Khong con may local nao dang cam ADB
  [ ] TG82 Auto: Share DUNG 1 device
  [ ] Doi 3-5 giay cho device on dinh
  [ ] Menu 2 Connect (start ADB + chot serial) — CHI SAU Share
"@
    Write-Bi -Level Ok `
        -Vi "ADB TAT. Hay Share tren TG82, doi on dinh, roi bam Connect (2)." `
        -En "ADB OFF. Share in TG82, wait until stable, then press Connect (2)."
}

function Action-Connect {
    Write-Bi -Level Title `
        -Vi "Ket noi ADB an toan (1 thiet bi) — sau khi USB/TG82 da Attach." `
        -En "Safe ADB connect (one device) — after USB/TG82 Attach is ready."

    if ($Script:SessionMode -eq 'Tg82') {
        Write-Bi -Level Info `
            -Vi "Che do TG82: dam bao Share xong truoc khi start-server." `
            -En "TG82 mode: confirm Share finished before start-server."
        $null = Show-RedirectStatus
    }

    # If adb somehow still running from a previous crash path, clear first.
    Clear-StuckAdbProcesses
    Stop-AdbServer
    Start-Sleep -Milliseconds 500
    Start-AdbServer
    Start-Sleep -Seconds 2

    Write-Bi -Level Info `
        -Vi "Dang quet thiet bi (chi 1 may 'device')..." `
        -En "Scanning devices (expect exactly one 'device')..."

    $all = @(Get-AdbDevices)
    $online = @($all | Where-Object { $_.State -eq 'device' })
    if ($all.Count -gt 1) {
        Write-Bi -Level Warn `
            -Vi "Co $($all.Count) muc trong adb devices — nen Release bot trong TG82 / rut may thua." `
            -En "$($all.Count) entries in adb devices — release extras in TG82 / unplug extras."
    }

    $serial = Select-OneDevice -Prefer $Script:PreferredSerial
    if (-not $serial) {
        Write-Bi -Level Err `
            -Vi "Khong thay 'device'. Neu TG82: kiem tra Share, USB debugging, Allow RSA." `
            -En "No authorized 'device'. If TG82: check Share, USB debugging, RSA Allow."
        return
    }

    $Script:PreferredSerial = $serial
    $env:ANDROID_SERIAL = $serial
    Write-Bi -Level Ok `
        -Vi "Da chot 1 may: $serial (ANDROID_SERIAL)." `
        -En "Locked to one device: $serial (ANDROID_SERIAL)."

    $r = Invoke-Adb -AdbArgs @('-s', $serial, 'get-state')
    Write-Host ("  get-state: " + ($r.Output -join ' '))

    if ($Script:SessionMode -eq 'Tg82') {
        Write-Bi -Level Info `
            -Vi "Khi xong: menu 9 kill ADB, ROI Unshare tren TG82." `
            -En "When done: menu 9 kill ADB, THEN Unshare in TG82."
    }
    else {
        Write-Bi -Level Info `
            -Vi "Khi xong: Disconnect (4), roi rut day." `
            -En "When finished: Disconnect (4), then unplug."
    }
}

function Action-Status {
    $adb = Find-Adb
    if ($adb) {
        Write-Bi -Level Ok -Vi "adb: $adb" -En "adb: $adb"
    }
    else {
        Write-Bi -Level Err -Vi "Khong tim thay adb." -En "adb not found."
    }
    if ($Script:SessionMode) {
        Write-Host ("  Session mode: {0}" -f $Script:SessionMode) -ForegroundColor Cyan
    }
    $null = Show-RedirectStatus
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
        -Vi "Ngat ket noi sach (LOCAL USB)." `
        -En "Clean disconnect (LOCAL USB)."
    $serial = $Script:PreferredSerial
    if (-not $serial) {
        $online = @(Get-AdbDevices | Where-Object { $_.State -eq 'device' })
        if ($online.Count -eq 1) { $serial = $online[0].Serial }
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
    $Script:SessionMode = $null
    Write-Bi -Level Ok `
        -Vi "Da ngat ADB. Ban co the RUT day USB local." `
        -En "ADB stopped. You may safely UNPLUG the local USB cable."
}

function Action-DisconnectTg82 {
    Write-Bi -Level Title `
        -Vi "Ngat TG82: kill ADB xong — TIEP theo Unshare tren TG82." `
        -En "TG82 teardown: ADB killed — NEXT Unshare in TG82."

    $serial = $Script:PreferredSerial
    if ($serial) {
        $null = Invoke-Adb -AdbArgs @('-s', $serial, 'disconnect') -TimeoutSec 10
    }
    Stop-AdbServer
    Clear-StuckAdbProcesses
    Remove-Item Env:ANDROID_SERIAL -ErrorAction SilentlyContinue
    $Script:PreferredSerial = $null

    Write-Host ""
    Write-Host "  ORDER NOW:  work done  ->  [kill ADB ✓]  ->  TG82 Unshare" -ForegroundColor Yellow
    Write-Bi -Level Warn `
        -Vi "BUOC TIEP THEO (bat buoc trong TG82 Auto):" `
        -En "NEXT STEP (required in TG82 Auto):"
    Write-Host @"
  1) TG82 Auto: Unshare / Release / Stop session (thiet bi vua dung).
  2) Doi 2-3 giay — KHONG Share may khac ngay.
  3) Rut day o may khach CHI SAU Unshare thanh cong.
  4) Neu TG82 treo: Exit app, Recover (5), mo lai.
"@
    $null = Show-RedirectStatus
    $Script:SessionMode = $null
    Write-Bi -Level Ok `
        -Vi "ADB da tat. Hay Unshare tren TG82 Auto BAY GIO." `
        -En "ADB is stopped. Unshare in TG82 Auto NOW."
}

function Action-Recover {
    Write-Bi -Level Title `
        -Vi "Khoi phuc sau ket noi loi / BSOD (dac biet sau TG82 Auto + ADB)." `
        -En "Recovery after bad connect / BSOD (esp. after TG82 Auto + ADB)."
    Write-Bi -Level Warn `
        -Vi "Doi Windows on dinh. CHUA Share lai tren TG82. CHUA cam may local." `
        -En "Wait until Windows is stable. Do NOT Share in TG82 yet. Do NOT plug local."

    Clear-StuckAdbProcesses
    Stop-AdbServer
    Start-Sleep -Seconds 1
    Start-AdbServer

    Write-Bi -Level Info `
        -Vi "Kiem tra TG82 / redirect con treo khong:" `
        -En "Checking whether TG82 / redirect still looks active:"
    $null = Show-RedirectStatus

    Write-Host @"

  Recover checklist:
  [ ] TG82 Auto — Unshare moi session treo; neu treo thi Exit app.
  [ ] Khong Share lai cho den khi menu 8 (kill ADB) xong.
  [ ] Neu BSOD lap: ghi STOP code + ten driver tu minidump.
  [ ] Thu Share 1 may/cong khac o may khach de tach HW vs redirect.
"@

    Invoke-UsbPnPRefresh
    Show-PublicNotes

    Write-Bi -Level Ok `
        -Vi "Recover xong. Lan sau: 8 kill ADB -> Share -> 2 Connect -> work -> 9 kill ADB -> Unshare." `
        -En "Recover done. Next: 8 kill ADB -> Share -> 2 Connect -> work -> 9 kill ADB -> Unshare."
    $Script:SessionMode = $null
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
    if ($Script:SessionMode) {
        Write-Host ("  mode: {0}" -f $Script:SessionMode) -ForegroundColor DarkCyan
    }
    Write-Host ""
    Write-Host "  SAFE ORDER (TG82): kill ADB -> Share -> Connect -> work -> kill ADB -> Unshare" -ForegroundColor Yellow
    Write-Host "  Thu tu:           kill ADB -> Share -> Connect -> lam viec -> kill ADB -> Unshare" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  --- TG82 Auto NOW (remote customer) ---" -ForegroundColor Yellow
    Write-Host "  8) Prepare TG82     = kill ADB  (roi Share tren TG82)" -ForegroundColor Yellow
    Write-Host "  2) Connect          = start ADB sau khi Share xong, chot 1 may" -ForegroundColor Yellow
    Write-Host "  9) Disconnect TG82  = kill ADB  (roi Unshare tren TG82)" -ForegroundColor Yellow
    Write-Host "  C) Checklist        = in lai thu tu + ghi chu"
    Write-Host ""
    Write-Host "  --- Local USB / other ---"
    Write-Host "  1) Prepare        local: stop ADB; CHUA cam may"
    Write-Host "  3) Status         adb devices + TG82 hints"
    Write-Host "  4) Disconnect     local: kill ADB, then unplug"
    Write-Host "  5) Recover        sau BSOD (TG82 hoac local)"
    Write-Host "  6) Tips           hardening"
    Write-Host "  7) Kill ADB       chi kill process + kill-server"
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
            '8' { Action-PrepareTg82 }
            '9' { Action-DisconnectTg82 }
            'C' { Action-Checklist }
            'c' { Action-Checklist }
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
Write-Bi -Level Warn `
    -Vi "Bang chung: BSOD ngay khi connect ADB qua USB Redirector TG82 Auto." `
    -En "Evidence: BSOD immediately on ADB connect via USB Redirector TG82 Auto."
Write-Host "  NOW:  8 Prepare TG82  ->  Share  ->  2 Connect  ->  work  ->  9 kill ADB  ->  Unshare" -ForegroundColor Yellow

if (-not (Find-Adb)) {
    Write-Bi -Level Warn `
        -Vi "Chua thay adb.exe — mot so chuc nang se that bai cho den khi cai platform-tools." `
        -En "adb.exe missing — some actions will fail until platform-tools are installed."
}

switch ($Action) {
    'Prepare'         { Action-Prepare }
    'PrepareTg82'     { Action-PrepareTg82 }
    'Connect'         { Action-Connect }
    'Status'          { Action-Status }
    'Disconnect'      { Action-Disconnect }
    'DisconnectTg82'  { Action-DisconnectTg82 }
    'Recover'         { Action-Recover }
    'Tips'            { Show-HardeningTips }
    'Kill'            { Action-Kill }
    'Checklist'       { Action-Checklist }
    default           { Invoke-MenuLoop }
}

if ($Action -ne 'Menu' -and -not $NoPause) {
    Write-Host ""
    Read-Host "Nhan Enter de thoat / Press Enter to exit" | Out-Null
}
