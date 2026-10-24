#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]param(
    [Parameter(Mandatory)][string]$ISO,
    [Parameter(Mandatory)][string]$ExpectedSerial,
    [Parameter(Mandatory)][long]$ExpectedSize,
    [string]$WorkRoot="$env:USERPROFILE\GNDeploy\USB"
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1')
function Identify {
    $disks=@(Get-Disk | Where-Object {$_.BusType -eq 'USB' -and $_.SerialNumber.Trim() -eq $ExpectedSerial -and $_.Size -eq $ExpectedSize -and -not $_.IsBoot -and -not $_.IsSystem})
    if($disks.Count -ne 1){throw 'No se identifico la USB autorizada.'}
    $disks[0]
}
$manifest=Get-Content -LiteralPath "$ISO.manifest.json" -Raw | ConvertFrom-Json
if($manifest.Status -ne 'BootTested-HyperV' -or $manifest.AutomaticValidation -or (Get-FileHash -LiteralPath $ISO).Hash -ne $manifest.Sha256){throw 'ISO no validada para actualizar USB.'}
$disk=Identify
foreach($path in @($ISO,$WorkRoot)){
    $drive=[IO.Path]::GetPathRoot([IO.Path]::GetFullPath($path)).TrimEnd('\').TrimEnd(':')
    $part=Get-Partition -DriveLetter $drive -ErrorAction Stop
    if($part.DiskNumber -eq $disk.Number){throw 'La ISO y los respaldos deben quedar fuera de la USB.'}
}
$parts=@(Get-Partition -DiskNumber $disk.Number)
$boot=@($parts | Where-Object {$_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -and $_.DriveLetter})
$data=@($parts | Where-Object {$_.DriveLetter -and (Test-Path "$($_.DriveLetter):\GNDeploy\usb-manifest.json")})
if($boot.Count -ne 1 -or $data.Count -ne 1){throw 'No se encontraron las particiones GNDeploy esperadas.'}
$bootRoot="$($boot[0].DriveLetter):\";$dataRoot="$($data[0].DriveLetter):\"
$previous=Get-Content "$dataRoot\GNDeploy\usb-manifest.json" -Raw | ConvertFrom-Json
if($previous.Serial -ne $ExpectedSerial){throw 'El manifiesto de la USB no coincide.'}
$run=Join-Path $WorkRoot ('Update-'+(Get-Date -Format yyyyMMdd-HHmmss))
New-Item -ItemType Directory -Path $run | Out-Null
$mounted=$false
try{
    Copy-Item -LiteralPath "$bootRoot\sources\boot.wim" -Destination "$run\boot-before.wim"
    if((Get-FileHash "$bootRoot\sources\boot.wim").Hash -ne (Get-FileHash "$run\boot-before.wim").Hash){throw 'El respaldo de arranque no coincide.'}
    Copy-Item "$dataRoot\GNDeploy\usb-manifest.json" "$run\usb-manifest-before.json"
    $image=Mount-DiskImage -ImagePath $ISO -PassThru;$mounted=$true
    $volume=@($image | Get-Volume | Where-Object DriveLetter)[0];$source="$($volume.DriveLetter):\"
    $needed=64MB
    foreach($file in Get-ChildItem "$source\GNDeploy\Images" -File | Where-Object Extension -in @('.wim','.esd')){if(-not(Test-Path (Join-Path "$dataRoot\GNDeploy\Images" $file.Name))){$needed+=$file.Length}}
    $dataDrive=New-Object IO.DriveInfo $dataRoot;$bootDrive=New-Object IO.DriveInfo $bootRoot
    if($dataDrive.AvailableFreeSpace -lt $needed -or $bootDrive.AvailableFreeSpace -lt (Get-Item "$source\sources\boot.wim").Length){throw 'No hay espacio suficiente para actualizar la USB; no se reemplazo el arranque.'}
    $null=Identify
    Copy-Item "$source\sources\boot.wim" "$bootRoot\sources\boot.wim.new"
    $bootHash=(Get-FileHash "$source\sources\boot.wim").Hash
    if((Get-FileHash "$bootRoot\sources\boot.wim.new").Hash -ne $bootHash){throw 'La nueva copia de arranque no coincide.'}
    Move-Item -LiteralPath "$bootRoot\sources\boot.wim.new" -Destination "$bootRoot\sources\boot.wim" -Force
    if((Get-FileHash "$bootRoot\sources\boot.wim").Hash -ne $bootHash){throw 'Verificacion final de arranque incorrecta.'}
    foreach($file in Get-ChildItem "$source\GNDeploy\Catalogs" -File){
        $target=Join-Path "$dataRoot\GNDeploy\Catalogs" $file.Name
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
        if((Get-FileHash $file.FullName).Hash -ne (Get-FileHash $target).Hash){throw "Catalogo no coincide: $($file.Name)"}
    }
    foreach($pack in Get-ChildItem "$source\GNDeploy\Drivers\Offline" -Directory){
        $metadata=Join-Path $pack.FullName 'GNDeploy-pack.json';$target=Join-Path "$dataRoot\GNDeploy\Drivers\Offline" $pack.Name
        if((Test-Path -LiteralPath $metadata) -and (Test-Path -LiteralPath $target)){
            Copy-Item -LiteralPath $metadata -Destination (Join-Path $target 'GNDeploy-pack.json') -Force
            if((Get-FileHash $metadata).Hash -ne (Get-FileHash (Join-Path $target 'GNDeploy-pack.json')).Hash){throw 'Metadatos de drivers no coinciden.'}
        }
    }
    $newImages=@()
    foreach($file in Get-ChildItem "$source\GNDeploy\Images" -File | Where-Object Extension -in @('.wim','.esd')){
        $target=Join-Path "$dataRoot\GNDeploy\Images" $file.Name
        if(Test-Path -LiteralPath $target){continue}
        Copy-Item -LiteralPath $file.FullName -Destination "$target.new"
        $hash=(Get-FileHash -LiteralPath $file.FullName).Hash
        if((Get-FileHash -LiteralPath "$target.new").Hash -ne $hash){throw 'La nueva imagen no coincide.'}
        Move-Item -LiteralPath "$target.new" -Destination $target
        $newImages+=[pscustomobject]@{File=$file.Name;SHA256=$hash;Bytes=$file.Length}
    }
    $guide=Join-Path (Split-Path $PSScriptRoot) 'docs\T420-UEFI.md'
    Copy-Item -LiteralPath $guide -Destination "$dataRoot\GUIA-T420-UEFI.md" -Force
    if((Get-FileHash $guide).Hash -ne (Get-FileHash "$dataRoot\GUIA-T420-UEFI.md").Hash){throw 'La guia T420 no coincide.'}
    $guide=Join-Path (Split-Path $PSScriptRoot) 'docs\GUIA-USO.md'
    Copy-Item -LiteralPath $guide -Destination "$dataRoot\GUIA-GNDEPLOY.md" -Force
    if((Get-FileHash $guide).Hash -ne (Get-FileHash "$dataRoot\GUIA-GNDEPLOY.md").Hash){throw 'La guia GNDeploy no coincide.'}
    $update=[ordered]@{Status='Updated-ReadbackVerified';Serial=$ExpectedSerial;ISO=$ISO;SourceSHA256=$manifest.Sha256;BootWimSHA256=$bootHash;Backup=$run;Data=$dataRoot;Boot=$bootRoot;Preserved='Existing Images, Drivers, Autopilot, Cache, Logs, Tools; existing images not rehashed';NewImages=$newImages;Created=(Get-Date).ToString('o')}
    $update | ConvertTo-Json | Set-Content "$run\result.json" -Encoding UTF8
    $update | ConvertTo-Json | Set-Content "$dataRoot\GNDeploy\runtime-update.json" -Encoding UTF8
    $update | ConvertTo-Json | Set-Content "$WorkRoot\runtime-update-ready.json" -Encoding UTF8
}catch{$_ | Out-String | Set-Content "$run\error.txt";throw}finally{if($mounted){Dismount-DiskImage -ImagePath $ISO}}
