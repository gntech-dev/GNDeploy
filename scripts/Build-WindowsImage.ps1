#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]param(
    [Parameter(Mandatory)][string]$RecipePath,
    [string]$Root="$env:LOCALAPPDATA\GNDeploy"
)
$ErrorActionPreference='Stop'
if ($Root -match '(?i)OneDrive') { throw 'El mantenimiento de imagenes debe ejecutarse fuera de OneDrive.' }
$recipe=Get-Content -LiteralPath $RecipePath -Raw | ConvertFrom-Json
$allowed=@('SchemaVersion','Name','SourceImage','SourceIndex','Packages','Drivers')
foreach($property in $recipe.PSObject.Properties.Name) { if ($property -notin $allowed) {throw "Propiedad no admitida en receta: $property"} }
if ($recipe.SchemaVersion -ne 1 -or $recipe.Name -notmatch '^[a-zA-Z0-9_-]{1,60}$') { throw 'Receta no valida.' }
$source=(Resolve-Path -LiteralPath $recipe.SourceImage).Path
$packages=@($recipe.Packages | Where-Object {$_})
foreach ($package in $packages) {
    if (-not (Test-Path -LiteralPath $package.Path) -or $package.Sha256 -notmatch '^[a-fA-F0-9]{64}$' -or (Get-FileHash -LiteralPath $package.Path).Hash -ne $package.Sha256) { throw "Paquete ausente o hash incorrecto: $($package.Path)" }
}
$drivers=@($recipe.Drivers | Where-Object {$_})
foreach ($driver in $drivers) { if (@(Get-ChildItem -LiteralPath $driver -Filter *.inf -Recurse).Count -eq 0) {throw "Carpeta sin INF: $driver"} }
$build=Join-Path $Root ('Build\'+$recipe.Name+'-'+(Get-Date -Format yyyyMMddHHmmss))
$mount=Join-Path $env:ProgramData ('GNDeploy\M\'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $mount | Out-Null
$dism="${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\DISM\dism.exe"
function Run([string[]]$ArgumentList) { & $dism @ArgumentList | Out-Host; if ($LASTEXITCODE -notin @(0,3010)) {throw "DISM fallo: $LASTEXITCODE"} }
$mounted=$false
Start-Transcript -Path "$build\servicing.log"
try {
    Copy-Item -LiteralPath $RecipePath -Destination "$build\recipe.json"
    Run @('/Export-Image',"/SourceImageFile:$source","/SourceIndex:$($recipe.SourceIndex)","/DestinationImageFile:$build\working.wim",'/Compress:max','/CheckIntegrity')
    Run @('/Mount-Image',"/ImageFile:$build\working.wim",'/Index:1',"/MountDir:$mount")
    $mounted=$true
    # Explicit package order is part of the recipe: prerequisites/checkpoints first.
    foreach ($package in $packages) { Run @("/Image:$mount",'/Add-Package',"/PackagePath:$($package.Path)","/LogPath:$build\dism-packages.log") }
    foreach ($driver in $drivers) { Run @("/Image:$mount",'/Add-Driver',"/Driver:$driver",'/Recurse',"/LogPath:$build\dism-drivers.log") }
    Get-WindowsPackage -Path $mount | Select-Object PackageName,PackageState,ReleaseType | ConvertTo-Json | Set-Content "$build\packages.json" -Encoding UTF8
    Run @('/Unmount-Image',"/MountDir:$mount",'/Commit')
    $mounted=$false
    Run @('/Export-Image',"/SourceImageFile:$build\working.wim",'/SourceIndex:1',"/DestinationImageFile:$build\install.wim",'/Compress:max','/CheckIntegrity')
    @{State='Built-NotBootTested';Image="$build\install.wim";Sha256=(Get-FileHash "$build\install.wim").Hash;RecipeSha256=(Get-FileHash $RecipePath).Hash;SourceSha256=(Get-FileHash $source).Hash;Created=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content "$build\manifest.json" -Encoding UTF8
    Write-Host "Imagen creada: $build\install.wim"
} finally {
    if ($mounted) { & $dism /Unmount-Image "/MountDir:$mount" /Discard | Out-Host }
    Stop-Transcript
}
