@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%~dp0.."

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "Get-ChildItem -LiteralPath '%SCRIPT_DIR%' -Filter '*.ps1' -Recurse | Unblock-File -ErrorAction SilentlyContinue; Unblock-File -LiteralPath '%REPO_ROOT%\Vagrantfile' -ErrorAction SilentlyContinue; Write-Host 'PowerShell files unblocked for this repository.' -ForegroundColor Green"

exit /b %ERRORLEVEL%
