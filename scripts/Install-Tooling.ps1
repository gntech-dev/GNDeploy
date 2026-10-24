#Requires -Version 5.1
[CmdletBinding()]param([string]$Root="$env:LOCALAPPDATA\GNDeploy",[switch]$IncludeIsolatedBuilder)
$ErrorActionPreference='Stop'
if($Root -match '(?i)OneDrive'){throw 'Las herramientas deben instalarse fuera de OneDrive.'}
Import-Module "$(Split-Path $PSScriptRoot)\src\GNDeploy\GNDeploy.psd1" -Force
New-Item -ItemType Directory -Force -Path "$Root\Downloads","$Root\Tools","$Root\Logs" | Out-Null
$inno="$Root\Tools\innoextract\innoextract.exe"
if(-not(Test-Path $inno)) {
    $zip=Save-GNDownload -Uri 'https://constexpr.org/innoextract/files/innoextract-1.9/innoextract-1.9-windows.zip' -Destination "$Root\Downloads\innoextract-1.9.zip" -Sha256 '6989342C9B026A00A72A38F23B62A8E6A22CC5DE69805CF47D68AC2FEC993065'
    Expand-Archive -LiteralPath $zip -DestinationPath "$Root\Tools\innoextract" -Force
}
$seven="$Root\Tools\7zip\7z.exe"
if(-not(Test-Path $seven)) {
    $bootstrap=Save-GNDownload -Uri 'https://www.7-zip.org/a/7zr.exe' -Destination "$Root\Downloads\7zr-bootstrap.exe"
    $installer=Save-GNDownload -Uri 'https://www.7-zip.org/a/7z2605-x64.exe' -Destination "$Root\Downloads\7zip-26.05.exe" -Sha256 'FD99E86F57D8F429EF5ED045BF98315AF962E2309B0F1BA87A147A44C71647D0'
    & $bootstrap x $installer "-o$Root\Tools\7zip" -y -bso0
    if($LASTEXITCODE -ne 0){throw 'No se pudo extraer 7-Zip.'}
}
if($IncludeIsolatedBuilder -and -not(Test-Path "$Root\Tools\qemu\qemu-system-x86_64.exe")) {
    $uri='https://qemu.weilnetz.de/w64/qemu-w64-setup-20260811.exe'
    $installer=Save-GNDownload -Uri $uri -Destination "$Root\Downloads\qemu-20260811.exe"
    $checksumFile=Save-GNDownload -Uri 'https://qemu.weilnetz.de/w64/qemu-w64-setup-20260811.sha512' -Destination "$Root\Downloads\qemu-20260811.sha512"
    $expected=(Get-Content $checksumFile -Raw).Split(' ')[0].Trim()
    if((Get-FileHash $installer -Algorithm SHA512).Hash -ne $expected){throw 'Hash QEMU incorrecto.'}
    & $seven x $installer "-o$Root\Tools\qemu" -y -bso0
    if($LASTEXITCODE -ne 0){throw 'No se pudo extraer QEMU.'}
}
Get-ChildItem "$Root\Tools" -Recurse -Filter *.exe | Select-Object FullName,@{n='Sha256';e={(Get-FileHash -LiteralPath $_.FullName).Hash}} | ConvertTo-Json | Set-Content "$Root\Logs\tooling-manifest.json" -Encoding UTF8
Write-Host "Herramientas preparadas en $Root\Tools"
