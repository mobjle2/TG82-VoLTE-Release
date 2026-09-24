@echo off
REM Tuong thich ten cu — goi Fix.ps1 slim
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\Fix-Xanh-Man\Fix.ps1" %*
set EXITCODE=%ERRORLEVEL%
endlocal & exit /b %EXITCODE%
