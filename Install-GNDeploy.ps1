#Requires -Version 5.1
# SPDX-License-Identifier: GPL-3.0-only
[CmdletBinding(DefaultParameterSetName='GitHub')]
param(
    [Parameter(ParameterSetName='GitHub')][ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repository='gntech-dev/GNDeploy',
    [Parameter(ParameterSetName='GitHub')][ValidatePattern('^v\d+\.\d+\.\d+$')][string]$Tag='v0.2.1',
    [Parameter(Mandatory,ParameterSetName='Local')][string]$PackagePath,
    [Parameter(Mandatory,ParameterSetName='Local')][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedSha256,
    [string]$Destination=(Join-Path $env:LOCALAPPDATA 'GNDeploy\Modules')
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1')
$destinationRoot=[IO.Path]::GetFullPath($Destination)
if($destinationRoot -match '(?i)OneDrive'){throw 'No instalar modulos dentro de OneDrive.'}
$work=Join-Path $env:LOCALAPPDATA ('GNDeploy\Install\'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$version=if($PSCmdlet.ParameterSetName -eq 'GitHub'){$Tag.Substring(1)}else{$null}
if($PSCmdlet.ParameterSetName -eq 'GitHub'){
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $base="https://github.com/$Repository/releases/download/$Tag"
    $name="GNDeploy-$version.zip"
    $PackagePath=Join-Path $work $name
    Invoke-WebRequest -UseBasicParsing -TimeoutSec 120 -Uri "$base/$name" -OutFile $PackagePath
    $checksumPath=Join-Path $work 'SHA256SUMS.txt'
    Invoke-WebRequest -UseBasicParsing -TimeoutSec 30 -Uri "$base/SHA256SUMS.txt" -OutFile $checksumPath
    $checksums=[IO.File]::ReadAllText($checksumPath)
    $line=@($checksums -split '\r?\n' | Where-Object {$_ -match ('^[a-fA-F0-9]{64}\s+\*?'+[regex]::Escape($name)+'$')})
    if($line.Count -ne 1){throw 'No se encontro una suma SHA-256 unica para el paquete.'}
    $ExpectedSha256=($line[0] -split '\s+')[0]
}
$archive=(Resolve-Path -LiteralPath $PackagePath).Path
if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $ExpectedSha256){throw 'El SHA-256 del paquete no coincide; no se instalara.'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$extract=Join-Path $work 'Extracted'
$extractRoot=[IO.Path]::GetFullPath($extract).TrimEnd('\')+'\'
$zip=[IO.Compression.ZipFile]::OpenRead($archive)
try{
    foreach($entry in $zip.Entries){
        $relative=$entry.FullName.Replace('/','\')
        $target=[IO.Path]::GetFullPath((Join-Path $extract $relative))
        if([IO.Path]::IsPathRooted($relative) -or $relative.Contains(':') -or -not $target.StartsWith($extractRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'El ZIP contiene una ruta fuera del paquete.'}
    }
}finally{$zip.Dispose()}
[IO.Compression.ZipFile]::ExtractToDirectory($archive,$extract)
$candidate=Join-Path $extract 'GNDeploy\GNDeploy.psd1'
if(-not(Test-Path -LiteralPath $candidate)){throw 'El ZIP no contiene GNDeploy/GNDeploy.psd1.'}
$data=Import-PowerShellDataFile $candidate
$packageVersion=[string]$data.ModuleVersion
if($packageVersion -notmatch '^\d+\.\d+\.\d+$' -or ($version -and $packageVersion -ne $version)){throw 'La version del paquete no coincide con la release.'}
if($data.GUID -ne '34b03eb9-adb4-4d73-8888-164f676a6042'){throw 'El paquete no corresponde a GNDeploy.'}
$null=Test-ModuleManifest -Path $candidate
$moduleRoot=Join-Path $destinationRoot "GNDeploy\$packageVersion"
if(Test-Path -LiteralPath $moduleRoot){
    if(@(Get-ChildItem $moduleRoot -Recurse -File).Count -ne @(Get-ChildItem (Split-Path $candidate) -Recurse -File).Count){throw 'Esta version ya existe con archivos adicionales o ausentes. Use un destino nuevo.'}
    foreach($file in Get-ChildItem (Split-Path $candidate) -Recurse -File){$relative=$file.FullName.Substring((Split-Path $candidate).Length+1);$installed=Join-Path $moduleRoot $relative;if(-not(Test-Path -LiteralPath $installed) -or (Get-FileHash $installed).Hash -ne (Get-FileHash $file.FullName).Hash){throw 'Esta version ya existe con contenido diferente. Use un destino nuevo o una release nueva.'}}
}else{
    New-Item -ItemType Directory -Path (Split-Path $moduleRoot) -Force | Out-Null
    Move-Item -LiteralPath (Split-Path $candidate) -Destination $moduleRoot
}
$modulePath=Join-Path $moduleRoot 'GNDeploy.psd1'
$env:PSModulePath=$destinationRoot+';'+$env:PSModulePath
[pscustomobject]@{Version=$packageVersion;ModulePath=$modulePath;ModuleSearchPath=$destinationRoot;PackageSHA256=$ExpectedSha256;Note='Import-Module con ModulePath; no se modifico el perfil ni se instalaron dependencias.'}

