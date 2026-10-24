#Requires -Version 5.1
# SPDX-License-Identifier: GPL-3.0-only
[CmdletBinding()]param([string]$SourceRoot,[Parameter(Mandatory)][string]$OutputRoot)
$ErrorActionPreference='Stop'
if(-not $SourceRoot){$SourceRoot=Split-Path $PSScriptRoot}
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1')
$source=(Resolve-Path $SourceRoot).Path
$output=[IO.Path]::GetFullPath($OutputRoot)
if($output -match '(?i)OneDrive' -or $output.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Construya la distribucion fuera del repositorio y de OneDrive.'}
if(Test-Path -LiteralPath $output){throw 'El destino ya existe. Use una carpeta nueva para una distribucion inmutable.'}
$version=(Import-PowerShellDataFile "$source\src\GNDeploy\GNDeploy.psd1").ModuleVersion
$repo=Join-Path $output 'Repository'
$module=Join-Path $output 'Package\GNDeploy'
New-Item -ItemType Directory -Path "$repo\scripts","$repo\docs",$module -Force | Out-Null
$scripts=@('Build-Distribution.ps1','Build-BootImage.ps1','Build-WindowsImage.ps1','Export-WinRE.ps1','Install-Dependencies.ps1','Install-LocalRuntime.ps1','Install-Tooling.ps1','New-GNDeployUSB.ps1','Prepare-Lenovo.ps1','Update-BootRuntime.ps1','Update-GNDeployUSB.ps1','Update-WindowsCatalog.ps1')
foreach($name in $scripts){Copy-Item -LiteralPath "$source\scripts\$name" -Destination "$repo\scripts\$name"}
foreach($folder in @('src','config','tests','public','.github')){Copy-Item -LiteralPath "$source\$folder" -Destination $repo -Recurse}
foreach($name in @('LICENSE','Install-GNDeploy.ps1')){Copy-Item -LiteralPath "$source\$name" -Destination $repo}
Copy-Item -LiteralPath "$source\public\README.md" -Destination "$repo\README.md"
Copy-Item -LiteralPath "$source\public\USAGE.md" -Destination "$repo\docs\USAGE.md"
foreach($name in @('CHANGELOG.md','THIRD-PARTY-NOTICES.md')){Copy-Item -LiteralPath "$source\public\$name" -Destination "$repo\$name"}
foreach($name in @('GUIA-USO.md','T420-UEFI.md')){Copy-Item -LiteralPath "$source\docs\$name" -Destination "$repo\docs\$name"}
@('dist/','*.iso','*.wim','*.esd','*.vhd*','*.exe','*.zip','*.log','__pycache__/','*.pyc','.env','Autopilot/','Images/','Drivers/') | Set-Content "$repo\.gitignore" -Encoding ASCII
# Explicit allowlist: laboratory scripts, personal reports, binaries and profiles are not published.
foreach($file in Get-ChildItem $repo -Recurse -File){
    if($file.Extension -in @('.exe','.dll','.wim','.esd','.iso','.vhdx','.zip','.pyc')){throw "Archivo no permitido: $($file.FullName)"}
    if((Get-Content -LiteralPath $file.FullName -Raw) -match '(?i)[A-Z]:\\Users\\[^\\]+\\|OneDrive - [A-Z]'){throw "Referencia local no publicable: $($file.FullName)"}
}
Copy-Item "$repo\src\GNDeploy\*" $module -Recurse
New-Item -ItemType Directory -Path "$module\Project\src","$module\Project\scripts","$module\Project\config" -Force | Out-Null
Copy-Item "$repo\src\*" "$module\Project\src" -Recurse
Copy-Item "$repo\scripts\*" "$module\Project\scripts" -Recurse
Copy-Item "$repo\config\*" "$module\Project\config" -Recurse
Copy-Item "$repo\docs" "$module\Project" -Recurse
Copy-Item "$repo\LICENSE","$repo\README.md","$repo\CHANGELOG.md","$repo\THIRD-PARTY-NOTICES.md" $module
$null=Test-ModuleManifest "$module\GNDeploy.psd1"
$packagePath=Join-Path $output "GNDeploy-$version.zip"
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory((Split-Path $module),$packagePath)
$sha=(Get-FileHash $packagePath -Algorithm SHA256).Hash
"$sha  GNDeploy-$version.zip" | Set-Content "$output\SHA256SUMS.txt" -Encoding ASCII
Copy-Item "$source\Install-GNDeploy.ps1" "$output\Install-GNDeploy.ps1"
$files=@(Get-ChildItem $repo -Recurse -File | ForEach-Object {[pscustomobject]@{Path=$_.FullName.Substring($repo.Length+1);SHA256=(Get-FileHash $_.FullName).Hash;Bytes=$_.Length}})
@{Version=$version;Repository=$repo;Package=$packagePath;SHA256=$sha;Files=$files} | ConvertTo-Json -Depth 6 | Set-Content "$output\distribution.json" -Encoding UTF8
[pscustomobject]@{Version=$version;Repository=$repo;PackagePath=$packagePath;SHA256=$sha;ModulePath="$module\GNDeploy.psd1"}
