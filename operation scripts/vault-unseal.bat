@echo off

for /L %%i in (1,1,3) do (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { . .\..\scripts\lab-config.ps1; & .\..\scripts\vault-unseal.ps1 }"
)