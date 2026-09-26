@echo off

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { . .\..\scripts\lab-config.ps1; & .\..\scripts\down.ps1}"