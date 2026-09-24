#Requires -Version 5.1
<#
.SYNOPSIS
  Shared helpers for TG82_USB_REDIRECTOR_FIX.
  No driver install/update. No USB1.9.7_Auto_Connect_Online_EFT.exe.
#>

$script:ToolName = 'TG82_USB_REDIRECTOR_FIX'
$script:CommonDir = $PSScriptRoot
if (-not $script:CommonDir) {
    $script:CommonDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$script:ToolRoot = Split-Path -Parent $script:CommonDir
if (-not $script:ToolRoot) {
    $script:ToolRoot = $script:CommonDir
}

$script:DataDir = Join-Path $env:LOCALAPPDATA $script:ToolName
$script:LogDir = Join-Path $script:ToolRoot 'logs'
$script:DetailLogPath = $null
$script:UiLogCallback = $null

$script:Report = [ordered]@{
    USB_REDIRECTOR_FOUND   = 'SKIP'
    ADB_CONFLICT           = 'SKIP'
    AUTO_REBIND_DISABLED   = 'SKIP'
    ADB_RESET              = 'SKIP'
    USB_SERVICE_RESET      = 'SKIP'
    SAFE_RECONNECT         = 'SKIP'
    MODE_TRANSITION_GUARD  = 'SKIP'
    FINAL_ADB              = 'SKIP'
    BSOD_RISK_REDUCED      = 'SKIP'
}

function Initialize-ToolEnvironment {
    if (-not (Test-Path -LiteralPath $script:DataDir)) {
        New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $script:LogDir)) {
        New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:DetailLogPath = Join-Path $script:LogDir ("detail_{0}.log" -f $stamp)
    "=== $script:ToolName detail log $stamp ===" | Out-File -FilePath $script:DetailLogPath -Encoding UTF8
}

function Set-UiLogCallback {
    param([scriptblock]$Callback)
    $script:UiLogCallback = $Callback
}

function Write-Detail {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
    if ($script:DetailLogPath) {
        Add-Content -LiteralPath $script:DetailLogPath -Value $line -Encoding UTF8
    }
}

function Write-UiStatus {
    param([Parameter(Mandatory)][string]$Message)
    Write-Detail "UI: $Message"
    if ($script:UiLogCallback) {
        & $script:UiLogCallback $Message
    }
    else {
        Write-Host $Message
    }
}

function Set-ReportField {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )
    if ($script:Report.Contains($Name)) {
        $script:Report[$Name] = $Value
    }
    Write-Detail "REPORT $Name = $Value"
}

function Get-ReportText {
    $lines = @()
    foreach ($k in $script:Report.Keys) {
        $lines += ("{0} = {1}" -f $k, $script:Report[$k])
    }
    return ($lines -join [Environment]::NewLine)
}

function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string]$Arguments = '',
        [int]$TimeoutMs = 20000
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($psi)
    if (-not $p.WaitForExit($TimeoutMs)) {
        try { $p.Kill() } catch {}
        return [pscustomobject]@{ ExitCode = -1; StdOut = ''; StdErr = 'TIMEOUT'; TimedOut = $true }
    }
    $out = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    $code = $p.ExitCode
    $p.Dispose()
    return [pscustomobject]@{ ExitCode = $code; StdOut = $out; StdErr = $err; TimedOut = $false }
}

function Find-UsbRedirectorInstall {
    $candidates = @(
        "${env:ProgramFiles}\USB Redirector Technician Edition",
        "${env:ProgramFiles(x86)}\USB Redirector Technician Edition",
        "${env:ProgramFiles}\USB Redirector",
        "${env:ProgramFiles(x86)}\USB Redirector",
        'C:\Program Files\USB Redirector Technician Edition',
        'C:\Program Files (x86)\USB Redirector Technician Edition',
        'D:\TOOL\TG82',
        'D:\TOOL\TG82 Auto',
        'D:\TG82',
        'C:\TG82'
    )

    # Scan D:\TOOL for TG82* folders
    if (Test-Path -LiteralPath 'D:\TOOL') {
        Get-ChildItem -LiteralPath 'D:\TOOL' -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'TG82|USB.?Redirector|usbtech' } |
            ForEach-Object { $candidates += $_.FullName }
    }

    $found = [ordered]@{
        Root         = $null
        UsbTechSh    = $null
        ServiceExe   = $null
        MainExe      = $null
        ConfigFiles  = @()
    }

    foreach ($root in ($candidates | Select-Object -Unique)) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        $usbtechsh = Join-Path $root 'usbtechsh.exe'
        $srv = Join-Path $root 'usbredirectortechssrv.exe'
        $main = Join-Path $root 'usbredirector-technician.exe'
        if ((Test-Path -LiteralPath $usbtechsh) -or (Test-Path -LiteralPath $srv) -or (Test-Path -LiteralPath $main)) {
            $found.Root = $root
            if (Test-Path -LiteralPath $usbtechsh) { $found.UsbTechSh = $usbtechsh }
            if (Test-Path -LiteralPath $srv) { $found.ServiceExe = $srv }
            if (Test-Path -LiteralPath $main) { $found.MainExe = $main }
            break
        }
    }

    # Fallback: locate usbtechsh via process / PATH / Get-Command
    if (-not $found.UsbTechSh) {
        $proc = Get-Process -Name 'usbtechsh','usbredirector-technician','usbredirectortechssrv' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($proc -and $proc.Path) {
            $found.Root = Split-Path -Parent $proc.Path
            $usbtechsh = Join-Path $found.Root 'usbtechsh.exe'
            if (Test-Path -LiteralPath $usbtechsh) { $found.UsbTechSh = $usbtechsh }
            $srv = Join-Path $found.Root 'usbredirectortechssrv.exe'
            if (Test-Path -LiteralPath $srv) { $found.ServiceExe = $srv }
            $main = Join-Path $found.Root 'usbredirector-technician.exe'
            if (Test-Path -LiteralPath $main) { $found.MainExe = $main }
        }
    }

    if ($found.Root) {
        $cfgPatterns = @('*.ini', '*.cfg', '*.xml', '*.conf', '*.json')
        foreach ($pat in $cfgPatterns) {
            Get-ChildItem -LiteralPath $found.Root -Filter $pat -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Length -lt 2MB } |
                Select-Object -First 20 |
                ForEach-Object { $found.ConfigFiles += $_.FullName }
        }
        $appDataRoots = @(
            (Join-Path $env:APPDATA 'USB Redirector Technician Edition'),
            (Join-Path $env:LOCALAPPDATA 'USB Redirector Technician Edition'),
            (Join-Path $env:PROGRAMDATA 'USB Redirector Technician Edition'),
            (Join-Path $env:APPDATA 'SimplyCore'),
            (Join-Path $env:LOCALAPPDATA 'SimplyCore')
        )
        foreach ($ar in $appDataRoots) {
            if (Test-Path -LiteralPath $ar) {
                Get-ChildItem -LiteralPath $ar -Include *.ini,*.cfg,*.xml,*.json -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.Length -lt 2MB } |
                    Select-Object -First 20 |
                    ForEach-Object { $found.ConfigFiles += $_.FullName }
            }
        }
    }

    return [pscustomobject]$found
}

function Find-Tg82BundledAdb {
    <#
    Prefer TG82 / USB Redirector bundled adb. Never prefer random PATH adb if bundle exists.
    #>
    $searchRoots = @()
    $ur = Find-UsbRedirectorInstall
    if ($ur.Root) { $searchRoots += $ur.Root }

    $extra = @(
        'D:\TOOL\TG82',
        'D:\TOOL\TG82 Auto',
        'D:\TG82',
        'C:\TG82',
        (Join-Path $script:ToolRoot 'platform-tools'),
        (Join-Path $script:ToolRoot 'adb')
    )
    if (Test-Path -LiteralPath 'D:\TOOL') {
        Get-ChildItem -LiteralPath 'D:\TOOL' -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'TG82|VoLTE|ADB|platform-tools' } |
            ForEach-Object { $extra += $_.FullName }
    }
    $searchRoots += $extra

    foreach ($root in ($searchRoots | Select-Object -Unique)) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        $hits = @(
            (Join-Path $root 'adb.exe'),
            (Join-Path $root 'platform-tools\adb.exe'),
            (Join-Path $root 'adb\adb.exe'),
            (Join-Path $root 'tools\adb.exe'),
            (Join-Path $root 'bin\adb.exe')
        )
        # shallow recurse for adb.exe under TG82 trees (depth-limited via -Recurse + Early stop)
        foreach ($h in $hits) {
            if (Test-Path -LiteralPath $h) {
                Write-Detail "Bundled adb found: $h"
                return (Resolve-Path -LiteralPath $h).Path
            }
        }
        $deep = Get-ChildItem -LiteralPath $root -Filter 'adb.exe' -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($deep) {
            Write-Detail "Bundled adb found (scan): $($deep.FullName)"
            return $deep.FullName
        }
    }

    # Fallback: Android SDK / PATH — only if no TG82 bundle
    $fallback = @()
    if ($env:ANDROID_HOME) { $fallback += (Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe') }
    if ($env:ANDROID_SDK_ROOT) { $fallback += (Join-Path $env:ANDROID_SDK_ROOT 'platform-tools\adb.exe') }
    $localApp = [Environment]::GetFolderPath('LocalApplicationData')
    $fallback += @(
        (Join-Path $localApp 'Android\Sdk\platform-tools\adb.exe'),
        "$env:ProgramFiles\Android\android-sdk\platform-tools\adb.exe",
        "${env:ProgramFiles(x86)}\Android\android-sdk\platform-tools\adb.exe"
    )
    foreach ($p in $fallback) {
        if ($p -and (Test-Path -LiteralPath $p)) {
            Write-Detail "Fallback SDK adb: $p"
            return (Resolve-Path -LiteralPath $p).Path
        }
    }
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) {
        Write-Detail "PATH adb (last resort): $($cmd.Source)"
        return $cmd.Source
    }
    return $null
}

function Get-AdbProcessInfo {
    $procs = @(Get-Process -Name 'adb' -ErrorAction SilentlyContinue)
    $paths = @()
    foreach ($p in $procs) {
        try {
            if ($p.Path) { $paths += $p.Path }
            else { $paths += ("pid:{0}" -f $p.Id) }
        }
        catch {
            $paths += ("pid:{0}" -f $p.Id)
        }
    }
    $uniquePaths = @($paths | Select-Object -Unique)
    return [pscustomobject]@{
        Count        = $procs.Count
        Paths        = $paths
        UniquePaths  = $uniquePaths
        Conflict     = ($uniquePaths.Count -gt 1) -or ($procs.Count -gt 2)
    }
}

function Find-UsbRedirectorServices {
    $names = @(
        'USB Redirector Technician Edition',
        'USBRedirectorTechnician',
        'usbredirectortechssrv',
        'USB Redirector',
        'usbredirector'
    )
    $list = @()
    foreach ($n in $names) {
        $svc = Get-Service -Name $n -ErrorAction SilentlyContinue
        if ($svc) { $list += $svc }
    }
    # Also match by display name / path
    Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match 'usb.?redirector|usbtech' -or
            $_.DisplayName -match 'USB Redirector' -or
            ($_.PathName -and $_.PathName -match 'usbredirectortechssrv|usbtechsh')
        } |
        ForEach-Object {
            $svc = Get-Service -Name $_.Name -ErrorAction SilentlyContinue
            if ($svc -and ($list.Name -notcontains $svc.Name)) { $list += $svc }
        }
    return $list
}

function Backup-ConfigFiles {
    param([string[]]$Files)
    if (-not $Files -or $Files.Count -eq 0) { return $null }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupRoot = Join-Path $script:DataDir ("config_backup_{0}" -f $stamp)
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $copied = 0
    foreach ($f in $Files) {
        if (-not (Test-Path -LiteralPath $f)) { continue }
        try {
            $leaf = Split-Path -Leaf $f
            $dest = Join-Path $backupRoot $leaf
            if (Test-Path -LiteralPath $dest) {
                $dest = Join-Path $backupRoot ("{0}_{1}" -f $copied, $leaf)
            }
            Copy-Item -LiteralPath $f -Destination $dest -Force
            $copied++
            Write-Detail "Backed up config: $f -> $dest"
        }
        catch {
            Write-Detail "Backup failed for $f : $($_.Exception.Message)"
        }
    }
    if ($copied -eq 0) { return $null }
    return $backupRoot
}

function Disable-AutoRebindInConfigs {
    param([string[]]$Files)
    <#
    Best-effort: set known auto-connect / auto-rebind keys to off.
    Never installs drivers. Never calls EFT auto tool.
    #>
    $changed = 0
    $patterns = @(
        @{ Regex = '(?im)^(\s*AutoConnect(?:All)?\s*=\s*)(1|true|yes|on)\s*$'; Replace = '${1}0' },
        @{ Regex = '(?im)^(\s*Auto-?Connect(?:\s+all\s+USB\s+devices)?\s*=\s*)(1|true|yes|on)\s*$'; Replace = '${1}0' },
        @{ Regex = '(?im)^(\s*AutoRebind\s*=\s*)(1|true|yes|on)\s*$'; Replace = '${1}0' },
        @{ Regex = '(?im)^(\s*AutoReconnect\s*=\s*)(1|true|yes|on)\s*$'; Replace = '${1}0' },
        @{ Regex = '(?im)^(\s*ContinuousRebind\s*=\s*)(1|true|yes|on)\s*$'; Replace = '${1}0' },
        @{ Regex = '(?im)^(\s*SESSION_LOCK\s*=\s*)(0|false|no|off)\s*$'; Replace = '${1}1' },
        @{ Regex = '(?im)^(\s*MODE_TRANSITION_LOCK\s*=\s*)(0|false|no|off)\s*$'; Replace = '${1}1' }
    )

    foreach ($f in $Files) {
        if (-not (Test-Path -LiteralPath $f)) { continue }
        $ext = [IO.Path]::GetExtension($f).ToLowerInvariant()
        if ($ext -notin @('.ini', '.cfg', '.conf', '.txt')) { continue }
        try {
            $raw = Get-Content -LiteralPath $f -Raw -ErrorAction Stop
            $new = $raw
            foreach ($p in $patterns) {
                $new = [regex]::Replace($new, $p.Regex, $p.Replace)
            }
            # Append lock flags if file looks like our/product ini and flags missing
            if ($new -notmatch '(?im)^\s*SESSION_LOCK\s*=') {
                $new = $new.TrimEnd() + "`r`nSESSION_LOCK=1`r`nMODE_TRANSITION_LOCK=1`r`n"
            }
            if ($new -ne $raw) {
                Set-Content -LiteralPath $f -Value $new -Encoding UTF8 -NoNewline
                $changed++
                Write-Detail "Auto-rebind disabled in: $f"
            }
        }
        catch {
            Write-Detail "Config edit skipped $f : $($_.Exception.Message)"
        }
    }

    # Always write tool-local lock flags (supported product flags)
    $lockPath = Join-Path $script:DataDir 'session.lock.json'
    $lockObj = [ordered]@{
        SESSION_LOCK          = $true
        MODE_TRANSITION_LOCK  = $true
        AUTO_CONNECT_PAUSED   = $true
        AUTO_REBIND_PAUSED    = $true
        BACKGROUND_SCAN_PAUSED = $true
        UpdatedAt             = (Get-Date).ToString('o')
        Note                  = 'Pause auto-connect / auto-rebind / background USB-COM scan for safe ADB transition'
    }
    ($lockObj | ConvertTo-Json) | Set-Content -LiteralPath $lockPath -Encoding UTF8
    Write-Detail "Wrote tool lock: $lockPath"

    return $changed
}

function Invoke-Adb {
    param(
        [Parameter(Mandatory)][string]$AdbPath,
        [Parameter(Mandatory)][string]$Arguments,
        [int]$TimeoutMs = 20000
    )
    return Invoke-Native -FilePath $AdbPath -Arguments $Arguments -TimeoutMs $TimeoutMs
}

function Get-AdbDevices {
    param([Parameter(Mandatory)][string]$AdbPath)
    $r = Invoke-Adb -AdbPath $AdbPath -Arguments 'devices' -TimeoutMs 15000
    $devices = @()
    foreach ($line in ($r.StdOut -split "`r?`n")) {
        if ($line -match '^\s*List of devices') { continue }
        if ($line -match '^\s*(\S+)\s+(device|recovery|sideload|unauthorized|offline|bootloader)\s*$') {
            $devices += [pscustomobject]@{ Serial = $Matches[1]; State = $Matches[2] }
        }
    }
    return [pscustomobject]@{
        Raw      = $r.StdOut
        Devices  = $devices
        ExitCode = $r.ExitCode
    }
}

function Get-DeviceBootCompleted {
    param(
        [Parameter(Mandatory)][string]$AdbPath,
        [string]$Serial
    )
    $args = 'shell getprop sys.boot_completed'
    if ($Serial) { $args = "-s $Serial shell getprop sys.boot_completed" }
    $r = Invoke-Adb -AdbPath $AdbPath -Arguments $args -TimeoutMs 10000
    $val = ($r.StdOut + $r.StdErr).Trim()
    return ($val -match '1')
}

function Get-DeviceMode {
    param(
        [Parameter(Mandatory)][string]$AdbPath,
        [string]$Serial
    )
    $args = 'get-state'
    if ($Serial) { $args = "-s $Serial get-state" }
    $r = Invoke-Adb -AdbPath $AdbPath -Arguments $args -TimeoutMs 10000
    $state = ($r.StdOut).Trim()
    if (-not $state) { $state = 'unknown' }

    # fastboot process presence
    $fb = Get-Process -Name 'fastboot' -ErrorAction SilentlyContinue
    $mode = $state
    if ($fb) { $mode = 'fastboot' }
    elseif ($state -eq 'recovery') { $mode = 'recovery' }
    elseif ($state -eq 'device') { $mode = 'android' }
    elseif ($state -match 'offline|unknown|bootloader') { $mode = $state }

    return [pscustomobject]@{
        State = $state
        Mode  = $mode
        Raw   = $r.StdOut + $r.StdErr
    }
}

function Test-ForbiddenEftTool {
    <# Ensure we never invoke the banned auto-connect EFT binary. #>
    $banned = 'USB1.9.7_Auto_Connect_Online_EFT.exe'
    Write-Detail "Safety: will NOT use $banned"
    return $banned
}
