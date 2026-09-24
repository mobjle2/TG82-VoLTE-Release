@echo off
REM ADB Safe Session launcher (Windows)
REM Phien ADB An Toan — launcher
setlocal
cd /d "%~dp0"

REM Bypass local ExecutionPolicy for this script only (does not change machine policy).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AdbSafe.ps1" %*
set EXITCODE=%ERRORLEVEL%

if not "%EXITCODE%"=="0" (
  echo.
  echo [VI] Loi thoat ma %EXITCODE%. Neu PowerShell bi chan, chay:
  echo [EN] Exit code %EXITCODE%. If PowerShell is blocked, run:
  echo   powershell -ExecutionPolicy Bypass -File "%~dp0AdbSafe.ps1"
  pause
)
endlocal & exit /b %EXITCODE%
