#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]param(
    [Parameter(Mandatory)][string]$MediaPath,
    [Parameter(Mandatory)][string]$OutputISO,
    [string]$SourceRoot=(Split-Path $PSScriptRoot),
    [string]$ValidationScript,
    [string]$BootDriverPath,
    [string]$PortableToolsPath=(Join-Path $env:USERPROFILE 'GNDeploy\Tools')
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
if($OutputISO -match '(?i)OneDrive'){throw 'La ISO debe quedar fuera de OneDrive.'}
if(Test-Path -LiteralPath $OutputISO){throw 'La ISO destino ya existe; elija un nombre nuevo.'}
$media=(Resolve-Path -LiteralPath $MediaPath).Path
if(Test-Path "$SourceRoot\config\catalogs"){
    New-Item -ItemType Directory -Path "$media\GNDeploy\Catalogs" -Force | Out-Null
    Copy-Item "$SourceRoot\config\catalogs\*" "$media\GNDeploy\Catalogs" -Force
}
foreach($metadata in @(Get-ChildItem "$SourceRoot\config\driver-metadata\*.json" -ErrorAction SilentlyContinue)){
    $pack=Join-Path "$media\GNDeploy\Drivers\Offline" $metadata.BaseName
    if(Test-Path -LiteralPath $pack){Copy-Item -LiteralPath $metadata.FullName -Destination (Join-Path $pack 'GNDeploy-pack.json') -Force}
}
$wim=Join-Path $media 'sources\boot.wim'
if(-not(Test-Path -LiteralPath $wim)){throw 'El medio no contiene sources\boot.wim.'}
$adk="${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64"
$mount=Join-Path $env:ProgramData ('GNDeploy\M\'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $mount,(Split-Path $OutputISO) | Out-Null
$mounted=$false
function Run([string]$File,[string[]]$Values){& $File @Values | Out-Host;if($LASTEXITCODE){throw "$File fallo: $LASTEXITCODE"}}
Start-Transcript -Path "$OutputISO.build.log"
try{
    Run "$adk\DISM\dism.exe" @('/Mount-Image',"/ImageFile:$wim",'/Index:1',"/MountDir:$mount")
    $mounted=$true
    Copy-Item "$SourceRoot\src\Start-GNDeploy.ps1","$SourceRoot\src\Start-GNDeployGui.ps1","$SourceRoot\src\GuiDialogs.ps1","$SourceRoot\src\GuiTools.ps1","$SourceRoot\src\Verify-GuestMenus.ps1" "$mount\GNDeploy" -Force
    Copy-Item "$SourceRoot\src\GuiWorkflow.ps1" "$mount\GNDeploy\GuiWorkflow.ps1" -Force
    if(Test-Path -LiteralPath $PortableToolsPath){
        New-Item -ItemType Directory -Path "$mount\GNDeploy\PortableTools" -Force | Out-Null
        foreach($tool in @('ExplorerPP','7Zip')){if(Test-Path "$PortableToolsPath\$tool"){Copy-Item "$PortableToolsPath\$tool" "$mount\GNDeploy\PortableTools" -Recurse -Force}}
    }
    Copy-Item "$SourceRoot\src\GNDeploy" "$mount\GNDeploy\Modules" -Recurse -Force
    Copy-Item "$SourceRoot\src\Verify-GuestTools.ps1" "$mount\GNDeploy" -Force
    Copy-Item "$adk\BCDBoot\bootsect.exe" "$mount\GNDeploy\Tools\bootsect.exe" -Force
    New-Item -ItemType Directory -Path "$mount\GNDeploy\Fonts" -Force | Out-Null
    foreach($fontName in @('segoeui.ttf','segoeuib.ttf')){Copy-Item -LiteralPath "$env:SystemRoot\Fonts\$fontName" -Destination "$mount\GNDeploy\Fonts\$fontName" -Force}
    Copy-Item "$SourceRoot\config\startnet.cmd","$SourceRoot\config\winpeshl.ini" "$mount\Windows\System32" -Force
    if($ValidationScript){
        Copy-Item -LiteralPath $ValidationScript -Destination "$mount\GNDeploy\LabValidation.ps1" -Force
        @'
[LaunchApps]
%SYSTEMROOT%\System32\wpeinit.exe
%SYSTEMROOT%\System32\WindowsPowerShell\v1.0\powershell.exe, -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -NoExit -File X:\GNDeploy\LabValidation.ps1
'@ | Set-Content "$mount\Windows\System32\winpeshl.ini" -Encoding ASCII
    }
    if($BootDriverPath){
        if(-not(Test-Path -LiteralPath $BootDriverPath -PathType Container)){throw 'No existe el paquete de drivers de arranque.'}
        Run "$adk\DISM\dism.exe" @("/Image:$mount",'/Add-Driver',"/Driver:$BootDriverPath",'/Recurse')
    }
    Run "$adk\DISM\dism.exe" @('/Unmount-Image',"/MountDir:$mount",'/Commit')
    $mounted=$false
    Run "$adk\Oscdimg\oscdimg.exe" @('-m','-o','-u2','-udfver102','-lGNDEPLOY',"-bootdata:2#p0,e,b$adk\Oscdimg\etfsboot.com#pEF,e,b$adk\Oscdimg\efisys.bin",$media,$OutputISO)
    @{ISO=$OutputISO;Sha256=(Get-FileHash -LiteralPath $OutputISO).Hash;Bytes=(Get-Item $OutputISO).Length;Created=(Get-Date).ToString('o');Interface=$(if($ValidationScript){'Isolated lab automation'}else{'Windows Forms'});Keyboard='0409:00000409';Status='Built-NotBootTested';AutomaticValidation=[bool]$ValidationScript} | ConvertTo-Json | Set-Content "$OutputISO.manifest.json" -Encoding UTF8
}catch{
    $_ | Out-String | Set-Content "$OutputISO.failure.txt";throw
}finally{
    if($mounted){& "$adk\DISM\dism.exe" /Unmount-Image "/MountDir:$mount" /Discard | Out-Host}
    Stop-Transcript
}


