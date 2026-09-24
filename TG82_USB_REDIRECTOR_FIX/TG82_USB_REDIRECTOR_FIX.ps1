#Requires -Version 5.1
<#
.SYNOPSIS
  TG82 USB Redirector Fix — tiny UI: AUTO FIX BSOD ADB + COLLECT BSOD LOG.
#>
[CmdletBinding()]
param(
    [ValidateSet('Gui', 'AutoFix', 'Collect')]
    [string]$Mode = 'Gui'
)

$ErrorActionPreference = 'Continue'
$Root = $PSScriptRoot
if (-not $Root) { $Root = Split-Path -Parent $MyInvocation.MyCommand.Path }

. (Join-Path $Root 'lib\Common.ps1')
. (Join-Path $Root 'lib\AutoFix.ps1')
. (Join-Path $Root 'lib\CollectLog.ps1')

Initialize-ToolEnvironment

function Start-ToolGui {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'TG82 USB Redirector Fix'
    $form.Size = New-Object System.Drawing.Size(520, 420)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $true

    $btnFix = New-Object System.Windows.Forms.Button
    $btnFix.Text = 'AUTO FIX BSOD ADB'
    $btnFix.Size = New-Object System.Drawing.Size(230, 40)
    $btnFix.Location = New-Object System.Drawing.Point(20, 20)
    $btnFix.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)

    $btnCollect = New-Object System.Windows.Forms.Button
    $btnCollect.Text = 'COLLECT BSOD LOG'
    $btnCollect.Size = New-Object System.Drawing.Size(230, 40)
    $btnCollect.Location = New-Object System.Drawing.Point(270, 20)
    $btnCollect.Font = New-Object System.Drawing.Font('Segoe UI', 10)

    $logBox = New-Object System.Windows.Forms.TextBox
    $logBox.Multiline = $true
    $logBox.ReadOnly = $true
    $logBox.ScrollBars = 'Vertical'
    $logBox.Location = New-Object System.Drawing.Point(20, 80)
    $logBox.Size = New-Object System.Drawing.Size(460, 280)
    $logBox.Font = New-Object System.Drawing.Font('Consolas', 9)
    $logBox.BackColor = [System.Drawing.Color]::White

    $form.Controls.AddRange(@($btnFix, $btnCollect, $logBox))

    $state = @{ Busy = $false }

    $appendUi = {
        param([string]$Message)
        if ($logBox.InvokeRequired) {
            [void]$logBox.Invoke([Action[string]]{
                    param($m)
                    $logBox.AppendText($m + [Environment]::NewLine)
                }, $Message)
        }
        else {
            $logBox.AppendText($Message + [Environment]::NewLine)
        }
    }
    Set-UiLogCallback -Callback $appendUi

    $btnFix.Add_Click({
            if ($state.Busy) { return }
            $state.Busy = $true
            $btnFix.Enabled = $false
            $btnCollect.Enabled = $false
            $logBox.Clear()
            try {
                Initialize-ToolEnvironment
                Set-UiLogCallback -Callback $appendUi
                [void](Invoke-AutoFixBsodAdb)
            }
            catch {
                Write-UiStatus 'Thất bại'
                Write-UiStatus ("[FAIL] {0}" -f $_.Exception.Message)
            }
            finally {
                $state.Busy = $false
                $btnFix.Enabled = $true
                $btnCollect.Enabled = $true
            }
        }.GetNewClosure())

    $btnCollect.Add_Click({
            if ($state.Busy) { return }
            $state.Busy = $true
            $btnFix.Enabled = $false
            $btnCollect.Enabled = $false
            $logBox.Clear()
            try {
                Initialize-ToolEnvironment
                Set-UiLogCallback -Callback $appendUi
                [void](Invoke-CollectBsodLog)
            }
            catch {
                Write-UiStatus 'Thất bại'
                Write-UiStatus ("[FAIL] {0}" -f $_.Exception.Message)
            }
            finally {
                $state.Busy = $false
                $btnFix.Enabled = $true
                $btnCollect.Enabled = $true
            }
        }.GetNewClosure())

    [void]$form.ShowDialog()
}

switch ($Mode) {
    'AutoFix' {
        Set-UiLogCallback -Callback { param($m) Write-Host $m }
        $r = Invoke-AutoFixBsodAdb
        if (-not $r.Success) { exit 1 }
        exit 0
    }
    'Collect' {
        Set-UiLogCallback -Callback { param($m) Write-Host $m }
        $r = Invoke-CollectBsodLog
        if (-not $r.Success) { exit 1 }
        exit 0
    }
    default {
        Start-ToolGui
    }
}
