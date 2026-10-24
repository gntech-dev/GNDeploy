@echo off
wpeinit
wpeutil SetKeyboardLayout 0409:00000409
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File X:\GNDeploy\Start-GNDeploy.ps1
cmd.exe
