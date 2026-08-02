@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\update-expedition-records.ps1" %*
exit /b %errorlevel%
