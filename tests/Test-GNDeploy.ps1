#Requires -Version 5.1
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
Import-Module "$repo\src\GNDeploy\GNDeploy.psd1" -Force
$module=Get-Module GNDeploy
$testRoot=Join-Path $env:TEMP ('GNDeploy-Tests-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $testRoot | Out-Null
$script:passed=0
function Assert([bool]$Condition,[string]$Message) { if (-not $Condition) {throw $Message}; $script:passed++; Write-Host "PASS $Message" }
function Assert-Throws([scriptblock]$Action,[string]$Message) { $thrown=$false; try { & $Action | Out-Null } catch {$thrown=$true}; Assert $thrown $Message }
try {
    $parseErrors=@()
    Get-ChildItem "$repo\src","$repo\scripts","$repo\tests" -Recurse -Include *.ps1,*.psm1,*.psd1 | ForEach-Object {
        $tokens=$null;$errors=$null
        [Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors) | Out-Null
        $parseErrors+=@($errors)
    }
    Assert ($parseErrors.Count -eq 0) 'Todos los scripts tienen sintaxis valida'
    Assert ((Test-ModuleManifest "$repo\src\GNDeploy\GNDeploy.psd1").Version -eq [version]'0.2.1') 'Manifiesto importable'
    $shellIni=Get-Content "$repo\config\winpeshl.ini" -Raw
    Assert ($shellIni -match '\[LaunchApps\]' -and $shellIni -notmatch 'CommandLine\s*=') 'Winpeshl usa seccion que admite argumentos de inicio'
    Assert ($shellIni -match 'powershell\.exe,.*-STA.*-WindowStyle Hidden.*Start-GNDeploy\.ps1' -and $shellIni -notmatch 'cmd\.exe') 'Winpeshl inicia la interfaz directamente sin consola principal que se pueda cerrar'
    $startup=Get-Content "$repo\config\startnet.cmd" -Raw
    Assert ($startup -match 'SetKeyboardLayout 0409:00000409[\s\S]*powershell\.exe') 'Teclado English US se configura antes de iniciar la interfaz'
    Assert ($startup -match 'powershell\.exe[^\r\n]*-STA') 'Interfaz grafica inicia en un proceso STA'
    $scriptFile=Join-Path $testRoot 'diskpart.txt'
    & $module {param($path) Write-GNDiskpartScript -Path $path -Commands "select disk 2`nlist partition`nexit"} $scriptFile
    $diskpartBytes=[IO.File]::ReadAllBytes($scriptFile)
    $diskpartText=[Text.Encoding]::ASCII.GetString($diskpartBytes)
    Assert ($diskpartText -ceq "select disk 2`r`nlist partition`r`nexit`r`n") 'DiskPart recibe CRLF explicitos aunque el codigo fuente use LF'
    Assert ($diskpartBytes[0] -eq [byte][char]'s') 'Script DiskPart ASCII sin BOM'
    $profile=Join-Path $testRoot 'empresa.json'
    $domain='contoso.onmicrosoft.com'
    @{CloudAssignedTenantId='b2f386a2-fefe-4d02-9f00-a7b1bb2ec001';CloudAssignedTenantDomain=$domain;CloudAssignedOobeConfig=28;CloudAssignedDomainJoinMethod=0;Comment_File=('Espa'+[char]0xf1+'a')} | ConvertTo-Json | Set-Content $profile -Encoding UTF8
    $parsed=Get-GNAutopilotProfile $profile
    Assert ($parsed.TenantDomain -eq $domain) 'Lee el tenant del perfil'
    $offline=Join-Path $testRoot 'offline'
    New-Item -ItemType Directory -Path "$offline\Windows\System32" -Force | Out-Null
    $written=Set-GNAutopilotProfile -ProfilePath $profile -WindowsRoot $offline
    $bytes=[IO.File]::ReadAllBytes($written.Path)
    Assert (@($bytes | Where-Object {$_ -gt 127}).Count -eq 0) 'JSON destino ASCII sin BOM'
    Assert ($written.Profile.Comment_File -eq $parsed.Profile.Comment_File) 'Caracteres Unicode conservados mediante escapes'
    Assert ((Split-Path $written.Path -Leaf) -ceq 'AutopilotConfigurationFile.json') 'Nombre final exacto del perfil'
    Assert-Throws { Set-GNAutopilotProfile -ProfilePath $profile -WindowsRoot "$testRoot\missing" } 'No aplica perfil sobre un destino sin Windows'
    '{}' | Set-Content "$testRoot\bad.json"
    Assert-Throws { Get-GNAutopilotProfile "$testRoot\bad.json" } 'Rechaza perfil incompleto'
    $bad=$parsed.Profile; $bad.CloudAssignedTenantId='not-a-guid'; $bad | ConvertTo-Json | Set-Content "$testRoot\bad.json"
    Assert-Throws { Get-GNAutopilotProfile "$testRoot\bad.json" } 'Rechaza tenant invalido'
    $sha='a'*64
    @"
<ModelList><Model name="Nano"><Types><Type>20UN</Type><Type>20UQ</Type></Types><SCCM os="win11" version="24H2" date="2024-07-17" crc="$sha">https://download.lenovo.com/pack.exe</SCCM><SCCM os="win10" version="22H2" date="2024-01-01" crc="$sha">https://download.lenovo.com/old.exe</SCCM></Model></ModelList>
"@ | Set-Content "$testRoot\lenovo.xml"
    Assert (@(Get-GNLenovoDriverPack "$testRoot\lenovo.xml" 20UQ -Release 24H2).Count -eq 1) 'Coincidencia exacta por machine type y release'
    Assert (@(Get-GNLenovoDriverPack "$testRoot\lenovo.xml" 21AA).Count -eq 0) 'No adivina un modelo desconocido'
    Assert (@(Get-GNLenovoDriverPack "$testRoot\lenovo.xml" 20UN -Release 25H2).Count -eq 0) 'No selecciona silenciosamente pack de otra release'
    (Get-Content "$testRoot\lenovo.xml" -Raw).Replace('download.lenovo.com','evil.invalid') | Set-Content "$testRoot\evil.xml"
    Assert-Throws { Get-GNLenovoDriverPack "$testRoot\evil.xml" 20UN } 'Rechaza origen OEM no permitido'
    '<!DOCTYPE x [<!ENTITY secret SYSTEM "file:///c:/windows/win.ini">]><x>&secret;</x>' | Set-Content "$testRoot\xxe.xml"
    Assert-Throws { Get-GNWindowsCatalog "$testRoot\xxe.xml" } 'XML con entidades externas bloqueado'
    @"
<MCT><Catalogs><Catalog><PublishedMedia><Files><File><FileName>test.esd</FileName><LanguageCode>es-es</LanguageCode><Edition>Professional</Edition><Architecture>x64</Architecture><Size>123</Size><Sha256>$sha</Sha256><FilePath>http://dl.delivery.mp.microsoft.com/test.esd</FilePath></File></Files></PublishedMedia></Catalog></Catalogs></MCT>
"@ | Set-Content "$testRoot\windows.xml"
    $media=@(Get-GNWindowsCatalog "$testRoot\windows.xml")
    Assert ($media.Count -eq 1 -and $media[0].Uri -like 'https://*') 'Catalogo filtra idioma y obliga HTTPS'
    Assert-Throws { Save-GNDownload -Uri 'http://example.com/image.esd' -Destination "$testRoot\image.esd" } 'Descarga HTTP bloqueada antes de red'
    'cached' | Set-Content "$testRoot\cache.esd"
    $hash=(Get-FileHash "$testRoot\cache.esd").Hash
    $cached=Save-GNDownload -Uri 'https://example.invalid/file' -Destination "$testRoot\cache.esd" -Sha256 $hash
    Assert ((Test-Path -LiteralPath $cached -PathType Leaf) -and (Get-FileHash -LiteralPath $cached).Hash -eq $hash) 'Cache valida no necesita red'
    Assert-Throws { Save-GNDownload -Uri 'https://example.invalid/file' -Destination "$testRoot\cache.esd" -Sha256 ('b'*64) } 'Cache corrupta no se reutiliza'
    # Destructive entry point must refuse to execute on a normal Windows host.
    if (-not (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')) {
        Assert-Throws { Invoke-GNDeployment -Plan ([pscustomobject]@{}) -Confirmation 'BORRAR 0' -Confirm:$false } 'Despliegue bloqueado fuera de WinPE'
    }
    # Mock inventory only inside the module; no disk modification is invoked in these tests.
    & $module {
        function script:Get-Disk { @(
            [pscustomobject]@{Number=0;FriendlyName='Host';SerialNumber='h';UniqueId='host';Size=128GB;BusType='NVMe';IsBoot=$true;IsSystem=$true;IsOffline=$false;IsReadOnly=$false;PartitionStyle='GPT'},
            [pscustomobject]@{Number=1;FriendlyName='USB';SerialNumber='u';UniqueId='usb';Size=128GB;BusType='USB';IsBoot=$false;IsSystem=$false;IsOffline=$false;IsReadOnly=$false;PartitionStyle='GPT'},
            [pscustomobject]@{Number=2;FriendlyName='VM';SerialNumber='v';UniqueId='vm';Size=128GB;BusType='SCSI';IsBoot=$false;IsSystem=$false;IsOffline=$false;IsReadOnly=$false;PartitionStyle='RAW'}
        ) }
    }
    Assert (@(Get-GNTargetDisk).Count -eq 1 -and @(Get-GNTargetDisk)[0].Number -eq 2) 'Excluye host y USB, admite disco SCSI de VM'
    Assert (@(Get-GNTargetDisk -ExcludeDiskNumber 2).Count -eq 0) 'Excluye discos que contienen contenido de despliegue'
    & $module {
        function script:Get-Partition {param($DriveLetter) [pscustomobject]@{DiskNumber=0;DriveLetter='C';AccessPaths=@('C:\')}}
        function script:Get-WindowsImage {param($ImagePath,$Index) [pscustomobject]@{Architecture=9;ImageName='Windows 11 Pro';EditionId='Professional';ImageSize=20GB;Version=[version]'10.0.26100.4349'}}
    }
    $fakeImage=Join-Path $testRoot 'fake-image.wim'
    'test fixture, not a real image' | Set-Content $fakeImage
    $plan=New-GNDeploymentPlan -DiskNumber 2 -ImagePath $fakeImage -ImageIndex 1 -AutopilotProfile $profile -LogRoot "$testRoot\logs"
    Assert ($plan.DiskUniqueId -eq 'vm' -and $plan.AutopilotProfile.TenantDomain -eq $domain) 'Plan fija identidad de disco y tenant'
    Assert ($plan.ImageSha256 -eq (Get-FileHash $fakeImage).Hash) 'Plan fija hash de la imagen'
    Assert-Throws {New-GNDeploymentPlan -DiskNumber 0 -ImagePath $fakeImage -ImageIndex 1 -LogRoot "$testRoot\logs"} 'Plan rechaza disco del sistema'
    Assert-Throws {New-GNDeploymentPlan -DiskNumber 1 -ImagePath $fakeImage -ImageIndex 1 -LogRoot "$testRoot\logs"} 'Plan rechaza USB aunque se indique explicitamente'
    & $module {function script:Get-Partition {param($DriveLetter) [pscustomobject]@{DiskNumber=2;DriveLetter='C';AccessPaths=@('C:\')}}}
    Assert-Throws {New-GNDeploymentPlan -DiskNumber 2 -ImagePath $fakeImage -ImageIndex 1 -LogRoot "$testRoot\logs"} 'Plan rechaza borrar el disco que contiene la imagen/logs'
    & $module {
        function script:Get-Partition {param($DriveLetter) [pscustomobject]@{DiskNumber=0;DriveLetter='C';AccessPaths=@('C:\')}}
        function script:Get-WindowsImage {param($ImagePath,$Index) [pscustomobject]@{Architecture=12;ImageName='Windows 11 Pro';EditionId='Professional';ImageSize=20GB;Version=[version]'10.0.26100.4349'}}
    }
    Assert-Throws {New-GNDeploymentPlan -DiskNumber 2 -ImagePath $fakeImage -ImageIndex 1 -LogRoot "$testRoot\logs"} 'Plan rechaza imagen ARM64 en runtime amd64'
    @"
<DriverPackManifest xmlns="openmanage/cm/dm"><DriverPackage dateTime="2026-01-01" path="folder/pack.cab" size="123"><SupportedOperatingSystems><OperatingSystem osCode="Windows11" osArch="x64" /></SupportedOperatingSystems><SupportedSystems><Brand><Model systemID="08AF" name="XPS" /></Brand></SupportedSystems><Cryptography><Hash algorithm="SHA256">$sha</Hash></Cryptography></DriverPackage></DriverPackManifest>
"@ | Set-Content "$testRoot\dell.xml"
    $dell=@(Get-GNOemDriverPack -Manufacturer Dell -CatalogPath "$testRoot\dell.xml" -SystemId 08AF)
    Assert ($dell.Count -eq 1 -and $dell[0].Uri -eq 'https://downloads.dell.com/folder/pack.cab') 'Dell resuelve SystemID y hash SHA256'
    Assert (@(Get-GNOemDriverPack -Manufacturer Dell -CatalogPath "$testRoot\dell.xml" -SystemId FFFF).Count -eq 0) 'Dell no adivina modelo por nombre'
    @"
<NewDataSet><HPClientDriverPackCatalog><SoftPaqList><SoftPaq><Id>sp1</Id><Url>https://ftp.hp.com/pack.exe</Url><SHA256>$sha</SHA256><Size>123</Size><DateReleased>10/01/2026 12:00:00 AM</DateReleased></SoftPaq></SoftPaqList><ProductOSDriverPackList><ProductOSDriverPack><Architecture>64-bit</Architecture><SystemId>1234,ABCD</SystemId><SystemName>HP Test</SystemName><OSName>Windows 11 64-bit, 24H2</OSName><SoftPaqId>sp1</SoftPaqId></ProductOSDriverPack></ProductOSDriverPackList></HPClientDriverPackCatalog></NewDataSet>
"@ | Set-Content "$testRoot\hp.xml"
    $hp=@(Get-GNOemDriverPack -Manufacturer HP -CatalogPath "$testRoot\hp.xml" -SystemId ABCD -Release 24H2)
    Assert ($hp.Count -eq 1 -and $hp[0].Sha256 -eq $sha) 'HP resuelve SystemID compartido y SoftPaq'
    Assert (@(Get-GNOemDriverPack -Manufacturer HP -CatalogPath "$testRoot\hp.xml" -SystemId ABCD -Release 25H2).Count -eq 0) 'HP no sustituye una release distinta'
    Assert-Throws {Save-GNDownload -Uri 'http://dl.delivery.mp.microsoft.com/test' -Destination "$testRoot\legacy" -AllowMicrosoftHttp} 'HTTP Microsoft sin hash/tamano sigue bloqueado'
    Assert-Throws {Save-GNDownload -Uri 'http://evil.invalid/test' -Destination "$testRoot\legacy" -Sha256 $sha -ExpectedSize 123 -AllowMicrosoftHttp} 'Excepcion HTTP no se extiende a otros hosts'
    $partitionChecks=& $module {
        function script:Update-HostStorageCache {}
        function script:Test-Path {param($LiteralPath) $true}
        function script:Get-GNVolumeExtent {param($Letter) $null}
        $script:fixture=@(
            [pscustomobject]@{DiskNumber=2;PartitionNumber=1;Offset=1048576;DriveLetter=[char]0;AccessPaths=@('S:\');GptType='{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'},
            [pscustomobject]@{DiskNumber=2;PartitionNumber=3;Offset=300MB;DriveLetter='W';AccessPaths=@('W:\');GptType='{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'})
        $script:reads=0
        function script:Get-Partition {param($DriveLetter) if($DriveLetter){throw 'No usar consulta CIM por letra'};$script:reads++;if($script:reads -gt 1){$script:fixture}}
        $assign=@(@{Letter='S';Number=1;Type='c12a7328-f81f-11d2-ba4b-00a0c93ec93b'},@{Letter='W';Number=3;Type='ebd0a0a2-b9e5-4433-87c0-68b6b72699c7'})
        Wait-GNDeploymentPartitions -DiskNumber 2 -Assignments $assign -Attempts 2 -DelayMilliseconds 0
        $retry=$script:reads -eq 2
        $script:fixture[0].AccessPaths=@('\\?\Volume{11111111-1111-1111-1111-111111111111}\')
        function script:Get-GNVolumeExtent {param($Letter) if($Letter -eq 'S'){[pscustomobject]@{DiskNumber=2;Offset=1048576;Size=260MB}}}
        Wait-GNDeploymentPartitions -DiskNumber 2 -Assignments $assign -Attempts 1
        $native=$true
        $script:fixture[0].DiskNumber=9;$wrong=$false
        try{Wait-GNDeploymentPartitions -DiskNumber 2 -Assignments $assign -Attempts 1}catch{$wrong=$true}
        $script:fixture[0].DiskNumber=2;$script:fixture[0].GptType='unexpected';$type=$false
        try{Wait-GNDeploymentPartitions -DiskNumber 2 -Assignments $assign -Attempts 1}catch{$type=$true}
        $script:fixture=@();$missing=$false
        try{Wait-GNDeploymentPartitions -DiskNumber 2 -Assignments $assign -Attempts 2 -DelayMilliseconds 0}catch{$missing=$true}
        [pscustomobject]@{Retry=$retry;Native=$native;WrongDisk=$wrong;WrongType=$type;Missing=$missing}
    }
    Assert $partitionChecks.Retry 'Espera inventario actualizado y admite ESP con AccessPaths sin DriveLetter'
    Assert $partitionChecks.Native 'Resuelve ESP oculto por extension nativa cuando CIM solo publica el GUID del volumen'
    Assert $partitionChecks.WrongDisk 'Rechaza letra asignada a otro disco despues de DiskPart'
    Assert $partitionChecks.WrongType 'Rechaza particion con tipo GPT inesperado'
    Assert $partitionChecks.Missing 'No aplica Windows si falta alguna particion al terminar la espera'
    Write-Host "RESULTADO: $script:passed comprobaciones correctas; ningun disco fue modificado."
} finally {
    Remove-Module GNDeploy -Force
    # Delete only the unique test directory we created under TEMP, after verifying containment.
    $resolved=[IO.Path]::GetFullPath($testRoot)
    $parent=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
    if ($resolved.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'GNDeploy-Tests-*') { Remove-Item -LiteralPath $resolved -Recurse -Force }
}

