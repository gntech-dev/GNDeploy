@echo off
reg query HKLM\SYSTEM\CurrentControlSet\Control\MiniNT >nul 2>&1
if errorlevel 1 (
  echo Ejecute esta actualizacion dentro de WinPE o WinRE.
  exit /b 1
)
if not exist "%~dp0GNDeploy\Start-GNDeployGui.ps1" exit /b 2
xcopy "%~dp0GNDeploy\*" X:\GNDeploy\ /E /I /H /Y
if errorlevel 1 exit /b 3
wpeutil SetKeyboardLayout 0409:00000409
if errorlevel 1 exit /b 4
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File X:\GNDeploy\Start-GNDeploy.ps1
