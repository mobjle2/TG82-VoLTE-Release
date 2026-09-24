#Requires -Version 5.1
<#
.SYNOPSIS
  COLLECT BSOD LOG — zip newest minidump, Kernel-PnP/USB events, USB Redirector logs, adb + service state.
#>

function Invoke-CollectBsodLog {
    [CmdletBinding()]
    param()

    Write-UiStatus 'Đang kiểm tra...'
    Write-Detail '=== COLLECT BSOD LOG ==='

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $stage = Join-Path $env:TEMP ("TG82_BSOD_LOG_{0}" -f $stamp)
    New-Item -ItemType Directory -Path $stage -Force | Out-Null

    $meta = [System.Text.StringBuilder]::new()
    [void]$meta.AppendLine("TG82_USB_REDIRECTOR_FIX BSOD collect $stamp")
    [void]$meta.AppendLine("IsAdmin=$(Test-IsAdmin)")
    [void]$meta.AppendLine("")

    # --- newest minidump ---
    $dumpDir = Join-Path $env:SystemRoot 'Minidump'
    $dumpCopied = $false
    if (Test-Path -LiteralPath $dumpDir) {
        $newest = Get-ChildItem -LiteralPath $dumpDir -Filter '*.dmp' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($newest) {
            try {
                $destDump = Join-Path $stage 'minidump'
                New-Item -ItemType Directory -Path $destDump -Force | Out-Null
                Copy-Item -LiteralPath $newest.FullName -Destination (Join-Path $destDump $newest.Name) -Force
                [void]$meta.AppendLine("Minidump: $($newest.FullName) ($($newest.LastWriteTime))")
                $dumpCopied = $true
            }
            catch {
                [void]$meta.AppendLine("Minidump copy FAIL (need admin?): $($_.Exception.Message)")
                Write-Detail "Minidump copy failed: $($_.Exception.Message)"
            }
        }
        else {
            [void]$meta.AppendLine('Minidump: none found')
        }
    }
    else {
        [void]$meta.AppendLine("Minidump folder missing: $dumpDir")
    }

    # MEMORY.DMP pointer note (do not copy huge file by default)
    $memDump = Join-Path $env:SystemRoot 'MEMORY.DMP'
    if (Test-Path -LiteralPath $memDump) {
        $mi = Get-Item -LiteralPath $memDump
        [void]$meta.AppendLine("MEMORY.DMP present size=$($mi.Length) mtime=$($mi.LastWriteTime) (not copied — too large)")
    }

    # --- Event Viewer Kernel-PnP / USB ---
    # UI status lines only from the allowed set; collect stays on "Đang kiểm tra..." until done.
    $evDir = Join-Path $stage 'eventlog'
    New-Item -ItemType Directory -Path $evDir -Force | Out-Null
    $evOk = $false
    try {
        $startTime = (Get-Date).AddDays(-7)
        $pnp = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-PnP'; StartTime = $startTime } -MaxEvents 200 -ErrorAction SilentlyContinue
        if ($pnp) {
            $pnp | Select-Object TimeCreated, Id, LevelDisplayName, Message |
                Export-Csv -Path (Join-Path $evDir 'Kernel-PnP.csv') -NoTypeInformation -Encoding UTF8
            $evOk = $true
        }
        $usbProviders = @(
            'Microsoft-Windows-USB-USBHUB3',
            'Microsoft-Windows-USB-USBPORT',
            'Microsoft-Windows-Kernel-PnP'
        )
        foreach ($prov in $usbProviders) {
            try {
                $ev = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = $prov; StartTime = $startTime } -MaxEvents 100 -ErrorAction SilentlyContinue
                if ($ev) {
                    $safe = ($prov -replace '[^\w\-]', '_')
                    $ev | Select-Object TimeCreated, Id, LevelDisplayName, Message |
                        Export-Csv -Path (Join-Path $evDir "$safe.csv") -NoTypeInformation -Encoding UTF8
                    $evOk = $true
                }
            }
            catch {
                Write-Detail "Event provider $prov: $($_.Exception.Message)"
            }
        }
        # Also try wevtutil export if admin
        if (Test-IsAdmin) {
            $evtx = Join-Path $evDir 'System_recent.evtx'
            $null = Invoke-Native -FilePath 'wevtutil.exe' -Arguments "epl System `"$evtx`" /ow:true" -TimeoutMs 60000
            if (Test-Path -LiteralPath $evtx) { $evOk = $true }
        }
        else {
            [void]$meta.AppendLine('Event log: partial export without admin (CSV via Get-WinEvent). Re-run as admin for full wevtutil.')
        }
        [void]$meta.AppendLine("Event log export ok=$evOk")
    }
    catch {
        [void]$meta.AppendLine("Event log FAIL: $($_.Exception.Message)")
        Write-Detail "Event log collect failed: $($_.Exception.Message)"
    }

    # --- USB Redirector logs ---
    $ur = Find-UsbRedirectorInstall
    $urLogDir = Join-Path $stage 'usb_redirector'
    New-Item -ItemType Directory -Path $urLogDir -Force | Out-Null
    [void]$meta.AppendLine("USB_REDIRECTOR_FOUND root=$($ur.Root)")
    $logCopied = 0
    $logSearch = @()
    if ($ur.Root) {
        $logSearch += $ur.Root
        $logSearch += (Join-Path $ur.Root 'logs')
        $logSearch += (Join-Path $ur.Root 'log')
    }
    $logSearch += @(
        (Join-Path $env:APPDATA 'USB Redirector Technician Edition'),
        (Join-Path $env:LOCALAPPDATA 'USB Redirector Technician Edition'),
        (Join-Path $env:PROGRAMDATA 'USB Redirector Technician Edition')
    )
    foreach ($root in ($logSearch | Select-Object -Unique)) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -Include *.log,*.txt,*.dmp -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -lt 50MB } |
            Select-Object -First 30 |
            ForEach-Object {
                try {
                    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $urLogDir $_.Name) -Force
                    $logCopied++
                }
                catch {
                    Write-Detail "UR log copy fail $($_.FullName): $($_.Exception.Message)"
                }
            }
    }
    # setup log often next to install
    if ($ur.Root) {
        $setupLog = Join-Path $ur.Root 'usbredirector-technician-setup.log'
        if (Test-Path -LiteralPath $setupLog) {
            Copy-Item -LiteralPath $setupLog -Destination (Join-Path $urLogDir 'usbredirector-technician-setup.log') -Force -ErrorAction SilentlyContinue
            $logCopied++
        }
    }
    [void]$meta.AppendLine("USB Redirector log files copied=$logCopied")

    # --- adb state ---
    $adbDir = Join-Path $stage 'adb'
    New-Item -ItemType Directory -Path $adbDir -Force | Out-Null
    $adbPath = Find-Tg82BundledAdb
    $adbState = [System.Text.StringBuilder]::new()
    [void]$adbState.AppendLine("adbPath=$adbPath")
    $procInfo = Get-AdbProcessInfo
    [void]$adbState.AppendLine("adbProcessCount=$($procInfo.Count)")
    [void]$adbState.AppendLine("adbPaths=$($procInfo.Paths -join '; ')")
    [void]$adbState.AppendLine("conflict=$($procInfo.Conflict)")
    if ($adbPath) {
        $ver = Invoke-Adb -AdbPath $adbPath -Arguments 'version' -TimeoutMs 10000
        [void]$adbState.AppendLine('--- adb version ---')
        [void]$adbState.AppendLine($ver.StdOut + $ver.StdErr)
        $devs = Invoke-Adb -AdbPath $adbPath -Arguments 'devices -l' -TimeoutMs 15000
        [void]$adbState.AppendLine('--- adb devices -l ---')
        [void]$adbState.AppendLine($devs.StdOut + $devs.StdErr)
    }
    Set-Content -LiteralPath (Join-Path $adbDir 'adb_state.txt') -Value $adbState.ToString() -Encoding UTF8

    # --- service state ---
    $svcDir = Join-Path $stage 'service'
    New-Item -ItemType Directory -Path $svcDir -Force | Out-Null
    $svcText = [System.Text.StringBuilder]::new()
    $services = @(Find-UsbRedirectorServices)
    if ($services.Count -eq 0) {
        [void]$svcText.AppendLine('No USB Redirector services matched')
    }
    foreach ($s in $services) {
        [void]$svcText.AppendLine(("Name={0} Status={1} StartType={2} DisplayName={3}" -f $s.Name, $s.Status, $s.StartType, $s.DisplayName))
    }
    Get-Process -Name 'usbtechsh','usbredirector-technician','usbredirectortechssrv','adb' -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                [void]$svcText.AppendLine(("PROC Name={0} Id={1} Path={2}" -f $_.Name, $_.Id, $_.Path))
            }
            catch {
                [void]$svcText.AppendLine(("PROC Name={0} Id={1}" -f $_.Name, $_.Id))
            }
        }
    Set-Content -LiteralPath (Join-Path $svcDir 'service_state.txt') -Value $svcText.ToString() -Encoding UTF8

    Set-Content -LiteralPath (Join-Path $stage 'collect_meta.txt') -Value $meta.ToString() -Encoding UTF8

    # Zip
    $zipName = "TG82_BSOD_LOG_{0}.zip" -f $stamp
    $zipPath = Join-Path $script:LogDir $zipName
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    try {
        Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zipPath -Force
        Write-Detail "Zip created: $zipPath"
        Write-UiStatus 'Hoàn tất'
        Write-UiStatus ("LOG ZIP: {0}" -f $zipPath)
        if (-not $dumpCopied) {
            Write-UiStatus 'Minidump: SKIP/không có hoặc cần admin'
        }
        if (-not (Test-IsAdmin)) {
            Write-UiStatus 'Gợi ý: chạy admin để lấy đủ Event Log / minidump'
        }
        return [pscustomobject]@{
            Success = $true
            ZipPath = $zipPath
        }
    }
    catch {
        Write-Detail "Zip failed: $($_.Exception.Message)"
        Write-UiStatus 'Thất bại'
        Write-UiStatus ("[FAIL] Không tạo được zip: {0}" -f $_.Exception.Message)
        return [pscustomobject]@{
            Success = $false
            ZipPath = $null
            Error   = $_.Exception.Message
        }
    }
    finally {
        try { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
}
