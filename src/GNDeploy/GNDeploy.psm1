Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop

function Assert-GNAdministrator {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Se requieren privilegios de administrador.' }
}

function Invoke-GNNative {
    param([string]$File,[string[]]$Arguments,[int[]]$SuccessCodes=@(0))
    & $File @Arguments | Out-Host
    if ($LASTEXITCODE -notin $SuccessCodes) { throw "$File fallo con codigo $LASTEXITCODE" }
}

function Write-GNDiskpartScript {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Commands)
    # DiskPart scripts must not depend on the line endings of the Git checkout.
    $windowsText=($Commands -replace '\r?\n',"`r`n").TrimEnd([char[]]"`r`n")+"`r`n"
    [IO.File]::WriteAllText($Path,$windowsText,[Text.Encoding]::ASCII)
}

function Read-GNXml {
    param([string]$Path)
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create((Resolve-Path -LiteralPath $Path).Path,$settings)
    try { $doc = New-Object System.Xml.XmlDocument; $doc.XmlResolver=$null; $doc.Load($reader); return ,$doc } finally { $reader.Dispose() }
}

function Get-GNInventory {
    [CmdletBinding()]param()
    $system = Get-CimInstance Win32_ComputerSystem
    $product = Get-CimInstance Win32_ComputerSystemProduct
    $bios = Get-CimInstance Win32_BIOS
    [pscustomobject]@{
        Manufacturer=[string]$system.Manufacturer; Model=[string]$system.Model
        ProductName=[string]$product.Version; SKU=[string]$system.SystemSKUNumber
        BoardProduct=[string](Get-CimInstance Win32_BaseBoard | Select-Object -First 1 -ExpandProperty Product)
        Serial=[string]$bios.SerialNumber; UUID=[string]$product.UUID
        Architecture=[string]$env:PROCESSOR_ARCHITECTURE; MemoryGB=[math]::Round($system.TotalPhysicalMemory/1GB,1)
        Devices=@(Get-CimInstance Win32_PnPEntity | Select-Object Name,PNPDeviceID,ConfigManagerErrorCode)
    }
}

function Get-GNTargetDisk {
    [CmdletBinding()]param([int[]]$ExcludeDiskNumber=@())
    Get-Disk | Where-Object {
        $_.BusType -notin @('USB','SD','MMC','File Backed Virtual') -and
        -not $_.IsBoot -and -not $_.IsSystem -and -not $_.IsOffline -and -not $_.IsReadOnly -and
        $_.Number -notin $ExcludeDiskNumber -and $_.Size -ge 32GB
    } | Select-Object Number,FriendlyName,SerialNumber,UniqueId,Size,BusType,PartitionStyle
}

function Assert-GNDownloadRange {
    param([string]$Headers,[long]$Start,[long]$End,[long]$Total)
    $ranges=[regex]::Matches($Headers,'(?im)^Content-Range:\s*bytes\s+(\d+)-(\d+)/(\d+)\s*$')
    if($ranges.Count -eq 0){throw 'El servidor no confirmo el rango descargado. Se conserva el progreso anterior.'}
    $range=$ranges[$ranges.Count-1]
    if([long]$range.Groups[1].Value -ne $Start -or [long]$range.Groups[2].Value -ne $End -or [long]$range.Groups[3].Value -ne $Total){throw 'El servidor devolvio un rango distinto al solicitado. No se agrego al archivo parcial.'}
}
function Save-GNDownload {
    [CmdletBinding()]param(
        [Parameter(Mandatory)][uri]$Uri,[Parameter(Mandatory)][string]$Destination,
        [ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$Sha256,
        [ValidatePattern('^[A-Fa-f0-9]{40}$')][string]$Sha1,
        [long]$ExpectedSize=0,
        [switch]$AllowMicrosoftHttp
    )
    $legacyHttp=$AllowMicrosoftHttp -and $Uri.Scheme -eq 'http' -and $Uri.Host -eq 'dl.delivery.mp.microsoft.com' -and ($Sha256 -or $Sha1) -and $ExpectedSize -gt 0
    if ($Uri.Scheme -ne 'https' -and -not $legacyHttp) { throw 'Se requiere HTTPS; HTTP legado solo se permite para Microsoft con hash y tamano del catalogo.' }
    $full = [IO.Path]::GetFullPath($Destination)
    New-Item -ItemType Directory -Force -Path (Split-Path $full) | Out-Null
    if (Test-Path -LiteralPath $full) {
        $hashMatches=($Sha256 -and (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash -eq $Sha256) -or ($Sha1 -and -not $Sha256 -and (Get-FileHash -LiteralPath $full -Algorithm SHA1).Hash -eq $Sha1)
        if ($hashMatches -and ($ExpectedSize -eq 0 -or (Get-Item -LiteralPath $full).Length -eq $ExpectedSize)) { return $full }
        throw "El destino ya existe y no se ha validado. Use otro destino o retire el archivo: $full"
    }
    $partial = "$full.partial"
    if($ExpectedSize -gt 0){
        $drive=New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($full))
        $already=0L;if(Test-Path -LiteralPath $partial){$already=(Get-Item -LiteralPath $partial).Length}
        if($drive.DriveFormat -eq 'FAT32' -and $ExpectedSize -ge 4GB){throw 'La imagen supera el limite FAT32. Elija la particion de datos NTFS de la USB.'}
        if($drive.AvailableFreeSpace -lt ([math]::Max(0L,[long]($ExpectedSize-$already))+128MB)){throw 'No hay espacio suficiente en la carpeta cache para completar la descarga.'}
    }
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        $protocols='=https'; if ($legacyHttp) {$protocols='=http,https'}
        $common=@('--silent','--show-error','--fail','--location','--proto',$protocols,'--proto-redir',$protocols,'--retry','3','--connect-timeout','30','--speed-limit','1024','--speed-time','60')
        if ($ExpectedSize -gt 512MB) {
            # Bounded HTTP ranges also work with the legacy Microsoft delivery endpoint.
            # Append only complete chunks; interrupted chunks are retried without duplicating data.
            $offset=0L
            if (Test-Path -LiteralPath $partial) {$offset=(Get-Item -LiteralPath $partial).Length}
            if ($offset -gt $ExpectedSize) {throw 'El parcial es mayor que el archivo esperado.'}
            $initialOffset=$offset;$watch=[Diagnostics.Stopwatch]::StartNew()
            while ($offset -lt $ExpectedSize) {
                $length=[math]::Min([long]64MB,[long]($ExpectedSize-$offset))
                $end=$offset+$length-1
                $chunk="$partial.range"
                $argsList=$common+@('--range',"$offset-$end",'--max-filesize',[string]$length,'--dump-header',"$chunk.headers",'--output',$chunk,$Uri.AbsoluteUri)
                Invoke-GNNative $curl.Source $argsList
                $headers=Get-Content -LiteralPath "$chunk.headers" -Raw
                Assert-GNDownloadRange -Headers $headers -Start $offset -End $end -Total $ExpectedSize
                if ((Get-Item -LiteralPath $chunk).Length -ne $length) {throw 'Respuesta Range incompleta; no se agrego al archivo parcial.'}
                $inputStream=[IO.File]::OpenRead($chunk)
                $outputStream=[IO.File]::Open($partial,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::Read)
                try {$inputStream.CopyTo($outputStream)} finally {$inputStream.Dispose();$outputStream.Dispose()}
                Remove-Item -LiteralPath $chunk -Force
                Remove-Item -LiteralPath "$chunk.headers" -Force
                $offset+=$length
                $speed=($offset-$initialOffset)/[math]::Max(0.1,$watch.Elapsed.TotalSeconds)
                $remaining=[TimeSpan]::FromSeconds(($ExpectedSize-$offset)/[math]::Max(1,$speed))
                Write-Progress -Activity 'Descargando contenido' -Status ('{0:N0}/{1:N0} MB | {2:N1} MB/s | aprox. {3:N0} min' -f ($offset/1MB),($ExpectedSize/1MB),($speed/1MB),$remaining.TotalMinutes) -PercentComplete ($offset*100/$ExpectedSize)
            }
            Write-Progress -Activity 'Descargando contenido' -Completed
        } else {
            $argsList=$common+@('--output',$partial)
            if (Test-Path -LiteralPath $partial) { $argsList += @('--continue-at','-') }
            $argsList += $Uri.AbsoluteUri
            Invoke-GNNative $curl.Source $argsList
        }
    } else {
        # WebRequest fallback restarts a partial transfer; it never treats it as complete.
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $partial
    }
    if ($ExpectedSize -gt 0 -and (Get-Item -LiteralPath $partial).Length -ne $ExpectedSize) { throw 'El tamano de la descarga no coincide.' }
    if ($Sha256 -and (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash -ne $Sha256) {
        Remove-Item -LiteralPath $partial -Force
        throw 'SHA256 incorrecto. Descarga descartada.'
    }
    if ($Sha1 -and (Get-FileHash -LiteralPath $partial -Algorithm SHA1).Hash -ne $Sha1) {
        Remove-Item -LiteralPath $partial -Force
        throw 'SHA1 no coincide con el catalogo Microsoft.'
    }
    Move-Item -LiteralPath $partial -Destination $full
    return $full
}

function Get-GNWindowsCatalog {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$Path,[string]$Language='es-es',[string]$Architecture='x64')
    if([IO.Path]::GetExtension($Path) -eq '.json'){
        $catalog=Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        foreach($record in $catalog.Media){
            if($record.Language -ne $Language -or $record.Architecture -ne $Architecture){continue}
            if($record.Acquisition -notin @('EvaluationISO','LicensedMedia','Unavailable')){throw 'Tipo de adquisicion no admitido.'}
            if($record.Acquisition -eq 'EvaluationISO'){
                $uri=[uri]$record.Uri
                if($uri.Scheme -ne 'https' -or $uri.Host -notmatch '(^|\.)microsoft\.com$' -or $record.Sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or [IO.Path]::GetFileName($record.FileName) -ne $record.FileName){throw 'Entrada ISO Microsoft no valida.'}
            }
            $record
        }
        return
    }
    $catalog = Read-GNXml $Path
    foreach ($node in @($catalog.SelectNodes('//PublishedMedia/Files/File'))) {
        if ([string]$node.LanguageCode -ne $Language -or [string]$node.Architecture -ne $Architecture) { continue }
        $uriText = [string]$node.FilePath
        # Microsoft MCT metadata can contain HTTP links. Require the corresponding HTTPS endpoint.
        $uriText = $uriText -replace '^http://','https://'
        $uri = [uri]$uriText
        if ($uri.Scheme -ne 'https' -or $uri.Host -notmatch '(^|\.)(microsoft\.com|windowsupdate\.com)$') { throw "Origen Microsoft no permitido: $($uri.Host)" }
        $sha256Node=$node.SelectSingleNode('Sha256'); $sha1Node=$node.SelectSingleNode('Sha1')
        $hash='';$legacyHash=''
        if ($sha256Node) { $hash=$sha256Node.InnerText }
        if ($sha1Node) { $legacyHash=$sha1Node.InnerText }
        if ($hash -notmatch '^[a-fA-F0-9]{64}$' -and $legacyHash -notmatch '^[a-fA-F0-9]{40}$') { continue }
        $family='Windows';$buildNumber=0
        if([int]::TryParse(([string]$node.FileName).Split('.')[0],[ref]$buildNumber)){$family=if($buildNumber -lt 22000){'Windows 10'}else{'Windows 11'}}
        [pscustomobject]@{FileName=[string]$node.FileName;Language=[string]$node.LanguageCode;Edition=[string]$node.Edition;Family=$family;Acquisition='DirectESD';Architecture=[string]$node.Architecture;Uri=$uri.AbsoluteUri;Sha256=$hash;Sha1=$legacyHash;Size=[long]$node.Size}
    }
}

function Get-GNImage {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$Path)
    Get-WindowsImage -ImagePath (Resolve-Path -LiteralPath $Path).Path | ForEach-Object {
        $detail = Get-WindowsImage -ImagePath $Path -Index $_.ImageIndex
        [pscustomobject]@{Index=$detail.ImageIndex;Name=$detail.ImageName;Edition=$detail.EditionId;Architecture=$detail.Architecture;Version=[string]$detail.Version;Size=$detail.ImageSize}
    }
}

function Get-GNAutopilotProfile {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$Path)
    $profile = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $properties = @($profile.PSObject.Properties.Name)
    foreach ($name in @('CloudAssignedTenantId','CloudAssignedTenantDomain','CloudAssignedOobeConfig','CloudAssignedDomainJoinMethod')) {
        if ($name -notin $properties) { throw "Perfil Autopilot incompleto: $name" }
    }
    $tenantId = [guid]::Empty
    if (-not [guid]::TryParse([string]$profile.CloudAssignedTenantId,[ref]$tenantId) -or $tenantId -eq [guid]::Empty) { throw 'Tenant ID no valido.' }
    if ([string]$profile.CloudAssignedTenantDomain -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$') { throw 'Dominio de tenant no valido.' }
    if ($profile.CloudAssignedDomainJoinMethod -notin @(0,1)) { throw 'DomainJoinMethod no valido.' }
    $oobe = 0
    if (-not [int]::TryParse([string]$profile.CloudAssignedOobeConfig,[ref]$oobe) -or $oobe -lt 0) { throw 'OobeConfig no valido.' }
    [pscustomobject]@{Name=[IO.Path]::GetFileNameWithoutExtension($Path);Path=(Resolve-Path -LiteralPath $Path).Path;TenantId=[string]$tenantId;TenantDomain=[string]$profile.CloudAssignedTenantDomain;Sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash;Profile=$profile}
}

function Set-GNAutopilotProfile {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$ProfilePath,[Parameter(Mandatory)][string]$WindowsRoot)
    $profile = Get-GNAutopilotProfile $ProfilePath
    if (-not (Test-Path -LiteralPath (Join-Path $WindowsRoot 'Windows\System32'))) { throw 'No hay una instalacion Windows en el destino.' }
    $folder = Join-Path $WindowsRoot 'Windows\Provisioning\Autopilot'
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    # Escape non-ASCII characters instead of replacing them when serializing to ASCII.
    $json = $profile.Profile | ConvertTo-Json -Depth 64
    $ascii = [regex]::Replace($json,'[^\x00-\x7F]',{param($m) '\u{0:x4}' -f [int][char]$m.Value})
    $destination = Join-Path $folder 'AutopilotConfigurationFile.json'
    [IO.File]::WriteAllText($destination,$ascii,[Text.Encoding]::ASCII)
    $verified = Get-GNAutopilotProfile $destination
    if ($verified.TenantId -ne $profile.TenantId -or $verified.TenantDomain -ne $profile.TenantDomain) { throw 'Verificacion de perfil Autopilot fallo.' }
    return $verified
}

function Get-GNLenovoDriverPack {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$CatalogPath,[Parameter(Mandatory)][string]$MachineType,[string]$Release)
    if ($MachineType -notmatch '^[a-zA-Z0-9]{4}$') { throw 'MachineType debe tener cuatro caracteres, por ejemplo 20UN.' }
    $doc = Read-GNXml $CatalogPath
    foreach ($model in @($doc.SelectNodes('/ModelList/Model'))) {
        if ($MachineType -notin @($model.SelectNodes('Types/Type') | ForEach-Object {$_.InnerText})) { continue }
        foreach ($pack in @($model.SelectNodes('SCCM[@os="win11"]'))) {
            if ($Release -and [string]$pack.version -ne $Release -and [string]$pack.version -ne '*') { continue }
            $hash = [string]$pack.crc
            if ($hash -notmatch '^[a-fA-F0-9]{64}$') { throw 'El catalogo Lenovo no contiene SHA256 valido en crc.' }
            $uri = [uri]$pack.InnerText
            if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'download.lenovo.com') { throw 'Origen de driver Lenovo no valido.' }
            [pscustomobject]@{Model=[string]$model.name;MachineType=$MachineType;Release=[string]$pack.version;Date=[datetime]$pack.date;Uri=$uri.AbsoluteUri;Sha256=$hash;FileName=[IO.Path]::GetFileName($uri.AbsolutePath)}
        }
    }
}

function Save-GNLenovoDriverPack {
    [CmdletBinding()]param([Parameter(Mandatory)]$Pack,[Parameter(Mandatory)][string]$CacheRoot,[Parameter(Mandatory)][string]$Extractor)
    $archive = Save-GNDownload -Uri $Pack.Uri -Destination (Join-Path $CacheRoot $Pack.FileName) -Sha256 $Pack.Sha256
    $out = Join-Path $CacheRoot $Pack.Sha256
    $marker = Join-Path $out '.gndeploy-complete'
    if (-not (Test-Path -LiteralPath $marker)) {
        New-Item -ItemType Directory -Force -Path $out | Out-Null
        # innoextract is a data extractor; the downloaded OEM EXE is never executed.
        Invoke-GNNative $Extractor @('--silent','--extract','--output-dir',$out,$archive)
        if (@(Get-ChildItem -LiteralPath $out -Recurse -Filter *.inf).Count -eq 0) { throw 'El pack no produjo drivers INF.' }
        Set-Content -LiteralPath $marker -Value $Pack.Sha256 -Encoding ASCII
    }
    return $out
}

function Get-GNNetworkStatus {
    [CmdletBinding()]param([uri]$ProbeUri='https://www.microsoft.com')
    $addresses = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' | ForEach-Object {$_.IPAddress} | Where-Object {$_ -notmatch '^(169\.254\.|127\.|fe80:|::1$)'})
    $reachable = $false
    try { $null = Invoke-WebRequest -UseBasicParsing -Method Head -Uri $ProbeUri -TimeoutSec 15; $reachable=$true } catch { }
    [pscustomobject]@{Addresses=$addresses;HttpsReachable=$reachable;Probe=$ProbeUri.AbsoluteUri}
}

function Connect-GNWifi {
    [CmdletBinding(DefaultParameterSetName='Personal')]
    param(
        [Parameter(Mandatory,ParameterSetName='Personal')][Parameter(Mandatory,ParameterSetName='Open')][ValidateLength(1,32)][string]$SSID,
        [Parameter(Mandatory,ParameterSetName='Personal')][securestring]$Password,
        [Parameter(Mandatory,ParameterSetName='Open')][switch]$Open,
        [Parameter(ParameterSetName='Personal')][ValidateSet('WPA2PSK','WPA3SAE')][string]$Authentication='WPA2PSK',
        [string]$InterfaceName,
        [Parameter(Mandatory,ParameterSetName='Profile')][string]$ProfilePath,
        [Parameter(ParameterSetName='Profile')][string]$ProfileName
    )
    if (-not (Get-Service WlanSvc -ErrorAction SilentlyContinue)) { throw 'Este boot no incluye WLAN. Use la variante WinRE Wi-Fi y su driver.' }
    Start-Service WlanSvc
    $temporary = $null
    try {
        if ($PSCmdlet.ParameterSetName -in @('Personal','Open')) {
            $keyXml='';$cipher='none';$auth='open'
            if(-not $Open){
            $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
            try { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
            if ($plain.Length -lt 8 -or $plain.Length -gt 63) { throw 'WPA2 Personal requiere entre 8 y 63 caracteres.' }
            $escapedSsid = [Security.SecurityElement]::Escape($SSID)
            $escapedKey = [Security.SecurityElement]::Escape($plain)
            $keyXml="<sharedKey><keyType>passPhrase</keyType><protected>false</protected><keyMaterial>$escapedKey</keyMaterial></sharedKey>"
            $cipher='AES';$auth=$Authentication
            }
            $escapedSsid = [Security.SecurityElement]::Escape($SSID)
            $xml = @"
<?xml version="1.0"?><WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1"><name>$escapedSsid</name><SSIDConfig><SSID><name>$escapedSsid</name></SSID></SSIDConfig><connectionType>ESS</connectionType><connectionMode>auto</connectionMode><MSM><security><authEncryption><authentication>$auth</authentication><encryption>$cipher</encryption><useOneX>false</useOneX></authEncryption>$keyXml</security></MSM></WLANProfile>
"@
            $temporary = Join-Path $env:TEMP ("gndeploy-wifi-{0}.xml" -f [guid]::NewGuid())
            [IO.File]::WriteAllText($temporary,$xml,[Text.Encoding]::UTF8)
            $ProfilePath=$temporary; $ProfileName=$SSID
            $plain=$null; $escapedKey=$null; $xml=$null;$keyXml=$null
        } else {
            $doc = Read-GNXml $ProfilePath
            $ProfileName = $doc.DocumentElement.SelectSingleNode('*[local-name()="name"]').InnerText
        }
        Invoke-GNNative netsh.exe @('wlan','add','profile',"filename=$ProfilePath",'user=all')
        $connectArgs=@('wlan','connect',"name=$ProfileName")
        if($InterfaceName){$connectArgs+= "interface=$InterfaceName"}
        Invoke-GNNative netsh.exe $connectArgs
        for ($i=0;$i -lt 12;$i++) {
            Start-Sleep -Seconds 2
            $status = Get-GNNetworkStatus
            if ($status.HttpsReachable) { return $status }
        }
        throw 'La conexion no obtuvo acceso HTTPS. Revise DHCP, DNS, proxy y fecha del equipo.'
    } finally { if ($temporary -and (Test-Path -LiteralPath $temporary)) { Remove-Item -LiteralPath $temporary -Force } }
}

function Get-GNPathDiskNumber {
    param([string]$Path)
    $resolved = [IO.Path]::GetFullPath($Path)
    if ($resolved -match '^([a-zA-Z]):\\') {
        $driveLetter=$Matches[1]
        # Enumerating avoids a terminating CIM "not found" query for RAM/CD-ROM drives.
        $partition = @(Get-Partition -ErrorAction Stop | Where-Object {
            [string]$_.DriveLetter -eq $driveLetter -or @($_.AccessPaths) -contains "${driveLetter}:\"
        })
        if($partition.Count -gt 1){throw "La ruta $Path corresponde a mas de una particion."}
        if ($partition) { return [int]$partition.DiskNumber }
    }
}

function Wait-GNDeploymentPartitions {
    [CmdletBinding()]param([int]$DiskNumber,[object[]]$Assignments,[int]$Attempts=15,[int]$DelayMilliseconds=1000)
    $last=''
    for($attempt=0;$attempt -lt $Attempts;$attempt++){
        if(Get-Command Update-HostStorageCache -ErrorAction SilentlyContinue){Update-HostStorageCache -ErrorAction Stop}
        $partitions=@(Get-Partition -ErrorAction Stop)
        $complete=$true
        foreach($expected in $Assignments){
            $root="$($expected.Letter):\"
            $mapped=@($partitions | Where-Object {[string]$_.DriveLetter -eq $expected.Letter -or @($_.AccessPaths) -contains $root})
            if($mapped.Count -eq 0){
                $native=Get-GNVolumeExtent -Letter $expected.Letter
                if($native){$mapped=@($partitions | Where-Object {$_.DiskNumber -eq $native.DiskNumber -and $_.Offset -eq $native.Offset})}
            }
            if($mapped.Count -gt 1 -or ($mapped.Count -eq 1 -and ($mapped[0].DiskNumber -ne $DiskNumber -or $mapped[0].PartitionNumber -ne $expected.Number))){
                throw "La letra $($expected.Letter): no corresponde a la particion $($expected.Number) del disco $DiskNumber. Se detuvo el despliegue."
            }
            if($mapped.Count -eq 0){$complete=$false;$last="No aparece $root para la particion $($expected.Number).";continue}
            if($expected.ContainsKey('MbrType')){
                if([int]$mapped[0].MbrType -ne [int]$expected.MbrType -or ($expected.Active -and -not $mapped[0].IsActive)){throw "Tipo MBR o particion activa inesperados para $root."}
            }elseif(([string]$mapped[0].GptType).Trim('{}') -ine $expected.Type){throw "Tipo GPT inesperado para $root. Se detuvo el despliegue."}
            if(-not(Test-Path -LiteralPath $root)){$complete=$false;$last="La particion $root aun no es accesible."}
        }
        if($complete){return}
        if($attempt -lt $Attempts-1 -and $DelayMilliseconds -gt 0){Start-Sleep -Milliseconds $DelayMilliseconds}
    }
    throw "No se pudo validar el particionado tras actualizar el inventario. $last Consulte diskpart.log y partitions-after.json. No se aplico Windows."
}

function Get-GNVolumeExtent {
    param([ValidatePattern('^[A-Za-z]$')][string]$Letter)
    if(-not('GNDeployNativeVolume' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class GNDeployNativeVolume {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool DeviceIoControl(SafeFileHandle handle, uint code, IntPtr input, uint inputSize, byte[] output, uint outputSize, out uint returned, IntPtr overlapped);
    public static long[] GetExtent(string letter) {
        using(var handle=CreateFile(@"\\.\"+letter+":",0,3,IntPtr.Zero,3,0,IntPtr.Zero)) {
            if(handle.IsInvalid) { int error=Marshal.GetLastWin32Error(); if(error==2 || error==3 || error==21) return null; throw new Win32Exception(error); }
            byte[] buffer=new byte[1024]; uint returned;
            if(!DeviceIoControl(handle,0x00560000,IntPtr.Zero,0,buffer,(uint)buffer.Length,out returned,IntPtr.Zero)) {
                int error=Marshal.GetLastWin32Error(); if(error==1 || error==50 || error==21) return null; throw new Win32Exception(error);
            }
            if(returned<32 || BitConverter.ToUInt32(buffer,0)!=1) throw new InvalidOperationException("El volumen no tiene una unica extension de disco.");
            return new long[]{BitConverter.ToUInt32(buffer,8),BitConverter.ToInt64(buffer,16),BitConverter.ToInt64(buffer,24)};
        }
    }
}
'@
    }
    $extent=[GNDeployNativeVolume]::GetExtent($Letter)
    if($extent){[pscustomobject]@{DiskNumber=[int]$extent[0];Offset=[long]$extent[1];Size=[long]$extent[2]}}
}

function New-GNDeploymentPlan {
    [CmdletBinding()]param(
        [Parameter(Mandatory)][int]$DiskNumber,[Parameter(Mandatory)][string]$ImagePath,
        [Parameter(Mandatory)][ValidateRange(1,100)][int]$ImageIndex,
        [string]$AutopilotProfile,[string]$DriverPath,
        [Parameter(Mandatory)][string]$LogRoot,
        [ValidateSet('UEFI','BIOS')][string]$FirmwareMode='UEFI'
    )
    $image = (Resolve-Path -LiteralPath $ImagePath).Path
    $excluded = @()
    foreach ($path in @($image,$LogRoot,$PSScriptRoot,$AutopilotProfile,$DriverPath)) {
        if ($path) { $number = Get-GNPathDiskNumber $path; if ($null -ne $number) { $excluded += $number } }
    }
    $disk = @(Get-GNTargetDisk -ExcludeDiskNumber $excluded | Where-Object Number -eq $DiskNumber)
    if ($disk.Count -ne 1) { throw 'Disco destino no permitido o contiene archivos necesarios para el despliegue.' }
    if ([string]::IsNullOrWhiteSpace([string]$disk[0].UniqueId)) { throw 'El disco no tiene UniqueId; no es seguro identificarlo.' }
    $detail = Get-WindowsImage -ImagePath $image -Index $ImageIndex
    if ([int]$detail.Architecture -ne 9) { throw 'Esta version solo despliega imagenes Windows amd64.' }
    $legacy=([string]$detail.Version -match '^6\.1\.' -and $detail.ImageName -match 'Windows 7')
    $modern=([version]$detail.Version).Major -eq 10 -and $detail.ImageName -match 'Windows (10|11)\b'
    if ((-not $modern -and -not $legacy) -or [string]$detail.EditionId -match 'WindowsPE|WindowsSetup' -or $detail.ImageName -match 'Windows (PE|Setup)') { throw 'Seleccione una imagen instalable Windows 7, 10 u 11 x64.' }
    if(-not $legacy -and $FirmwareMode -ne 'UEFI'){throw 'Windows 10 y 11 usan el flujo UEFI/GPT en esta version.'}
    $minimum=if($modern -and ([version]$detail.Version).Build -ge 22000){64GB}else{32GB}
    if($disk[0].Size -lt $minimum){throw "La imagen requiere un disco de al menos $($minimum/1GB) GB."}
    if($legacy -and $AutopilotProfile){throw 'Windows 7 no admite Autopilot.'}
    if($AutopilotProfile -and [string]$detail.EditionId -match '^Core'){throw 'Windows Home no admite Autopilot. Seleccione una edicion compatible o Sin Autopilot.'}
    if($legacy -and $FirmwareMode -eq 'BIOS' -and $disk[0].Size -gt 2TB){throw 'El flujo BIOS/MBR admite discos de hasta 2 TB.'}
    $notes=''
    if($legacy -and $FirmwareMode -eq 'UEFI'){
        $notes='Windows 7 UEFI: requiere firmware compatible y Secure Boot desactivado.'
        if(Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT'){Assert-GNWindows7UefiFirmware}
    }
    if ($detail.ImageSize -gt ($disk[0].Size - 4GB)) { throw 'Disco demasiado pequeno para la imagen.' }
    $profile = $null
    if ($AutopilotProfile) { $profile = Get-GNAutopilotProfile $AutopilotProfile }
    $drivers = $null
    if ($DriverPath) {
        $drivers = (Resolve-Path -LiteralPath $DriverPath).Path
        if (@(Get-ChildItem -LiteralPath $drivers -Filter *.inf -Recurse).Count -eq 0) { throw 'La carpeta de drivers no contiene INF.' }
        $compatibility=Get-GNDriverCompatibility -Path $drivers -ImageVersion ([string]$detail.Version)
        if($compatibility.Status -eq 'No compatible'){throw $compatibility.Detail}
    }
    [pscustomobject]@{
        SchemaVersion=1;Id=[guid]::NewGuid().ToString();Created=(Get-Date).ToString('o');FirmwareMode=$FirmwareMode;ImageVersion=[string]$detail.Version;CompatibilityNotes=$notes
        DiskNumber=$DiskNumber;DiskUniqueId=[string]$disk[0].UniqueId;DiskSize=[long]$disk[0].Size;DiskName=$disk[0].FriendlyName
        ImagePath=$image;ImageIndex=$ImageIndex;ImageName=$detail.ImageName;ImageSha256=(Get-FileHash -LiteralPath $image -Algorithm SHA256).Hash
        AutopilotProfile=$profile;DriverPath=$drivers;LogRoot=[IO.Path]::GetFullPath($LogRoot)
    }
}

function Invoke-GNDeployment {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)][string]$Confirmation)
    if (-not (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')) { throw 'El despliegue destructivo solo se permite dentro de WinPE/WinRE.' }
    Assert-GNAdministrator
    if ($Confirmation -cne "BORRAR $($Plan.DiskNumber)") { throw 'Confirmacion incorrecta.' }
    if ($Plan.SchemaVersion -ne 1) { throw 'Version de plan no compatible.' }
    # Rebuild all validations using current devices and files immediately before destruction.
    $profilePath=$null
    if ($Plan.AutopilotProfile) { $profilePath=$Plan.AutopilotProfile.Path }
    $mode='UEFI';if($Plan.PSObject.Properties['FirmwareMode']){$mode=$Plan.FirmwareMode}
    $fresh = New-GNDeploymentPlan -DiskNumber $Plan.DiskNumber -ImagePath $Plan.ImagePath -ImageIndex $Plan.ImageIndex -AutopilotProfile $profilePath -DriverPath $Plan.DriverPath -LogRoot $Plan.LogRoot -FirmwareMode $mode
    if ($fresh.DiskUniqueId -ne $Plan.DiskUniqueId -or $fresh.DiskSize -ne $Plan.DiskSize -or $fresh.ImageSha256 -ne $Plan.ImageSha256) { throw 'El disco o la imagen cambiaron despues de crear el plan.' }
    if ($Plan.AutopilotProfile -and $fresh.AutopilotProfile.Sha256 -ne $Plan.AutopilotProfile.Sha256) { throw 'El perfil Autopilot cambio.' }
    Invoke-GNNative wpeutil.exe @('UpdateBootInfo')
    if($mode -eq 'BIOS'){
        if((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control').PEFirmwareType -ne 1){throw 'El plan BIOS requiere arrancar en modo BIOS.'}
        if(-not $PSCmdlet.ShouldProcess("Disco $($Plan.DiskNumber): $($Plan.DiskName)",'BORRAR y desplegar Windows 7 BIOS/MBR')){return}
        return Invoke-GNLegacyDeployment -Plan $fresh
    }
    if ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control').PEFirmwareType -ne 2) { throw 'Se requiere arranque UEFI.' }
    $windows7=$fresh.ImageVersion -match '^6\.1\.'
    if($windows7){Assert-GNWindows7UefiFirmware}
    $occupied=@(Get-Partition -ErrorAction Stop | ForEach-Object {
        if($_.DriveLetter){[string]$_.DriveLetter}
        foreach($path in @($_.AccessPaths)){if($path -match '^([A-Za-z]):\\$'){$Matches[1]}}
    }) + @(Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Name) + @(Get-CimInstance Win32_LogicalDisk | ForEach-Object {$_.DeviceID.TrimEnd(':')})
    $letters = @('W','S','R','T','U','V','Y','Z') | Where-Object {$_ -notin $occupied -and -not(Test-Path "${_}:\")}
    if ($letters.Count -lt 3) { throw 'No hay letras disponibles para las particiones.' }
    $osLetter=$letters[0]; $efiLetter=$letters[1]; $reLetter=$letters[2]
    if (-not $PSCmdlet.ShouldProcess("Disco $($Plan.DiskNumber): $($Plan.DiskName), UniqueId $($Plan.DiskUniqueId)",'BORRAR y desplegar Windows')) { return }
    $runRoot = Join-Path $Plan.LogRoot $Plan.Id
    New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
    $Plan | ConvertTo-Json -Depth 64 | Set-Content (Join-Path $runRoot 'plan.json') -Encoding UTF8
    $result = [ordered]@{Id=$Plan.Id;State='Running';Step='Partition';Started=(Get-Date).ToString('o');Finished=$null;Error=$null}
    $journal = Join-Path $runRoot 'result.json'
    $result | ConvertTo-Json | Set-Content $journal -Encoding UTF8
    Start-Transcript -Path (Join-Path $runRoot 'deployment.log')
    try {
        $diskpartFile = Join-Path $runRoot 'diskpart.txt'
        $layout=Get-GNUefiDeploymentLayout -DiskNumber $Plan.DiskNumber -OSLetter $osLetter -SystemLetter $efiLetter -RecoveryLetter $reLetter -Windows7:$windows7
        $diskpartText=$layout.Commands
        Write-GNDiskpartScript -Path $diskpartFile -Commands $diskpartText
        $lastCheck=Get-Disk -Number $Plan.DiskNumber
        if ($lastCheck.UniqueId -ne $Plan.DiskUniqueId -or $lastCheck.Size -ne $Plan.DiskSize -or $lastCheck.IsBoot -or $lastCheck.IsSystem -or $lastCheck.IsOffline -or $lastCheck.IsReadOnly -or $lastCheck.BusType -in @('USB','SD','MMC')) {throw 'El disco cambio o dejo de ser un destino permitido antes del borrado.'}
        & diskpart.exe /s $diskpartFile 2>&1 | Tee-Object -FilePath "$runRoot\diskpart.log" | Out-Host
        if($LASTEXITCODE -ne 0){throw "DiskPart fallo: $LASTEXITCODE. Consulte $runRoot\diskpart.log"}
        Get-Partition -ErrorAction Stop | Select-Object DiskNumber,PartitionNumber,DriveLetter,AccessPaths,GptType,Size | ConvertTo-Json -Depth 5 | Set-Content "$runRoot\partitions-after.json" -Encoding UTF8
        Wait-GNDeploymentPartitions -DiskNumber $Plan.DiskNumber -Assignments $layout.Assignments
        $result.Step='ApplyImage'; $result | ConvertTo-Json | Set-Content $journal -Encoding UTF8
        $scratch="${osLetter}:\GNDeployScratch"
        New-Item -ItemType Directory -Path $scratch -Force | Out-Null
        Invoke-GNNative dism.exe @('/Apply-Image',"/ImageFile:$($Plan.ImagePath)","/Index:$($Plan.ImageIndex)","/ApplyDir:${osLetter}:\",'/CheckIntegrity',"/ScratchDir:$scratch", "/LogPath:$runRoot\dism-apply.log")
        if ($Plan.DriverPath) {
            $result.Step='Drivers'; $result | ConvertTo-Json | Set-Content $journal -Encoding UTF8
            Invoke-GNNative dism.exe @("/Image:${osLetter}:\",'/Add-Driver',"/Driver:$($Plan.DriverPath)",'/Recurse',"/ScratchDir:$scratch", "/LogPath:$runRoot\dism-drivers.log")
        }
        if ($profilePath) {
            $result.Step='Autopilot'; $result | ConvertTo-Json | Set-Content $journal -Encoding UTF8
            $null = Set-GNAutopilotProfile -ProfilePath $profilePath -WindowsRoot "${osLetter}:\"
        }
        $result.Step='Boot'; $result | ConvertTo-Json | Set-Content $journal -Encoding UTF8
        Invoke-GNNative bcdboot.exe @("${osLetter}:\Windows",'/s',"${efiLetter}:",'/f','UEFI')
        if($windows7){
            if(-not(Test-Path "${efiLetter}:\EFI\Microsoft\Boot\bootmgfw.efi") -or -not(Test-Path "${efiLetter}:\EFI\Microsoft\Boot\BCD")){throw 'Faltan archivos de arranque UEFI.'}
            New-Item -ItemType Directory -Path "${efiLetter}:\EFI\Boot" -Force | Out-Null
            Copy-Item -LiteralPath "${efiLetter}:\EFI\Microsoft\Boot\bootmgfw.efi" -Destination "${efiLetter}:\EFI\Boot\bootx64.efi" -Force
        }else{
        $winre = "${osLetter}:\Windows\System32\Recovery\winre.wim"
        if (-not (Test-Path -LiteralPath $winre)) { throw 'La imagen no contiene WinRE; revise el resultado antes de reiniciar.' }
        New-Item -ItemType Directory -Force -Path "${reLetter}:\Recovery\WindowsRE" | Out-Null
        Copy-Item -LiteralPath $winre -Destination "${reLetter}:\Recovery\WindowsRE\winre.wim"
        Invoke-GNNative "${osLetter}:\Windows\System32\reagentc.exe" @('/setreimage','/path',"${reLetter}:\Recovery\WindowsRE",'/target',"${osLetter}:\Windows")
        }
        $result.State='Succeeded'; $result.Step='ReadyForOOBE'
    } catch {
        $result.State='Failed'; $result.Error=$_.Exception.Message
        throw
    } finally {
        $result.Finished=(Get-Date).ToString('o')
        $result | ConvertTo-Json | Set-Content $journal -Encoding UTF8
        Stop-Transcript
        if (Test-Path "${osLetter}:\Windows") {
            $dest="${osLetter}:\ProgramData\GNDeploy\Logs\$($Plan.Id)"
            New-Item -ItemType Directory -Force -Path $dest | Out-Null
            Copy-Item -Path "$runRoot\*" -Destination $dest -Recurse -Force
        }
    }
    [pscustomobject]$result
}

function Export-GNDiagnostics {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$Destination)
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Get-GNInventory | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $Destination 'inventory.json') -Encoding UTF8
    Get-Disk | Select-Object Number,FriendlyName,SerialNumber,UniqueId,Size,BusType,IsBoot,IsSystem | ConvertTo-Json | Set-Content (Join-Path $Destination 'disks.json') -Encoding UTF8
    & ipconfig.exe /all | Out-File (Join-Path $Destination 'network.txt')
    & netsh.exe wlan show drivers | Out-File (Join-Path $Destination 'wlan-drivers.txt')
    & netsh.exe wlan show interfaces | Out-File (Join-Path $Destination 'wlan-interfaces.txt')
    return $Destination
}

. (Join-Path $PSScriptRoot 'Oem.ps1')
. (Join-Path $PSScriptRoot 'Readiness.ps1')
. (Join-Path $PSScriptRoot 'Wifi.ps1')
. (Join-Path $PSScriptRoot 'Legacy.ps1')
. (Join-Path $PSScriptRoot 'Uefi.ps1')
. (Join-Path $PSScriptRoot 'Utilities.ps1')
. (Join-Path $PSScriptRoot 'Distribution.ps1')

