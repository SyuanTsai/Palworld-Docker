@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0update-base-records.ps1" %*
exit /b %errorlevel%
