@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\update-base-records.ps1" %*
exit /b %errorlevel%
