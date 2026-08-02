@echo off
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\combat-pal-awakening.ps1" %*
exit /b %errorlevel%
