#Requires -Version 5.1
[CmdletBinding()]param(
    [string]$MachineType='20UN',
    [string]$Release='24H2',
    [string]$Root="$env:LOCALAPPDATA\GNDeploy",
    [switch]$IncludeOfflinePack
)
$ErrorActionPreference='Stop'
if ($Root -match '(?i)OneDrive') { throw 'Los drivers deben prepararse fuera de OneDrive.' }
Import-Module "$(Split-Path $PSScriptRoot)\src\GNDeploy\GNDeploy.psd1" -Force
New-Item -ItemType Directory -Force -Path "$Root\Downloads","$Root\Drivers\Boot","$Root\Drivers\Offline" | Out-Null
$extractor=Join-Path $Root 'Tools\innoextract\innoextract.exe'
if (-not (Test-Path -LiteralPath $extractor)) {
    $zip=Save-GNDownload -Uri 'https://constexpr.org/innoextract/files/innoextract-1.9/innoextract-1.9-windows.zip' -Destination "$Root\Downloads\innoextract-1.9.zip"
    Expand-Archive -LiteralPath $zip -DestinationPath "$Root\Tools\innoextract" -Force
}
$catalog=Join-Path $Root ('Downloads\lenovo-'+(Get-Date -Format yyyyMMddHHmmss)+'.xml')
$null=Save-GNDownload -Uri 'https://download.lenovo.com/cdrt/td/catalogv2.xml' -Destination $catalog
$packs=@(Get-GNLenovoDriverPack -CatalogPath $catalog -MachineType $MachineType -Release $Release | Sort-Object Date -Descending)
if ($packs.Count -eq 0) { throw "No hay pack Lenovo para $MachineType / $Release. No se eligio otra version automaticamente." }
$pack=$packs[0]
$expanded=Save-GNLenovoDriverPack -Pack $pack -CacheRoot "$Root\Cache\Lenovo" -Extractor $extractor
# Intel WLAN packages for the X1 Nano contain Netwtw*.inf; copy supporting files as a unit.
$wifiDirs=@(Get-ChildItem -LiteralPath $expanded -Filter 'Netwtw*.inf' -Recurse | ForEach-Object DirectoryName | Sort-Object -Unique)
if ($wifiDirs.Count -eq 0) {throw 'No se encontro el paquete WLAN Intel en el pack seleccionado.'}
foreach($dir in $wifiDirs) {
    $target=Join-Path "$Root\Drivers\Boot" ("Lenovo-$MachineType-WLAN-"+(Split-Path $dir -Leaf))
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Get-ChildItem -LiteralPath $dir | Copy-Item -Destination $target -Recurse -Force
}
if ($IncludeOfflinePack) {
    $target=Join-Path "$Root\Drivers\Offline" "Lenovo-$MachineType-$Release"
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Get-ChildItem -LiteralPath $expanded | Copy-Item -Destination $target -Recurse -Force
}
$serialDirs=@(Get-ChildItem -LiteralPath $expanded -Filter 'iaLPSS2*_TGL.inf' -Recurse | ForEach-Object DirectoryName | Sort-Object -Unique)
foreach($dir in $serialDirs){
    $target=Join-Path "$Root\Drivers\Boot" "Lenovo-$MachineType-SerialIO"
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Get-ChildItem -LiteralPath $dir | Copy-Item -Destination $target -Recurse -Force
}
@{Pack=$pack;Expanded=$expanded;BootWlan=$wifiDirs;Prepared=(Get-Date).ToString('o')} | ConvertTo-Json -Depth 8 | Set-Content "$Root\Drivers\lenovo-prepared.json" -Encoding UTF8
Write-Host "Drivers WLAN preparados para $MachineType / $Release. Pack completo: $expanded"
