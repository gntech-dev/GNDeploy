# SPDX-License-Identifier: GPL-3.0-only
$script:GNProjectRoot=if(Test-Path (Join-Path $PSScriptRoot 'Project')){Join-Path $PSScriptRoot 'Project'}else{Split-Path (Split-Path $PSScriptRoot)}
function Get-GNDeployVersion {
    <# .SYNOPSIS Returns the installed module version and distribution paths. #>
    [CmdletBinding()]param()
    $manifest=Import-PowerShellDataFile (Join-Path $PSScriptRoot 'GNDeploy.psd1')
    [pscustomobject]@{Version=$manifest.ModuleVersion;ModuleRoot=$PSScriptRoot;ProjectRoot=$script:GNProjectRoot;License='GPL-3.0-only'}
}
function New-GNDeployWorkspace {
    <# .SYNOPSIS Creates content and build folders outside OneDrive; copies bundled catalogs. #>
    [CmdletBinding()]param([string]$Path=(Join-Path $env:LOCALAPPDATA 'GNDeploy'))
    $full=[IO.Path]::GetFullPath($Path)
    if($full -match '(?i)OneDrive'){throw 'El workspace debe estar fuera de OneDrive.'}
    foreach($part in @('Images','Drivers\Boot','Drivers\Offline','Autopilot\Profiles','Catalogs','Tools','Cache','Logs','Build')){New-Item -ItemType Directory -Path (Join-Path $full $part) -Force | Out-Null}
    foreach($file in Get-ChildItem (Join-Path $script:GNProjectRoot 'config\catalogs') -File){$target=Join-Path "$full\Catalogs" $file.Name;if(-not(Test-Path -LiteralPath $target)){Copy-Item -LiteralPath $file.FullName -Destination $target}}
    [pscustomobject]@{Path=$full;Images="$full\Images";Drivers="$full\Drivers\Offline";Autopilot="$full\Autopilot\Profiles";Catalogs="$full\Catalogs"}
}
function Start-GNDeploy {
    <# .SYNOPSIS Opens GNDeploy in a separate Windows PowerShell STA process. Preview never deploys Windows. #>
    [CmdletBinding()]param([switch]$Preview,[switch]$Wait)
    $gui=Join-Path $script:GNProjectRoot 'src\Start-GNDeployGui.ps1'
    if(-not(Test-Path -LiteralPath $gui)){throw 'La distribucion no contiene la interfaz. Reinstale el paquete completo.'}
    if(-not $Preview -and -not(Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')){throw 'Use Start-GNDeploy -Preview en Windows. El despliegue requiere WinPE/WinRE.'}
    $exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments='-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "'+$gui+'"'+$(if($Preview){' -Preview'}else{''})
    Start-Process -FilePath $exe -ArgumentList $arguments -WindowStyle Normal -Wait:$Wait -PassThru
}
function Install-GNDeployDependency {
    <# .SYNOPSIS Installs Microsoft ADK/WinPE with the existing signed-installer workflow. Requires elevation. #>
    [CmdletBinding(SupportsShouldProcess)]param([string]$Root=(Join-Path $env:LOCALAPPDATA 'GNDeploy'))
    if($PSCmdlet.ShouldProcess($Root,'Instalar Microsoft ADK y WinPE')){& (Join-Path $script:GNProjectRoot 'scripts\Install-Dependencies.ps1') -Root $Root}
}
function New-GNDeployISO {
    <# .SYNOPSIS Builds a new WinPE/WinRE ISO locally with ADK; does not download Windows installation media. #>
    [CmdletBinding()]param([ValidateSet('WinPE','WinRE')][string]$Base='WinPE',[string]$WinREPath,[string]$Root=(Join-Path $env:LOCALAPPDATA 'GNDeploy'),[string]$BootDriverPath,[switch]$IncludeImages,[switch]$UseCA2023)
    $null=New-GNDeployWorkspace -Path $Root
    & (Join-Path $script:GNProjectRoot 'scripts\Build-BootImage.ps1') -Base $Base -WinREPath $WinREPath -Root $Root -SourceRoot $script:GNProjectRoot -BootDriverPath $BootDriverPath -IncludeImages:$IncludeImages -UseCA2023:$UseCA2023
}
function New-GNDeployUSB {
    <# .SYNOPSIS Creates installer media on an explicitly identified USB. Supports WhatIf and confirmation. #>
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]param([Parameter(Mandatory)][int]$DiskNumber,[Parameter(Mandatory)][string]$ExpectedSerial,[Parameter(Mandatory)][uint64]$ExpectedSize,[Parameter(Mandatory)][string]$ISO,[string]$WorkRoot=(Join-Path $env:LOCALAPPDATA 'GNDeploy\USB'),[ValidateSet('UEFI','Dual')][string]$BootMode='UEFI',[string[]]$AdditionalImages=@())
    & (Join-Path $script:GNProjectRoot 'scripts\New-GNDeployUSB.ps1') @PSBoundParameters
}
function Export-GNDeployWinRE {
    <# .SYNOPSIS Extracts WinRE from a Windows image supplied by the operator. Requires elevation. #>
    [CmdletBinding()]param([Parameter(Mandatory)][string]$ImagePath,[ValidateRange(0,100)][int]$Index=0,[string]$Root=(Join-Path $env:LOCALAPPDATA 'GNDeploy'))
    & (Join-Path $script:GNProjectRoot 'scripts\Export-WinRE.ps1') -ImagePath $ImagePath -Index $Index -Root $Root
}
function New-GNDeployWindowsImage {
    <# .SYNOPSIS Services a user-supplied Windows image using a JSON recipe. Requires elevation. #>
    [CmdletBinding()]param([Parameter(Mandatory)][string]$RecipePath,[string]$Root=(Join-Path $env:LOCALAPPDATA 'GNDeploy'))
    & (Join-Path $script:GNProjectRoot 'scripts\Build-WindowsImage.ps1') -RecipePath $RecipePath -Root $Root
}
