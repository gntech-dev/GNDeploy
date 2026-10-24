#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]param(
    [Parameter(Mandatory)][int]$DiskNumber,
    [Parameter(Mandatory)][string]$ExpectedSerial,
    [Parameter(Mandatory)][uint64]$ExpectedSize,
    [Parameter(Mandatory)][string]$ISO,
    [string]$WorkRoot="$env:LOCALAPPDATA\GNDeploy\USB",
    [string]$ExistingBackup,
    [ValidateSet('UEFI','Dual')][string]$BootMode='UEFI',
    [string[]]$AdditionalImages=@()
)
$ErrorActionPreference='Stop'
Import-Module "$PSHOME\Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1" -Force
New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null
$run=Join-Path $WorkRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
New-Item -ItemType Directory -Path $run -Force | Out-Null
Start-Transcript "$run\build.log"
$mountedISO=$null
function Status([string]$Stage){@{Stage=$Stage;Run=$run;Updated=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content "$WorkRoot\status.json"}
function Check-USB {
    $d=Get-Disk -Number $DiskNumber
    if($d.BusType -ne 'USB' -or $d.IsBoot -or $d.IsSystem -or $d.SerialNumber.Trim() -ne $ExpectedSerial.Trim() -or $d.Size -ne $ExpectedSize){throw 'La identidad del disco no coincide con la USB autorizada.'}
    return $d
}
function Assert-OutsideUSB([string]$Path){
    $full=(Resolve-Path -LiteralPath $Path).Path
    if($full -match '^([A-Za-z]):\\'){
        $letter=$Matches[1]
        if(Get-Partition | Where-Object {$_.DiskNumber -eq $DiskNumber -and [string]$_.DriveLetter -eq $letter}){throw 'Un archivo necesario esta guardado en la USB que se va a borrar.'}
    }
}
function Copy-Tree([string]$Source,[string]$Destination,[string[]]$Exclude=@()){
    $arguments=@($Source,$Destination,'/E','/COPY:DAT','/DCOPY:DAT','/R:1','/W:1','/XJ','/NP','/NFL','/NDL','/XD','System Volume Information','$RECYCLE.BIN')+$Exclude
    & robocopy.exe @arguments | Out-Host
    if($LASTEXITCODE -ge 8){throw "Robocopy fallo ($LASTEXITCODE): $Source"}
}
function Check-Tree([string]$Source,[string]$Destination,[string[]]$ExcludedTop=@()){
    foreach($file in Get-ChildItem -LiteralPath $Source -Recurse -File -Force -ErrorAction Stop){
        $relative=$file.FullName.Substring($Source.TrimEnd('\').Length).TrimStart('\')
        if(($relative.Split('\')[0]) -in (@('System Volume Information','$RECYCLE.BIN')+$ExcludedTop)){continue}
        $target=Join-Path $Destination $relative
        if(-not(Test-Path -LiteralPath $target)){throw "Falta $target"}
        if((Get-Item -LiteralPath $target).Length -ne $file.Length -or (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash){throw "Copia diferente: $target"}
    }
}
try{
    $disk=Check-USB
    foreach($requiredPath in @($ISO,$WorkRoot)+$AdditionalImages){Assert-OutsideUSB $requiredPath}
    if($ExistingBackup){Assert-OutsideUSB $ExistingBackup}
    $disk | Select-Object Number,FriendlyName,SerialNumber,UniqueId,Size,BusType | ConvertTo-Json | Set-Content "$run\device-before.json"
    $manifest=Get-Content "$ISO.manifest.json" -Raw | ConvertFrom-Json
    if($manifest.Interface -ne 'Windows Forms' -or $manifest.AutomaticValidation -or $ISO -match 'validation'){throw 'Solo se admite el medio interactivo, nunca una ISO automatica de laboratorio.'}
    Status 'VerifyingSourceISO'
    if((Get-FileHash -LiteralPath $ISO -Algorithm SHA256).Hash -ne $manifest.Sha256){throw 'Hash de la ISO incorrecto.'}
    $partitions=@(Get-Partition | Where-Object DiskNumber -eq $DiskNumber)
    $backupRoot="$run\PreviousUSB"
    if($ExistingBackup){
        $resolvedBackup=(Resolve-Path -LiteralPath $ExistingBackup).Path
        $allowedRoot=(Resolve-Path -LiteralPath $WorkRoot).Path.TrimEnd('\')+'\'
        if(-not $resolvedBackup.StartsWith($allowedRoot,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolvedBackup -Leaf) -ne 'PreviousUSB'){throw 'La copia previa debe estar dentro del historial de este creador.'}
        $backupRoot=$resolvedBackup
        Status 'ReusingPreviouslyVerifiedBackup'
    }else{
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    Status 'BackingUpExistingUSB'
    foreach($part in $partitions | Where-Object DriveLetter){
        $source="$($part.DriveLetter):\"
        $backup="$run\PreviousUSB\Partition-$($part.PartitionNumber)"
        Copy-Tree $source $backup
        Status 'VerifyingPreviousUSBBackup'
        # Enumerate only accessible installer content; omit Windows-managed directories.
        foreach($item in Get-ChildItem $source -Force | Where-Object Name -notin @('System Volume Information','$RECYCLE.BIN')){
            if($item.PSIsContainer){Check-Tree $item.FullName (Join-Path $backup $item.Name)}else{
                if((Get-FileHash $item.FullName).Hash -ne (Get-FileHash (Join-Path $backup $item.Name)).Hash){throw 'La copia previa no coincide.'}
            }
        }
    }
    }
    Status 'MountingSourceISO'
    $mountedISO=Mount-DiskImage -ImagePath $ISO -PassThru
    $isoVolume=$mountedISO | Get-Volume
    $media="$($isoVolume.DriveLetter):\"
    if(-not(Test-Path "$media\efi\boot\bootx64.efi") -or -not(Test-Path "$media\sources\boot.wim") -or -not(Test-Path "$media\GNDeploy")){throw 'ISO sin estructura GNDeploy UEFI.'}
    foreach($file in Get-ChildItem $media -Recurse -File | Where-Object {$_.FullName.Substring($media.Length) -notlike 'GNDeploy\*'}){if($file.Length -ge 4GB){throw 'El arranque contiene un archivo incompatible con FAT32.'}}
    $used=@(Get-Volume | Where-Object DriveLetter | ForEach-Object {[string]$_.DriveLetter})+@(Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Name)
    $letters=@(70..90 | ForEach-Object {[string][char]$_} | Where-Object {$_ -notin $used})
    if($letters.Count -lt 2){throw 'Faltan letras libres.'}
    $bootLetter=$letters[0];$dataLetter=$letters[1]
    $bootsect="${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\BCDBoot\bootsect.exe"
    if($BootMode -eq 'Dual' -and -not(Test-Path -LiteralPath $bootsect)){throw 'Falta bootsect para preparar BIOS.'}
    foreach($imagePath in $AdditionalImages){if(-not(Test-Path -LiteralPath $imagePath -PathType Leaf) -or [IO.Path]::GetExtension($imagePath) -notin @('.wim','.esd')){throw 'Imagen adicional no valida.'}}
    $disk=Check-USB
    if(-not $PSCmdlet.ShouldProcess("USB $DiskNumber $($disk.FriendlyName), serial $ExpectedSerial",'Reemplazar particiones despues de verificar copia previa')){return}
    Status 'PartitioningUSB'
    $disk | Clear-Disk -RemoveData -RemoveOEM -Confirm:$false
    $disk=Get-Disk -Number $DiskNumber
    $style=if($BootMode -eq 'Dual'){'MBR'}else{'GPT'}
    if(@(Get-Partition | Where-Object DiskNumber -eq $DiskNumber).Count){throw 'El disco no quedo vacio despues del borrado.'}
    if($disk.PartitionStyle -eq 'RAW'){$disk | Initialize-Disk -PartitionStyle $style | Out-Null}
    elseif([string]$disk.PartitionStyle -ne $style){
        $null=Check-USB
        [IO.File]::WriteAllText("$run\convert.txt","select disk $DiskNumber`r`nconvert $($style.ToLowerInvariant())`r`nexit`r`n",[Text.Encoding]::ASCII)
        & diskpart.exe /s "$run\convert.txt" | Tee-Object "$run\convert.log" | Out-Host
        if($LASTEXITCODE){throw 'No se pudo convertir la tabla de la USB.'}
    }
    if([string](Get-Disk -Number $DiskNumber).PartitionStyle -ne $style){throw 'Tabla de particiones inesperada.'}
    if($BootMode -eq 'Dual'){$boot=New-Partition -DiskNumber $DiskNumber -Size 4GB -MbrType FAT32 -IsActive -DriveLetter $bootLetter}
    else{$boot=New-Partition -DiskNumber $DiskNumber -Size 4GB -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -DriveLetter $bootLetter}
    $boot | Format-Volume -FileSystem FAT32 -NewFileSystemLabel GNBOOT -Confirm:$false | Out-Null
    $data=New-Partition -DiskNumber $DiskNumber -UseMaximumSize -DriveLetter $dataLetter
    $data | Format-Volume -FileSystem NTFS -NewFileSystemLabel GNDATA -Confirm:$false | Out-Null
    $bootRoot="${bootLetter}:\";$dataRoot="${dataLetter}:\"
    $null=Check-USB
    foreach($letter in @($bootLetter,$dataLetter)){
        $mapping=@(Get-Partition | Where-Object {[string]$_.DriveLetter -eq $letter})
        if($mapping.Count -ne 1 -or $mapping[0].DiskNumber -ne $DiskNumber){throw 'La letra de una particion USB cambio.'}
    }
    Status 'CopyingBoot'
    Copy-Tree $media $bootRoot @('GNDeploy')
    Status 'CopyingCatalogsDriversAndImages'
    Copy-Tree "$media\GNDeploy" "$dataRoot\GNDeploy"
    foreach($folder in @('Images','Drivers\Offline','Drivers\Boot','Autopilot\Profiles','Cache','Logs','Tools')){New-Item -ItemType Directory -Path "$dataRoot\GNDeploy\$folder" -Force | Out-Null}
    if($BootMode -eq 'Dual'){
        $null=Check-USB
        & $bootsect /nt60 "${bootLetter}:" /mbr | Tee-Object "$run\bootsect.log" | Out-Host
        if($LASTEXITCODE){throw 'Fallo al preparar el arranque BIOS.'}
    }
    foreach($imagePath in $AdditionalImages){
        $name=Split-Path $imagePath -Leaf;$target=Join-Path "$dataRoot\GNDeploy\Images" $name
        Status ("CopyingImage: "+$name)
        Copy-Item -LiteralPath $imagePath -Destination $target -Force
        Status ("VerifyingImage: "+$name)
        if((Get-FileHash -LiteralPath $imagePath).Hash -ne (Get-FileHash -LiteralPath $target).Hash){throw 'Imagen adicional no coincide.'}
    }
    $originalImages=@(Get-ChildItem -LiteralPath $backupRoot -Directory -Force | ForEach-Object {
        $candidate=Join-Path $_.FullName 'sources\install.wim'
        if(Test-Path -LiteralPath $candidate){Get-Item -LiteralPath $candidate -Force}
    })
    foreach($file in $originalImages){Copy-Item -LiteralPath $file.FullName -Destination "$dataRoot\GNDeploy\Images\Windows-original-USB-$($file.Directory.Parent.Name).wim"}
    @'
GNDeploy USB de pruebas - x64 (consultar modo de arranque al final)

GNBOOT (FAT32): archivos de arranque. No copiar imagenes Windows aqui.
GNDATA (NTFS): archivos editables, admite WIM/ESD mayores de 4 GB.

GNDeploy\Images\                  Copiar WIM/ESD aqui, sin subcarpetas.
GNDeploy\Drivers\Offline\Modelo\  Drivers extraidos INF/SYS/CAT para el Windows instalado.
GNDeploy\Autopilot\Profiles\      JSON Autopilot clasico, uno por perfil.
GNDeploy\Cache\                   Descargas y cache.
GNDeploy\Logs\                    Seleccionar esta carpeta para los logs.
GNDeploy\Drivers\Boot\            Zona de preparacion: copiar aqui NO inyecta drivers en WinRE.
GNDeploy\Tools\                   Herramientas portables x64; actualizar lista en Herramientas.

Las listas se cargan al abrir el menu. Para archivos agregados despues, use Abrir WIM/ESD,
Abrir JSON o el selector de carpeta de drivers.
Windows > seleccionar imagen > Leer imagen > elegir indice > Usar edicion.
Drivers > seleccionar pack > comprobar/usar carpeta.
Autopilot > seleccionar JSON > Usar perfil seleccionado.
Desplegar > revisar disco y plan > confirmacion explicita de borrado.

Los drivers necesarios para red/almacenamiento durante WinRE deben integrarse en boot.wim.
La imagen de arranque incluye los drivers WLAN preparados para Lenovo X1 Nano Gen 1;
su funcionamiento fisico aun requiere prueba. No hay perfiles de tenant de ejemplo activos.
'@ | Set-Content "$dataRoot\LEEME-GNDeploy.txt" -Encoding UTF8
    @"

Modo de este medio: $BootMode / tabla $style.
Windows 11: arrancar UEFI; destino GPT.
Windows 7 x64: UEFI/GPT con firmware compatible y Secure Boot desactivado; arranque fisico pendiente de validar. No admite Autopilot.
BIOS/MBR para Windows 7 queda disponible si se crea un medio Dual.
T420: pack Lenovo-T420-Win7-x64-Network incluye solo red Intel, no todos los drivers.
"@ | Add-Content "$dataRoot\LEEME-GNDeploy.txt" -Encoding UTF8
    Status 'VerifyingUSBReadback'
    foreach($item in Get-ChildItem $media -Force | Where-Object Name -ne 'GNDeploy'){
        if($item.PSIsContainer){Check-Tree $item.FullName (Join-Path $bootRoot $item.Name)}else{if((Get-FileHash $item.FullName).Hash -ne (Get-FileHash (Join-Path $bootRoot $item.Name)).Hash){throw 'Boot copiado incorrectamente.'}}
    }
    Check-Tree "$media\GNDeploy" "$dataRoot\GNDeploy"
    foreach($file in $originalImages){$target="$dataRoot\GNDeploy\Images\Windows-original-USB-$($file.Directory.Parent.Name).wim";if((Get-FileHash $file.FullName).Hash -ne (Get-FileHash $target).Hash){throw 'El WIM original copiado no coincide.'}}
    $imageInfo=@(Get-ChildItem "$dataRoot\GNDeploy\Images" -File | Where-Object Extension -in @('.wim','.esd') | ForEach-Object {[pscustomobject]@{File=$_.Name;Bytes=$_.Length;SHA256=(Get-FileHash $_.FullName).Hash;Editions=@(Get-WindowsImage -ImagePath $_.FullName | Select-Object ImageIndex,ImageName)}})
    $result=@{Status='Created-ReadbackVerified';UEFI=$true;BIOS=($BootMode -eq 'Dual');PartitionStyle=$style;Serial=$ExpectedSerial;DiskNumber=$DiskNumber;Boot=$bootRoot;Data=$dataRoot;ISO=$ISO;SourceSHA256=$manifest.Sha256;Backup=$backupRoot;Images=$imageInfo;Created=(Get-Date).ToString('o')}
    $result | ConvertTo-Json -Depth 8 | Set-Content "$dataRoot\GNDeploy\usb-manifest.json" -Encoding UTF8
    $result | ConvertTo-Json -Depth 8 | Set-Content "$run\result.json" -Encoding UTF8
    Status 'Completed'
}catch{$_ | Out-String | Set-Content "$run\error.txt";Status 'Failed';throw}finally{
    if($mountedISO){Dismount-DiskImage -ImagePath $ISO -ErrorAction Continue}
    Stop-Transcript
}


