#Requires -Version 5.1
[CmdletBinding()]param([switch]$Console)
$ErrorActionPreference='Stop'
$env:PSModulePath="$PSScriptRoot\Modules;$env:PSModulePath"
$curl=Join-Path $PSScriptRoot 'Tools\curl.exe'
if (Test-Path -LiteralPath $curl) {
    $null = & $curl --version 2>$null
    if ($LASTEXITCODE -eq 0) { $env:PATH="$PSScriptRoot\Tools;$env:PATH" }
}
Import-Module "$PSScriptRoot\Modules\GNDeploy\GNDeploy.psd1" -Force
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
try {
    foreach($command in @('Get-Disk','Get-Partition','Get-WindowsImage','Get-CimInstance','Invoke-GNDeployment')) {Get-Command $command -ErrorAction Stop | Out-Null}
    $system=Get-CimInstance Win32_ComputerSystem
    @{State='Ready';Version='0.1.0';Manufacturer=$system.Manufacturer;Model=$system.Model;Time=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content "$PSScriptRoot\boot-status.json" -Encoding UTF8
} catch {
    $_ | Out-String | Set-Content "$PSScriptRoot\boot-error.txt"
    throw
}
if(-not $Console){
    do{
        try{& "$PSScriptRoot\Start-GNDeployGui.ps1"}catch{
            $_ | Out-String | Set-Content "$PSScriptRoot\gui-error.txt"
            Start-Process "$env:SystemRoot\System32\cmd.exe" -ArgumentList '/k title GNDeploy - Error de interfaz - revisar X:\GNDeploy\gui-error.txt' -WindowStyle Normal -Wait
        }
    }while(Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')
    return
}
function Select-ItemFromList([object[]]$Items,[string]$Label) {
    if ($Items.Count -eq 0) { throw "No hay elementos: $Label" }
    for ($i=0;$i -lt $Items.Count;$i++) { Write-Host "[$($i+1)] $($Items[$i] | Out-String)" }
    $number=0
    if (-not [int]::TryParse((Read-Host $Label),[ref]$number) -or $number -lt 1 -or $number -gt $Items.Count) { throw 'Seleccion no valida.' }
    return $Items[$number-1]
}
function Get-MediaRoots {
    @(Get-PSDrive -PSProvider FileSystem | Where-Object {Test-Path (Join-Path $_.Root 'GNDeploy')} | ForEach-Object {Join-Path $_.Root 'GNDeploy'})
}
$imagePath=$null; $driverPath=$null; $profilePath=$null
while ($true) {
    Write-Host "`nGNDeploy 0.1 - Laboratorio Windows 11" -ForegroundColor Cyan
    Write-Host '1 Inventario / red    2 Conectar Wi-Fi    3 Descargar Windows'
    Write-Host '4 Seleccionar WIM/ESD  5 Drivers OEM/locales    6 Perfil Autopilot'
    Write-Host '7 Plan y despliegue   8 Exportar diagnostico    0 Consola'
    Write-Host "Imagen: $imagePath | Drivers: $driverPath | Autopilot: $profilePath"
    try {
        switch (Read-Host 'Opcion') {
            '1' { Get-GNInventory | Select-Object Manufacturer,Model,ProductName,Serial,MemoryGB | Format-List; Get-GNNetworkStatus | Format-List; Get-Disk | Format-Table Number,FriendlyName,Size,BusType }
            '2' {
                Start-Service WlanSvc -ErrorAction Stop
                & netsh.exe wlan show networks
                $ssid=Read-Host 'SSID (WPA2 Personal)'
                $password=Read-Host 'Contrasena' -AsSecureString
                Connect-GNWifi -SSID $ssid -Password $password | Format-List
                $password=$null
            }
            '3' {
                $catalogs=@(Get-MediaRoots | ForEach-Object {Get-ChildItem -Path "$_\Catalogs\*.xml" -ErrorAction SilentlyContinue})
                $catalog=Select-ItemFromList $catalogs 'Catalogo Microsoft'
                $language=Read-Host 'Idioma (es-es / es-mx / en-us)'
                $record=Select-ItemFromList @(Get-GNWindowsCatalog -Path $catalog.FullName -Language $language) 'Medio Windows'
                $cache=Read-Host 'Carpeta cache en USB o segundo disco (no disco destino)'
                if([string]::IsNullOrWhiteSpace($cache)){throw 'Seleccione una carpeta cache antes de descargar.'}
                $download=@{Uri=$record.Uri;Destination=(Join-Path $cache $record.FileName);ExpectedSize=$record.Size}
                if ($record.Sha256) {$download.Sha256=$record.Sha256} else {$download.Sha1=$record.Sha1;Write-Host 'Este catalogo historico solo proporciona SHA1. Se verifica junto con HTTPS y tamano.'}
                try {$imagePath=Save-GNDownload @download} catch {
                    if(([uri]$record.Uri).Host -ne 'dl.delivery.mp.microsoft.com'){throw}
                    Write-Host 'HTTPS no completo la descarga de este medio historico Microsoft.'
                    if((Read-Host 'Usar su enlace HTTP original verificando hash y tamano del catalogo? SI para continuar') -cne 'SI'){throw}
                    $download.Uri=$record.Uri -replace '^https:','http:'
                    $download.AllowMicrosoftHttp=$true
                    $imagePath=Save-GNDownload @download
                }
            }
            '4' {
                $available=@(Get-MediaRoots | ForEach-Object {Get-ChildItem -Path "$_\Images\*" -Include *.wim,*.esd -ErrorAction SilentlyContinue})
                $candidate=Read-Host 'Ruta completa a WIM/ESD (Enter para listar medios incluidos)'
                if (-not $candidate) { $candidate=(Select-ItemFromList $available 'Imagen incluida').FullName }
                Get-GNImage $candidate | Format-Table; $imagePath=(Resolve-Path -LiteralPath $candidate).Path
            }
            '5' {
                $localDrivers=Read-Host 'Carpeta INF local (Enter para detectar Lenovo y descargar)'
                if ($localDrivers) {
                    if (@(Get-ChildItem -LiteralPath $localDrivers -Filter *.inf -Recurse).Count -eq 0) {throw 'No hay INF en la carpeta.'}
                    $driverPath=(Resolve-Path -LiteralPath $localDrivers).Path
                    break
                }
                $inventory=Get-GNInventory
                $cache=Read-Host 'Carpeta cache en USB o segundo disco'
                $release=Read-Host 'Release Windows destino (24H2 / 25H2)'
                $cat=Join-Path $cache ('oem-{0}.xml' -f (Get-Date -Format yyyyMMddHHmmss))
                if ($inventory.Manufacturer -match 'Lenovo') {
                    $type=$inventory.Model.Substring(0,4)
                    $null=Save-GNDownload -Uri 'https://download.lenovo.com/cdrt/td/catalogv2.xml' -Destination $cat
                    $packs=@(Get-GNLenovoDriverPack -CatalogPath $cat -MachineType $type -Release $release | Sort-Object Date -Descending)
                    $pack=Select-ItemFromList $packs 'Pack Lenovo'
                    $driverPath=Save-GNLenovoDriverPack -Pack $pack -CacheRoot $cache -Extractor "$PSScriptRoot\Tools\innoextract.exe"
                } elseif ($inventory.Manufacturer -match 'Dell|HP|Hewlett') {
                    $manufacturer='HP';$systemId=$inventory.BoardProduct;$uri='https://hpia.hpcloud.hp.com/downloads/driverpackcatalog/HPClientDriverPackCatalog.cab'
                    if($inventory.Manufacturer -match 'Dell'){$manufacturer='Dell';$systemId=$inventory.SKU;$uri='https://downloads.dell.com/catalog/DriverPackCatalog.cab'}
                    $null=Save-GNDownload -Uri $uri -Destination "$cat.cab"
                    & expand.exe "$cat.cab" $cat | Out-Host
                    if($LASTEXITCODE -ne 0){throw 'No se pudo extraer el catalogo OEM.'}
                    $packs=@(Get-GNOemDriverPack -Manufacturer $manufacturer -CatalogPath $cat -SystemId $systemId -Release $release | Sort-Object Date -Descending)
                    $pack=Select-ItemFromList $packs 'Pack OEM (Dell clasifica Windows 11 sin garantizar release especifica)'
                    $driverPath=Save-GNOemDriverPack -Pack $pack -CacheRoot $cache -Extractor "$PSScriptRoot\Tools\7z.exe"
                } else {throw 'Fabricante sin proveedor automatico. Seleccione una carpeta INF local.'}
            }
            '6' {
                $profiles=@(Get-MediaRoots | ForEach-Object {Get-ChildItem -Path "$_\Autopilot\Profiles\*.json" -ErrorAction SilentlyContinue})
                Write-Host '0 Sin perfil'
                $choice=Read-Host 'Enter para listar perfiles o 0 para quitar el perfil'
                if ($choice -eq '0') { $profilePath=$null } else {
                    $selected=Select-ItemFromList $profiles 'Perfil Autopilot'
                    $profile=Get-GNAutopilotProfile $selected.FullName
                    $profile | Select-Object Name,TenantDomain,TenantId | Format-List
                    $profilePath=$profile.Path
                }
            }
            '7' {
                if (-not $imagePath) { throw 'Seleccione o descargue una imagen primero.' }
                Get-GNTargetDisk | Format-Table Number,FriendlyName,Size,UniqueId
                $diskNumberText=Read-Host 'Numero de disco destino'
                $diskNumber=0
                if (-not [int]::TryParse($diskNumberText,[ref]$diskNumber)) { throw 'Numero de disco no valido.' }
                $image=Select-ItemFromList @(Get-GNImage $imagePath) 'Indice Windows'
                $logs=Read-Host 'Carpeta de logs en USB o segundo disco'
                if (-not $logs) {$logs='X:\GNDeploy\Logs';Write-Host 'Logs temporales en RAM; se copian al Windows instalado al finalizar.'}
                $plan=New-GNDeploymentPlan -DiskNumber $diskNumber -ImagePath $imagePath -ImageIndex $image.Index -DriverPath $driverPath -AutopilotProfile $profilePath -LogRoot $logs
                $plan | Select-Object DiskNumber,DiskName,DiskUniqueId,DiskSize,ImageName,@{n='Tenant';e={if ($_.AutopilotProfile) {$_.AutopilotProfile.TenantDomain}}} | Format-List
                $confirmation=Read-Host "Se perderan TODOS los datos de ese disco. Escriba BORRAR $diskNumber"
                $result=Invoke-GNDeployment -Plan $plan -Confirmation $confirmation -Confirm:$false
                $result | Format-List
                if ($result.State -eq 'Succeeded' -and (Read-Host 'Reiniciar a OOBE? Escriba SI') -ceq 'SI') { & wpeutil.exe reboot }
            }
            '8' { Export-GNDiagnostics -Destination (Read-Host 'Carpeta destino persistente') }
            '0' { return }
            default { Write-Host 'Opcion no valida.' }
        }
    } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
}
