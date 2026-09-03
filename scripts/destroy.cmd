@echo off
setlocal

set "SCRIPT_DIR=%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "Unblock-File '%SCRIPT_DIR%destroy.ps1' -ErrorAction SilentlyContinue; & '%SCRIPT_DIR%destroy.ps1'"

exit /b %ERRORLEVEL%
