#Requires -Version 5.1
[CmdletBinding()]param([string]$Root="$env:LOCALAPPDATA\GNDeploy")
$ErrorActionPreference='Stop'
if ($Root -match '(?i)OneDrive') { throw 'No instalar modulos dentro de OneDrive.' }
New-Item -ItemType Directory -Force -Path "$Root\Modules","$Root\Catalogs","$Root\Autopilot\Profiles","$Root\Drivers\Boot","$Root\Drivers\Offline","$Root\Images","$Root\Tools" | Out-Null
Copy-Item -LiteralPath "$(Split-Path $PSScriptRoot)\src\GNDeploy" -Destination "$Root\Modules" -Recurse -Force
Write-Host "Modulo instalado: $Root\Modules\GNDeploy"
Write-Host "Import-Module '$Root\Modules\GNDeploy\GNDeploy.psd1'"
