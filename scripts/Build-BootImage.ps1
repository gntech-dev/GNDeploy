#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [ValidateSet('WinPE','WinRE')][string]$Base='WinPE',
    [string]$WinREPath,
    [string]$Root="$env:LOCALAPPDATA\GNDeploy",
    [string]$SourceRoot=(Split-Path $PSScriptRoot),
    [string]$BootDriverPath,
    [switch]$UseCA2023,
    [switch]$IncludeImages
)
$ErrorActionPreference='Stop'
if ($Root -match '(?i)OneDrive') { throw 'El build debe estar fuera de OneDrive.' }
$adk="${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit"
$peRoot=Join-Path $adk 'Windows Preinstallation Environment'
$ocRoot=Join-Path $peRoot 'amd64\WinPE_OCs'
$dism=Join-Path $adk 'Deployment Tools\amd64\DISM\dism.exe'
$oscdimg=Join-Path $adk 'Deployment Tools\amd64\Oscdimg\oscdimg.exe'
$baseWim=Join-Path $peRoot 'amd64\en-us\winpe.wim'
foreach ($file in @($dism,$oscdimg,$baseWim)) { if (-not (Test-Path -LiteralPath $file)) { throw "Dependencia ausente: $file" } }
if ($Base -eq 'WinRE') {
    if (-not $WinREPath -or -not (Test-Path -LiteralPath $WinREPath)) { throw 'Indique un winre.wim con -WinREPath.' }
    $baseWim=(Resolve-Path -LiteralPath $WinREPath).Path
    $sourceVersion=(Get-WindowsImage -ImagePath $baseWim -Index 1).Version
    $adkVersion=(Get-WindowsImage -ImagePath (Join-Path $peRoot 'amd64\en-us\winpe.wim') -Index 1).Version
    if ($sourceVersion.Build -ne $adkVersion.Build) { throw "WinRE $sourceVersion y paquetes ADK $adkVersion no coinciden. Use una fuente WinRE del mismo build base." }
}
$name='GNDeploy-{0}-{1}' -f $Base,(Get-Date -Format 'yyyyMMdd-HHmmss')
$build=Join-Path "$Root\Build" $name
$media=Join-Path $build 'media'
$mount=Join-Path $env:ProgramData ('GNDeploy\M\'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $build,$media,$mount -Force | Out-Null
Start-Transcript -Path (Join-Path $build 'build.log')
function Run([string]$File,[string[]]$ArgumentList) {
    & $File @ArgumentList | Out-Host
    if ($LASTEXITCODE -notin @(0,3010)) { throw "$File fallo: $LASTEXITCODE" }
}
$mounted=$false
try {
    Copy-Item -Path "$peRoot\amd64\Media\*" -Destination $media -Recurse -Force
    New-Item -ItemType Directory -Force -Path "$media\sources" | Out-Null
    Copy-Item -LiteralPath $baseWim -Destination "$media\sources\boot.wim"
    (Get-Item "$media\sources\boot.wim").IsReadOnly=$false
    Run $dism @('/Mount-Image',"/ImageFile:$media\sources\boot.wim",'/Index:1',"/MountDir:$mount")
    $mounted=$true
    $packageOutput=& $dism "/Image:$mount" /Get-Packages /English
    if ($LASTEXITCODE -ne 0) {throw 'No se pudo consultar el inventario de paquetes del boot.'}
    $installed=@($packageOutput | Where-Object {$_ -match '^Package Identity\s*:\s*(.+)$'} | ForEach-Object {($_ -split ':',2)[1].Trim()})
    # Dependency order follows Microsoft's WinPE PowerShell optional-components guidance.
    foreach ($component in @('WinPE-WMI','WinPE-NetFX','WinPE-Scripting','WinPE-PowerShell','WinPE-StorageWMI','WinPE-DismCmdlets','WinPE-SecureStartup')) {
        if (-not ($installed | Where-Object {$_ -like "$component-Package*"})) {
            Run $dism @("/Image:$mount",'/Add-Package',"/PackagePath:$ocRoot\$component.cab")
            $language=Join-Path $ocRoot "en-us\${component}_en-us.cab"
            if (Test-Path -LiteralPath $language) { Run $dism @("/Image:$mount",'/Add-Package',"/PackagePath:$language") }
        }
    }
    if ($Base -eq 'WinRE' -and -not (Test-Path "$mount\Windows\System32\wlanapi.dll")) { throw 'La fuente WinRE no tiene wlanapi.dll.' }
    if (-not $BootDriverPath) { $BootDriverPath=Join-Path $Root 'Drivers\Boot' }
    if (Test-Path -LiteralPath $BootDriverPath) {
        if (@(Get-ChildItem -LiteralPath $BootDriverPath -Filter *.inf -Recurse).Count -gt 0) { Run $dism @("/Image:$mount",'/Add-Driver',"/Driver:$BootDriverPath",'/Recurse') }
    }
    New-Item -ItemType Directory -Force -Path "$mount\GNDeploy\Modules","$mount\GNDeploy\Tools","$media\GNDeploy\Autopilot\Profiles","$media\GNDeploy\Images","$media\GNDeploy\Catalogs","$media\GNDeploy\Drivers\Offline" | Out-Null
    Copy-Item -LiteralPath "$SourceRoot\src\GNDeploy" -Destination "$mount\GNDeploy\Modules" -Recurse -Force
    Copy-Item -LiteralPath "$SourceRoot\src\Start-GNDeploy.ps1" -Destination "$mount\GNDeploy\Start-GNDeploy.ps1"
    Copy-Item -LiteralPath "$SourceRoot\src\Start-GNDeployGui.ps1" -Destination "$mount\GNDeploy\Start-GNDeployGui.ps1"
    Copy-Item -LiteralPath "$SourceRoot\src\GuiDialogs.ps1" -Destination "$mount\GNDeploy\GuiDialogs.ps1"
    Copy-Item -LiteralPath "$SourceRoot\src\GuiTools.ps1" -Destination "$mount\GNDeploy\GuiTools.ps1"
    Copy-Item -LiteralPath "$SourceRoot\src\GuiWorkflow.ps1" -Destination "$mount\GNDeploy\GuiWorkflow.ps1"
    New-Item -ItemType Directory -Path "$mount\GNDeploy\Fonts" -Force | Out-Null
    foreach($fontName in @('segoeui.ttf','segoeuib.ttf')){Copy-Item -LiteralPath "$env:SystemRoot\Fonts\$fontName" -Destination "$mount\GNDeploy\Fonts\$fontName" -Force}
    # Native curl relies on additional OS DLLs on some boot bases: startup tests it and download has a WebRequest fallback.
    Copy-Item -LiteralPath "$env:SystemRoot\System32\curl.exe" -Destination "$mount\GNDeploy\Tools\curl.exe"
    if (Test-Path "$Root\Tools\innoextract\innoextract.exe") { Copy-Item -Path "$Root\Tools\innoextract\*" -Destination "$mount\GNDeploy\Tools" -Recurse -Force }
    foreach ($item in @('Autopilot\Profiles','Catalogs','Drivers\Offline')) {
        if (Test-Path "$Root\$item") { Copy-Item -Path "$Root\$item\*" -Destination "$media\GNDeploy\$item" -Recurse -Force }
    }
    if ($IncludeImages -and (Test-Path "$Root\Images")) {
        Get-ChildItem -LiteralPath "$Root\Images" -File | Where-Object Extension -in @('.wim','.esd') | Copy-Item -Destination "$media\GNDeploy\Images" -Force
    }
    Copy-Item -LiteralPath "$SourceRoot\config\startnet.cmd" -Destination "$mount\Windows\System32\startnet.cmd" -Force
    # WinRE normally launches recovery UI; explicitly select the deployment shell.
    Copy-Item -LiteralPath "$SourceRoot\config\winpeshl.ini" -Destination "$mount\Windows\System32\winpeshl.ini" -Force
    Run $dism @("/Image:$mount",'/Set-ScratchSpace:512')
    $bootManager=Join-Path $mount 'Windows\Boot\EFI\bootmgfw.efi'
    if ($UseCA2023) { $bootManager=Join-Path $mount 'Windows\Boot\EFI_EX\bootmgfw_EX.efi' }
    if (-not (Test-Path -LiteralPath $bootManager)) { throw "Boot manager ausente: $bootManager" }
    Copy-Item -LiteralPath $bootManager -Destination "$media\EFI\Boot\bootx64.efi" -Force
    Copy-Item -LiteralPath $bootManager -Destination "$media\EFI\Microsoft\Boot\bootmgfw.efi" -Force
    Run $dism @('/Unmount-Image',"/MountDir:$mount",'/Commit')
    $mounted=$false
    $firmware=Join-Path $adk 'Deployment Tools\amd64\Oscdimg'
    $bios=Join-Path $firmware 'etfsboot.com'
    $efi=Join-Path $firmware 'efisys.bin'
    if ($UseCA2023) {
        $efi=Join-Path $firmware 'efisys_EX.bin'
    }
    foreach ($file in @($bios,$efi)) { if (-not (Test-Path -LiteralPath $file)) { throw "Archivo boot ausente: $file" } }
    $iso=Join-Path $build "$name.iso"
    Run $oscdimg @('-m','-o','-u2','-udfver102','-lGNDEPLOY',"-bootdata:2#p0,e,b$bios#pEF,e,b$efi",$media,$iso)
    $manifest=[ordered]@{Version='0.1.0';Base=$Base;SourceWim=$baseWim;SourceSha256=(Get-FileHash -LiteralPath $baseWim -Algorithm SHA256).Hash;ISO=$iso;Sha256=(Get-FileHash -LiteralPath $iso -Algorithm SHA256).Hash;Created=(Get-Date).ToString('o');CA2023=[bool]$UseCA2023;Status='Built-NotBootTested'}
    $manifest | ConvertTo-Json | Set-Content (Join-Path $build 'manifest.json') -Encoding UTF8
    $manifest | ConvertTo-Json | Set-Content (Join-Path $Root 'latest-build.json') -Encoding UTF8
    Write-Host "ISO creada: $iso"
} catch {
    @{State='Failed';Error=$_.Exception.Message;Location=[string]$_.InvocationInfo.PositionMessage} | ConvertTo-Json | Set-Content (Join-Path $build 'failure.json') -Encoding UTF8
    Write-Host ($_ | Out-String) -ForegroundColor Red
    throw
} finally {
    if ($mounted) { & $dism /Unmount-Image "/MountDir:$mount" /Discard | Out-Host }
    Stop-Transcript
}




