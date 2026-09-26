@echo off

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { . .\..\scripts\lab-config.ps1; & .\..\scripts\jenkins-shutdown.ps1}"