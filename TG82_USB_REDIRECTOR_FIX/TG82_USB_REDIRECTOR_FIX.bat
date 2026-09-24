@echo off
setlocal
title TG82 USB Redirector Fix
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0TG82_USB_REDIRECTOR_FIX.ps1" -Mode Gui
endlocal
