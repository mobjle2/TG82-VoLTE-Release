@echo off
REM Fix Xanh Man — launcher nhanh toi AdbSafe
REM Double-click file nay tu D:\TOOL\Fix Xanh Man Khoi Dong lai\
setlocal
cd /d "%~dp0"

if not exist "%~dp0adb-safe\AdbSafe.bat" (
  echo [VI] Khong tim thay adb-safe\AdbSafe.bat
  echo [EN] Missing adb-safe\AdbSafe.bat
  echo      Chay CaiDat-Ve-O-D.ps1 neu chua cai du project.
  pause
  exit /b 1
)

call "%~dp0adb-safe\AdbSafe.bat" %*
set EXITCODE=%ERRORLEVEL%
endlocal & exit /b %EXITCODE%
