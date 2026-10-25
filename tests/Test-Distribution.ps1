#Requires -Version 5.1
$ErrorActionPreference='Stop'
$source=Split-Path $PSScriptRoot
$root=Join-Path $env:TEMP ('GNDeploy-DistributionTest-'+[guid]::NewGuid().ToString('N'))
function Check($ok,$message){if(-not $ok){throw $message};Write-Host "PASS $message"}
$build=& "$source\scripts\Build-Distribution.ps1" -OutputRoot "$root\Build"
Check (Test-Path $build.PackagePath) 'ZIP de modulo generado'
$installed=& "$source\Install-GNDeploy.ps1" -PackagePath $build.PackagePath -ExpectedSha256 $build.SHA256 -Destination "$root\Modules"
$markerName='module-identity-'+[guid]::NewGuid().ToString('N')+'.txt'
$marker=Join-Path (Split-Path $installed.ModulePath) $markerName
[IO.File]::WriteAllText($marker,$markerName)
Import-Module $installed.ModulePath -Force
$v=Get-GNDeployVersion
$loadedMarker=Join-Path $v.ModuleRoot $markerName
Check ($v.Version -eq '0.2.1' -and (Test-Path -LiteralPath $loadedMarker) -and [IO.File]::ReadAllText($loadedMarker) -eq $markerName) 'Modulo importado desde instalacion aislada'
Remove-Item -LiteralPath $marker
Check (Test-Path "$($v.ProjectRoot)\src\Start-GNDeployGui.ps1") 'GUI y scripts de construccion incluidos'
$workspace=New-GNDeployWorkspace -Path "$root\Workspace"
Check ((Test-Path "$($workspace.Path)\Autopilot\Profiles") -and @(Get-ChildItem $workspace.Catalogs -File).Count -gt 0) 'Workspace con carpetas y catalogos'
'keep' | Set-Content "$($workspace.Catalogs)\custom.json"
$null=New-GNDeployWorkspace -Path $workspace.Path
Check ((Get-Content "$($workspace.Catalogs)\custom.json") -eq 'keep') 'Crear workspace conserva contenido propio'
$again=& "$source\Install-GNDeploy.ps1" -PackagePath $build.PackagePath -ExpectedSha256 $build.SHA256 -Destination "$root\Modules"
Check ($again.ModulePath -eq $installed.ModulePath) 'Reinstalacion identica es idempotente'
# GitHub serves release assets as application/octet-stream. Read checksums from the saved file.
function Invoke-WebRequest {param([switch]$UseBasicParsing,[int]$TimeoutSec,[string]$Uri,[string]$OutFile)
    if($Uri.EndsWith('.zip')){Copy-Item -LiteralPath $build.PackagePath -Destination $OutFile}
    elseif($Uri.EndsWith('/SHA256SUMS.txt')){[IO.File]::WriteAllBytes($OutFile,[Text.Encoding]::ASCII.GetBytes($build.SHA256+'  '+[IO.Path]::GetFileName($build.PackagePath)+"`r`n"))}
    else{throw 'Solicitud inesperada en prueba de instalacion GitHub.'}
}
try{$remote=& "$source\Install-GNDeploy.ps1" -Repository example/GNDeploy -Tag ('v'+$v.Version) -Destination "$root\RemoteModules";Check ($remote.Version -eq $v.Version -and (Test-Path $remote.ModulePath)) 'Instalacion GitHub procesa checksum binario guardado'}finally{Remove-Item Function:\Invoke-WebRequest}
$blocked=$false;try{& "$source\Install-GNDeploy.ps1" -PackagePath $build.PackagePath -ExpectedSha256 ('0'*64) -Destination "$root\Bad"}catch{$blocked=$true};Check $blocked 'Hash incorrecto bloquea instalacion'
$blocked=$false;try{& "$source\Install-GNDeploy.ps1" -PackagePath $build.PackagePath -ExpectedSha256 $build.SHA256 -Destination "$root\OneDrive\Modules"}catch{$blocked=$true};Check $blocked 'Instalacion en OneDrive bloqueada'
$blocked=$false;try{New-GNDeployWorkspace -Path "$root\OneDrive\Workspace"}catch{$blocked=$true};Check $blocked 'Workspace OneDrive bloqueado'
$blocked=$false;try{Start-GNDeploy}catch{$blocked=$true};Check $blocked 'Despliegue real bloqueado fuera de WinPE'
$module=Get-Module GNDeploy
Check ($module.ExportedCommands.ContainsKey('New-GNDeployUSB') -and $module.ExportedCommands.ContainsKey('New-GNDeployWindowsImage')) 'Comandos publicos de USB y mantenimiento exportados'
& $module {function script:Start-Process {param($FilePath,$ArgumentList,$WindowStyle,[switch]$Wait,[switch]$PassThru) [pscustomobject]@{FilePath=$FilePath;Arguments=$ArgumentList}}}
$launch=Start-GNDeploy -Preview
Check ($launch.Arguments -match '-STA' -and $launch.Arguments -match '-Preview' -and $launch.Arguments.Contains('"'+$v.ProjectRoot+'\src\Start-GNDeployGui.ps1"')) 'Comando de entrada usa STA y ruta completa entre comillas'
# Attack fixture: archive traversal must be rejected even with a matching ZIP checksum.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$attack=Join-Path $root 'traversal.zip';$z=[IO.Compression.ZipFile]::Open($attack,'Create');$entry=$z.CreateEntry('../outside.txt');$writer=New-Object IO.StreamWriter($entry.Open());$writer.Write('fixture');$writer.Dispose();$z.Dispose()
$blocked=$false;try{& "$source\Install-GNDeploy.ps1" -PackagePath $attack -ExpectedSha256 (Get-FileHash $attack).Hash -Destination "$root\Attack"}catch{$blocked=$_.Exception.Message -like '*ruta fuera*'};Check $blocked 'ZIP con traversal bloqueado'
$gui=Join-Path $v.ProjectRoot 'src\Start-GNDeployGui.ps1'
& powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File $gui -Preview -VerifyPreview -RenderPath "$root\installed-gui.png"
Check ($LASTEXITCODE -eq 0 -and (Test-Path "$root\installed-gui.png")) 'GUI instalada supera pruebas en proceso nuevo'
Write-Host "Evidencia: $root"

