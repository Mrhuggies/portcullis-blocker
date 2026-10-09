@echo off
rem Opens the Portcullis control panel in your browser.
rem Keep this file next to the "app" folder it came with.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0app\windows\panel.ps1"
