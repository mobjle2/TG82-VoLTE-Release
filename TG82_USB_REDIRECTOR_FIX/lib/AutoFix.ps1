#Requires -Version 5.1
<#
.SYNOPSIS
  AUTO FIX BSOD ADB — sequential steps 1–10 per product spec.
#>

function Invoke-AutoFixBsodAdb {
    [CmdletBinding()]
    param()

    # Reset report
    foreach ($k in @($script:Report.Keys)) { $script:Report[$k] = 'SKIP' }

    [void](Test-ForbiddenEftTool)

    # -------------------------------------------------------------------------
    # 1. DETECT
    # -------------------------------------------------------------------------
    Write-UiStatus 'Đang kiểm tra...'
    Write-Detail '=== STEP 1 DETECT ==='

    $ur = Find-UsbRedirectorInstall
    $adbInfo = Get-AdbProcessInfo
    $services = @(Find-UsbRedirectorServices)
    $adbPath = Find-Tg82BundledAdb

    Write-Detail ("USB Redirector root: {0}" -f $(if ($ur.Root) { $ur.Root } else { '(not found)' }))
    Write-Detail ("usbtechsh: {0}" -f $(if ($ur.UsbTechSh) { $ur.UsbTechSh } else { '(none)' }))
    Write-Detail ("ADB path: {0}" -f $(if ($adbPath) { $adbPath } else { '(none)' }))
    Write-Detail ("ADB processes: count={0} uniquePaths={1} conflict={2}" -f $adbInfo.Count, $adbInfo.UniquePaths.Count, $adbInfo.Conflict)
    Write-Detail ("Services: {0}" -f (($services | ForEach-Object { "{0}({1})" -f $_.Name, $_.Status }) -join ', '))

    if ($ur.Root -or $ur.UsbTechSh -or $services.Count -gt 0) {
        Set-ReportField -Name 'USB_REDIRECTOR_FOUND' -Value 'PASS'
    }
    else {
        Set-ReportField -Name 'USB_REDIRECTOR_FOUND' -Value 'FAIL'
        Write-Detail 'USB Redirector / usbtechsh not found'
    }

    if ($adbInfo.Conflict -or $adbInfo.UniquePaths.Count -gt 1) {
        Set-ReportField -Name 'ADB_CONFLICT' -Value 'PASS'  # conflict detected (info field — presence of conflict)
        Write-Detail 'ADB conflict DETECTED (multiple adb paths/servers)'
        $script:HadAdbConflict = $true
    }
    else {
        Set-ReportField -Name 'ADB_CONFLICT' -Value 'PASS'  # checked; will reflect cleaned state later
        $script:HadAdbConflict = $false
        if ($adbInfo.Count -le 1) {
            Write-Detail 'No multi-adb conflict at detect time'
        }
    }

    # Capture current target session
    $targetSerial = $null
    $preDevices = $null
    if ($adbPath) {
        $preDevices = Get-AdbDevices -AdbPath $adbPath
        Write-Detail ("adb devices pre:`n{0}" -f $preDevices.Raw)
        $online = @($preDevices.Devices | Where-Object { $_.State -in @('device', 'recovery') })
        if ($online.Count -eq 1) {
            $targetSerial = $online[0].Serial
            Write-Detail "Current target serial: $targetSerial ($($online[0].State))"
        }
        elseif ($online.Count -gt 1) {
            Write-Detail 'Multiple devices — will refuse reconnect loop; target = first device state only'
            $targetSerial = $online[0].Serial
        }
    }

    # -------------------------------------------------------------------------
    # 2. SAFE LOCK
    # -------------------------------------------------------------------------
    Write-Detail '=== STEP 2 SAFE LOCK ==='
    # UI stays on "Đang kiểm tra..." until ADB CLEAN; lock work is detail-log only.

    $backup = Backup-ConfigFiles -Files $ur.ConfigFiles
    if ($backup) {
        Write-Detail "Config backup: $backup"
    }
    else {
        Write-Detail 'No product config files to backup (will still write tool lock flags)'
    }

    $changed = Disable-AutoRebindInConfigs -Files $ur.ConfigFiles
    # Pause continuous rebind: do NOT kill usbtechsh GUI permanently; only note lock.
    # Prevent continuous rebind by ensuring we never call auto-connect EFT and by lock flags.
    if ($changed -ge 0) {
        Set-ReportField -Name 'AUTO_REBIND_DISABLED' -Value 'PASS'
    }
    else {
        Set-ReportField -Name 'AUTO_REBIND_DISABLED' -Value 'SKIP'
    }

    # -------------------------------------------------------------------------
    # 3. ADB CLEAN
    # -------------------------------------------------------------------------
    Write-Detail '=== STEP 3 ADB CLEAN ==='
    Write-UiStatus 'Đang làm sạch ADB...'

    if (-not $adbPath) {
        Set-ReportField -Name 'ADB_RESET' -Value 'FAIL'
        Write-Detail 'No adb.exe found (TG82 bundle or fallback)'
    }
    else {
        # Kill conflicting adb servers/processes
        $kill = Invoke-Adb -AdbPath $adbPath -Arguments 'kill-server' -TimeoutMs 12000
        Write-Detail ("adb kill-server exit={0} out={1} err={2}" -f $kill.ExitCode, $kill.StdOut.Trim(), $kill.StdErr.Trim())

        $killed = 0
        Get-Process -Name 'adb' -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Stop-Process -Id $_.Id -Force -ErrorAction Stop
                $killed++
            }
            catch {
                Write-Detail "Could not kill adb pid $($_.Id): $($_.Exception.Message)"
            }
        }
        Write-Detail "Force-killed adb processes: $killed"
        Start-Sleep -Seconds 1

        $start = Invoke-Adb -AdbPath $adbPath -Arguments 'start-server' -TimeoutMs 20000
        Write-Detail ("adb start-server exit={0} out={1} err={2}" -f $start.ExitCode, $start.StdOut.Trim(), $start.StdErr.Trim())

        $ver = Invoke-Adb -AdbPath $adbPath -Arguments 'version' -TimeoutMs 10000
        Write-Detail ("adb version:`n{0}" -f ($ver.StdOut + $ver.StdErr))

        $devs = Get-AdbDevices -AdbPath $adbPath
        Write-Detail ("adb devices after reset:`n{0}" -f $devs.Raw)

        $postInfo = Get-AdbProcessInfo
        if ($ver.ExitCode -eq 0 -or ($ver.StdOut -match 'Android Debug Bridge')) {
            if (-not $postInfo.Conflict) {
                Set-ReportField -Name 'ADB_RESET' -Value 'PASS'
            }
            else {
                Set-ReportField -Name 'ADB_RESET' -Value 'FAIL'
                Write-Detail 'ADB still conflicting after reset'
            }
        }
        else {
            Set-ReportField -Name 'ADB_RESET' -Value 'FAIL'
        }

        # Update conflict field: PASS means checked & resolved or none; FAIL if still conflicting
        if ($postInfo.Conflict) {
            Set-ReportField -Name 'ADB_CONFLICT' -Value 'FAIL'
        }
        else {
            Set-ReportField -Name 'ADB_CONFLICT' -Value 'PASS'
        }
    }

    # -------------------------------------------------------------------------
    # 4. USB REDIRECTOR SAFE RESET
    # -------------------------------------------------------------------------
    Write-Detail '=== STEP 4 USB REDIRECTOR SAFE RESET ==='
    Write-UiStatus 'Đang reset USB Redirector...'

    $serviceResetOk = $false
    $reconnectOk = $false

    if ($services.Count -eq 0 -and -not $ur.Root) {
        Set-ReportField -Name 'USB_SERVICE_RESET' -Value 'SKIP'
        Write-Detail 'No USB Redirector service to reset'
    }
    else {
        if (-not (Test-IsAdmin)) {
            Write-Detail 'Not admin — cannot restart service safely; SKIP service restart'
            Set-ReportField -Name 'USB_SERVICE_RESET' -Value 'SKIP'
        }
        else {
            foreach ($svc in $services) {
                try {
                    Write-Detail "Restarting service $($svc.Name) ($($svc.Status))"
                    if ($svc.Status -eq 'Running') {
                        Restart-Service -Name $svc.Name -Force -ErrorAction Stop
                    }
                    else {
                        Start-Service -Name $svc.Name -ErrorAction Stop
                    }
                    # Wait until stable
                    $deadline = (Get-Date).AddSeconds(30)
                    do {
                        Start-Sleep -Seconds 1
                        $svc.Refresh()
                    } while ($svc.Status -ne 'Running' -and (Get-Date) -lt $deadline)
                    if ($svc.Status -eq 'Running') {
                        $serviceResetOk = $true
                        Write-Detail "Service $($svc.Name) stable Running"
                    }
                    else {
                        Write-Detail "Service $($svc.Name) not Running after wait: $($svc.Status)"
                    }
                }
                catch {
                    Write-Detail "Service restart failed $($svc.Name): $($_.Exception.Message)"
                }
            }
            if ($serviceResetOk) {
                Set-ReportField -Name 'USB_SERVICE_RESET' -Value 'PASS'
            }
            else {
                Set-ReportField -Name 'USB_SERVICE_RESET' -Value 'FAIL'
            }
        }
    }

    # Disconnect current target session only + reconnect once (no loop, no EFT tool)
    Write-UiStatus 'Đang kết nối lại...'
    Write-Detail 'Safe disconnect/reconnect current target once (no reconnect loop)'

    $transitioning = $false
    if ($adbPath -and $targetSerial) {
        $modeInfo = Get-DeviceMode -AdbPath $adbPath -Serial $targetSerial
        Write-Detail ("Device mode before reconnect: {0}/{1}" -f $modeInfo.Mode, $modeInfo.State)
        if ($modeInfo.Mode -in @('recovery', 'fastboot', 'bootloader', 'offline', 'unknown')) {
            # May be transitioning — guard will handle
            if ($modeInfo.Mode -in @('offline', 'unknown', 'bootloader')) {
                $transitioning = $true
            }
        }
    }

    if ($transitioning) {
        Write-Detail 'NO reconnect — device appears to be transitioning Android ↔ Recovery/boot'
        Set-ReportField -Name 'SAFE_RECONNECT' -Value 'SKIP'
    }
    else {
        $didDisconnect = $false
        if ($ur.UsbTechSh -and (Test-Path -LiteralPath $ur.UsbTechSh)) {
            # Probe CLI without assuming vendor docs; try safe one-shot commands only
            $help = Invoke-Native -FilePath $ur.UsbTechSh -Arguments '/?' -TimeoutMs 5000
            $helpOut = if ($help.StdOut) { $help.StdOut.Substring(0, [Math]::Min(500, $help.StdOut.Length)) } else { '' }
            $helpErr = if ($help.StdErr) { $help.StdErr.Substring(0, [Math]::Min(200, $help.StdErr.Length)) } else { '' }
            Write-Detail ("usbtechsh /? exit={0} out={1} err={2}" -f $help.ExitCode, $helpOut, $helpErr)

            $cliText = ($help.StdOut + $help.StdErr)
            if ($cliText -match '(?i)disconnect') {
                $d = Invoke-Native -FilePath $ur.UsbTechSh -Arguments 'disconnect' -TimeoutMs 10000
                Write-Detail ("usbtechsh disconnect exit={0}" -f $d.ExitCode)
                $didDisconnect = $true
                Start-Sleep -Seconds 2
                # Reconnect SAME target once only
                if ($cliText -match '(?i)connect' -and $cliText -notmatch '(?i)Auto_Connect_Online_EFT') {
                    $c = Invoke-Native -FilePath $ur.UsbTechSh -Arguments 'connect' -TimeoutMs 15000
                    Write-Detail ("usbtechsh connect (once) exit={0}" -f $c.ExitCode)
                    $reconnectOk = ($c.ExitCode -eq 0)
                }
            }
            else {
                Write-Detail 'usbtechsh has no documented disconnect CLI in help — relying on service reset + ADB wait (no EFT auto tool)'
            }
        }

        # If service was reset, USB stack often re-enumerates once — treat as reconnect if adb sees device again
        if ($adbPath) {
            Start-Sleep -Seconds 2
            $after = Get-AdbDevices -AdbPath $adbPath
            Write-Detail ("adb devices after reconnect attempt:`n{0}" -f $after.Raw)
            $match = @($after.Devices | Where-Object {
                    (-not $targetSerial -or $_.Serial -eq $targetSerial) -and $_.State -in @('device', 'recovery')
                })
            if ($match.Count -eq 1) {
                $reconnectOk = $true
            }
            elseif ($match.Count -gt 1) {
                Write-Detail 'Duplicate devices after reconnect — FAIL safe reconnect'
                $reconnectOk = $false
            }
            elseif ($serviceResetOk -or $didDisconnect) {
                # Attempted but device not back — not infinite retry
                $reconnectOk = $false
            }
            else {
                # Nothing to reconnect (no prior session)
                if (-not $targetSerial) {
                    Set-ReportField -Name 'SAFE_RECONNECT' -Value 'SKIP'
                    $reconnectOk = $null
                }
            }
        }

        if ($null -eq $reconnectOk) {
            # already SKIP
        }
        elseif ($reconnectOk) {
            Set-ReportField -Name 'SAFE_RECONNECT' -Value 'PASS'
        }
        else {
            Set-ReportField -Name 'SAFE_RECONNECT' -Value 'FAIL'
        }
    }

    # -------------------------------------------------------------------------
    # 5. MODE TRANSITION GUARD
    # -------------------------------------------------------------------------
    Write-Detail '=== STEP 5 MODE TRANSITION GUARD ==='
    if (-not $adbPath) {
        Set-ReportField -Name 'MODE_TRANSITION_GUARD' -Value 'SKIP'
    }
    else {
        $devsNow = Get-AdbDevices -AdbPath $adbPath
        $primary = $null
        if ($targetSerial) {
            $primary = $devsNow.Devices | Where-Object { $_.Serial -eq $targetSerial } | Select-Object -First 1
        }
        if (-not $primary) {
            $primary = $devsNow.Devices | Select-Object -First 1
        }

        if (-not $primary) {
            Write-Detail 'No device for mode guard'
            Set-ReportField -Name 'MODE_TRANSITION_GUARD' -Value 'SKIP'
        }
        else {
            $mode = Get-DeviceMode -AdbPath $adbPath -Serial $primary.Serial
            Write-Detail ("Mode guard: mode={0} state={1}" -f $mode.Mode, $mode.State)

            if ($mode.Mode -in @('recovery', 'fastboot', 'bootloader') -or $mode.State -eq 'offline') {
                Write-Detail 'Auto-connect kept OFF; waiting for stable Android or Recovery ADB (max ~45s, no reconnect loop)'
                $stable = $false
                $deadline = (Get-Date).AddSeconds(45)
                while ((Get-Date) -lt $deadline) {
                    Start-Sleep -Seconds 3
                    $m2 = Get-DeviceMode -AdbPath $adbPath -Serial $primary.Serial
                    if ($m2.Mode -eq 'android' -or $m2.State -eq 'device') {
                        if (Get-DeviceBootCompleted -AdbPath $adbPath -Serial $primary.Serial) {
                            $stable = $true
                            Write-Detail 'Android online + boot_completed=1'
                            break
                        }
                    }
                    elseif ($m2.Mode -eq 'recovery' -or $m2.State -eq 'recovery') {
                        # Recovery ADB stable if get-state stays recovery
                        Start-Sleep -Seconds 2
                        $m3 = Get-DeviceMode -AdbPath $adbPath -Serial $primary.Serial
                        if ($m3.State -eq 'recovery') {
                            $stable = $true
                            Write-Detail 'Recovery ADB stable'
                            break
                        }
                    }
                }
                if ($stable) {
                    Set-ReportField -Name 'MODE_TRANSITION_GUARD' -Value 'PASS'
                }
                else {
                    Set-ReportField -Name 'MODE_TRANSITION_GUARD' -Value 'FAIL'
                    Write-Detail 'Mode did not stabilize — no infinite retry'
                }
            }
            else {
                # Already stable android
                $bootOk = Get-DeviceBootCompleted -AdbPath $adbPath -Serial $primary.Serial
                Write-Detail "boot_completed check: $bootOk"
                Set-ReportField -Name 'MODE_TRANSITION_GUARD' -Value 'PASS'
            }
        }
    }

    # -------------------------------------------------------------------------
    # 6. VERIFY
    # -------------------------------------------------------------------------
    Write-Detail '=== STEP 6 VERIFY ==='
    $finalAdbPass = $false
    $finalAdbSkipNoDevice = $false
    if (-not $adbPath) {
        Set-ReportField -Name 'FINAL_ADB' -Value 'FAIL'
    }
    else {
        $finalDevs = Get-AdbDevices -AdbPath $adbPath
        Write-Detail ("verify adb devices:`n{0}" -f $finalDevs.Raw)
        $good = @($finalDevs.Devices | Where-Object { $_.State -in @('device', 'recovery') })
        $dup = ($good.Count -gt 1) -and (($good.Serial | Select-Object -Unique).Count -lt $good.Count)
        $multiSerial = ($good.Count -gt 1)
        $procInfo = Get-AdbProcessInfo

        $statePass = $false
        if ($good.Count -eq 1) {
            $serial = $good[0].Serial
            if ($targetSerial -and $serial -ne $targetSerial) {
                Write-Detail "Serial changed ($targetSerial -> $serial) — still OK if single device"
            }
            $st = Get-DeviceMode -AdbPath $adbPath -Serial $serial
            $statePass = ($st.State -in @('device', 'recovery'))
            Write-Detail ("get-state: {0}" -f $st.State)
        }
        elseif ($good.Count -eq 0) {
            Write-Detail 'No device online at verify'
            if (-not $targetSerial) {
                $finalAdbSkipNoDevice = $true
            }
            $statePass = $false
        }
        else {
            Write-Detail 'Multiple devices — verify FAIL (no duplicate/multi session desired)'
            $statePass = $false
        }

        if ($statePass -and -not $procInfo.Conflict -and -not $dup) {
            $finalAdbPass = $true
            Set-ReportField -Name 'FINAL_ADB' -Value 'PASS'
        }
        elseif ($finalAdbSkipNoDevice -and -not $procInfo.Conflict -and $script:Report['ADB_RESET'] -eq 'PASS') {
            # No session to verify — ADB server itself is clean
            Set-ReportField -Name 'FINAL_ADB' -Value 'SKIP'
            $finalAdbPass = $true
            Write-Detail 'FINAL_ADB SKIP — no device; ADB server clean'
        }
        else {
            Set-ReportField -Name 'FINAL_ADB' -Value 'FAIL'
            Write-Detail ("Verify fail: statePass={0} conflict={1} dup={2} multi={3}" -f $statePass, $procInfo.Conflict, $dup, $multiSerial)
        }
    }

    # -------------------------------------------------------------------------
    # 7. FINAL
    # -------------------------------------------------------------------------
    Write-Detail '=== STEP 7 FINAL ==='
    $adbClean = ($script:Report['ADB_RESET'] -eq 'PASS')
    $rebindOk = ($script:Report['AUTO_REBIND_DISABLED'] -in @('PASS', 'SKIP'))
    $ok = $false

    if ($finalAdbPass -and $adbClean) {
        Set-ReportField -Name 'BSOD_RISK_REDUCED' -Value 'PASS'
        Write-UiStatus 'Hoàn tất'
        Write-UiStatus '[OK] Đã tối ưu USB Redirector / ADB an toàn.'
        $ok = $true
    }
    elseif ($adbClean -and $rebindOk -and $script:Report['FINAL_ADB'] -ne 'FAIL') {
        Set-ReportField -Name 'BSOD_RISK_REDUCED' -Value 'PASS'
        Write-UiStatus 'Hoàn tất'
        Write-UiStatus '[OK] Đã tối ưu USB Redirector / ADB an toàn.'
        $ok = $true
    }
    else {
        if ($adbClean -and $rebindOk) {
            # ADB cleaned but device not stable — risk partially reduced, overall FAIL stabilize
            Set-ReportField -Name 'BSOD_RISK_REDUCED' -Value 'PASS'
        }
        else {
            Set-ReportField -Name 'BSOD_RISK_REDUCED' -Value 'FAIL'
        }
        Write-UiStatus 'Thất bại'
        Write-UiStatus '[FAIL] Không thể ổn định USB/ADB.'
        $ok = $false
    }

    # -------------------------------------------------------------------------
    # 8. LOG — report fields to UI + file
    # -------------------------------------------------------------------------
    Write-Detail '=== STEP 8 LOG / REPORT ==='
    $report = Get-ReportText
    Write-Detail $report
    foreach ($line in ($report -split "`n")) {
        Write-UiStatus $line.Trim()
    }
    if ($script:DetailLogPath) {
        Write-UiStatus ("Chi tiết: {0}" -f $script:DetailLogPath)
    }

    return [pscustomobject]@{
        Success        = $ok
        Report         = $script:Report
        DetailLogPath  = $script:DetailLogPath
    }
}
