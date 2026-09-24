@echo off
REM Fix — tat ADB truoc Share / Unshare TG82 (giam rui ro xanh man)
setlocal
cd /d "%~dp0"

REM Neu can che do sau BSOD: Fix.bat -SauXanhMan
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fix.ps1" %*
set EXITCODE=%ERRORLEVEL%

if not "%EXITCODE%"=="0" (
  echo.
  echo Loi thoat ma %EXITCODE%. Thu:
  echo   powershell -ExecutionPolicy Bypass -File "%~dp0Fix.ps1"
  pause
)
endlocal & exit /b %EXITCODE%
