function Get-GNHardwareStatus {
    [CmdletBinding()]param()
    $i=Get-GNInventory
    $cpu=Get-CimInstance Win32_Processor | Select-Object -First 1
    $tpm=$null;try{$tpm=Get-CimInstance -Namespace root/cimv2/security/microsofttpm -ClassName Win32_Tpm -ErrorAction Stop}catch{}
    $secure=$null;try{$secure=[bool](Confirm-SecureBootUEFI -ErrorAction Stop)}catch{}
    $firmware='Desconocido';try{$value=Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name PEFirmwareType -ErrorAction Stop;$firmware=if($value -eq 2){'UEFI'}else{'BIOS'}}catch{if($null -ne $secure){$firmware='UEFI'}}
    [pscustomobject]@{Manufacturer=$i.Manufacturer;Model=$i.Model;ProductName=$i.ProductName;Serial=$i.Serial;CPU=$cpu.Name;Cores=$cpu.NumberOfCores;LogicalProcessors=$cpu.NumberOfLogicalProcessors;MemoryGB=$i.MemoryGB;Architecture=$i.Architecture;Firmware=$firmware;SecureBoot=$secure;TPMVersion=$(if($tpm){$tpm.SpecVersion}else{$null});TPMEnabled=$(if($tpm){$tpm.IsEnabled_InitialValue}else{$null});IsVirtual=($i.Model -match 'Virtual|QEMU|VMware|KVM');Disks=@(Get-Disk | Select-Object Number,FriendlyName,BusType,Size);ProblemDevices=@($i.Devices | Where-Object {$_.ConfigManagerErrorCode -ne 0})}
}

function Get-GNAutopilotReadiness {
    [CmdletBinding()]param([Parameter(Mandatory)]$Hardware,[string]$Edition,[string]$ImageVersion)
    $rows=New-Object Collections.Generic.List[object]
    $rows.Add([pscustomobject]@{Check='Arquitectura';Status=$(if($Hardware.Architecture -match 'AMD64|ARM64'){'OK'}else{'Revisar'});Detail=$Hardware.Architecture})
    $supported=@('Professional','ProfessionalEducation','ProfessionalWorkstation','Enterprise','EnterpriseS','Education')
    $state='Pendiente';$detail='Seleccione una edicion Windows para evaluar.'
    if($Edition){$state=if($Edition -in $supported){'OK'}elseif($Edition -match '^IoT'){'Condicional'}elseif($Edition -match '^Core|WindowsPE|WindowsSetup'){'No compatible'}else{'No verificado'};$detail=$Edition;if($Edition -match '^IoT'){$detail+=': Autopilot admite IoT solo en Microsoft Teams Rooms.'}}
    $rows.Add([pscustomobject]@{Check='Edicion Windows';Status=$state;Detail=$detail})
    $rows.Add([pscustomobject]@{Check='Firmware';Status=$(if($Hardware.Firmware -eq 'UEFI'){'OK'}else{'Revisar'});Detail=$Hardware.Firmware})
    $rows.Add([pscustomobject]@{Check='Secure Boot';Status=$(if($null -eq $Hardware.SecureBoot){'No verificado'}elseif($Hardware.SecureBoot){'OK'}else{'Desactivado'});Detail='Comprobacion local; no confirma todos los requisitos de Windows 11.'})
    $tpmOK=$Hardware.TPMVersion -match '2\.0' -and $Hardware.TPMEnabled
    $rows.Add([pscustomobject]@{Check='TPM 2.0';Status=$(if($tpmOK){'OK'}else{'No verificado'});Detail=$(if($Hardware.TPMVersion){$Hardware.TPMVersion}else{'El proveedor TPM puede no estar disponible en WinRE.'})})
    $rows.Add([pscustomobject]@{Check='Autopilot con usuario';Status='Condicional';Detail='Requiere edicion admitida, perfil, red, licencias y configuracion del tenant.'})
    $rows.Add([pscustomobject]@{Check='Self-deploy / pre-provision';Status=$(if($Hardware.IsVirtual){'No compatible'}elseif($tpmOK){'Condicional'}else{'No verificado'});Detail=$(if($Hardware.IsVirtual){'Las VM no admiten atestacion TPM para estos modos.'}else{'TPM fisico 2.0 y atestacion requeridos; atestacion no ensayada.'})})
    $rows.Add([pscustomobject]@{Check='Tenant / registro / licencias';Status='No verificado';Detail='Un JSON offline no confirma registro del equipo, asignacion ni licencias en Intune.'})
    if($ImageVersion -match '^6\.1\.'){
        foreach($row in $rows | Where-Object {$_.Check -in @('Edicion Windows','Autopilot con usuario','Self-deploy / pre-provision')}){$row.Status='No compatible';$row.Detail='Windows 7 no admite Windows Autopilot.'}
    }
    $rows
}

function Get-GNDriverCompatibility {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$ImageVersion)
    $manifest=Join-Path $Path 'GNDeploy-pack.json'
    if(-not(Test-Path -LiteralPath $manifest)){return [pscustomobject]@{Status='No verificado';Detail='Pack sin metadatos de compatibilidad. Confirme modelo, arquitectura y Windows.'}}
    $data=Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    if($data.Architecture -ne 'x64' -or $data.MinBuild -lt 1 -or $data.MaxBuild -lt $data.MinBuild){throw 'Metadatos de compatibilidad de drivers invalidos.'}
    $build=([version]$ImageVersion).Build
    if($build -lt $data.MinBuild -or $build -gt $data.MaxBuild){return [pscustomobject]@{Status='No compatible';Detail='El pack declara otra version de Windows: '+$data.Name}}
    [pscustomobject]@{Status='SO compatible';Detail=$data.Name+'; compatibilidad del dispositivo fisico pendiente de comprobar.'}
}
