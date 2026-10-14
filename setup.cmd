@echo off
rem Double-click this to set up WSL, Emacs and Syncthing on this PC.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
echo.
pause
