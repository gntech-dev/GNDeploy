#Requires -Version 5.1
$ErrorActionPreference='Stop'
Import-Module "$PSScriptRoot\..\src\GNDeploy\GNDeploy.psd1" -Force
$root=Join-Path $env:TEMP ('GNDeploy-Utilities-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $root | Out-Null
function Check($ok,$message){if(-not $ok){throw $message};Write-Host "PASS $message"}
try{
    $file=Join-Path $root 'fixture.bin';[IO.File]::WriteAllText($file,'abc',(New-Object Text.UTF8Encoding($false)))
    $expected='BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD'
    $r=Test-GNFileIntegrity $file $expected
    Check ($r.SHA256 -eq $expected -and $r.Status -eq 'Coincide' -and $r.Bytes -eq 3) 'SHA-256 coincide con vector conocido abc'
    Check ((Test-GNFileIntegrity $file ('0'*64)).Status -eq 'NO COINCIDE') 'Hash diferente se informa sin declarar integridad'
    Check ((Test-GNFileIntegrity $file).Status -like 'Calculado*') 'Sin referencia no se declara coincidencia'
    $blocked=$false;try{Test-GNFileIntegrity $file 'invalid'}catch{$blocked=$true};Check $blocked 'Referencia malformada rechazada'
    $blocked=$false;try{Test-GNFileIntegrity $root}catch{$blocked=$true};Check $blocked 'Directorio rechazado como archivo'
    $blocked=$false;try{Import-GNSessionDriver $file}catch{$blocked=$true};Check $blocked 'Carga de driver bloqueada fuera de WinPE'
    $m=Get-Module GNDeploy
    & $m {
        function script:Get-Volume {[pscustomobject]@{DriveLetter='T';FileSystemLabel='Fixture';HealthStatus='Healthy';FileSystem='NTFS';SizeRemaining=8GB;Size=16GB}}
        function script:Get-CimInstance {param($ClassName) if($ClassName -eq 'Win32_PnPEntity'){@([pscustomobject]@{Name='Missing driver';ConfigManagerErrorCode=28;DeviceID='PCI\FIXTURE';HardwareID=@('PCI\VEN_0000')},[pscustomobject]@{Name='Healthy';ConfigManagerErrorCode=0})}else{[pscustomobject]@{Description='Fixture NIC';IPEnabled=$true;DHCPEnabled=$true;IPAddress=@('192.0.2.10');DefaultIPGateway=@('192.0.2.1');DNSServerSearchOrder=@('192.0.2.53')}}}
    }
    Check ((Get-GNUtilityInventory Volumes).Detail -like '*8.0*16.0*' -or (Get-GNUtilityInventory Volumes).Detail -like '*8,0*16,0*') 'Inventario calcula espacio disponible'
    $devices=@(Get-GNUtilityInventory Devices);Check ($devices.Count -eq 1 -and $devices[0].Detail -like '*PCI\VEN_0000*') 'Solo problemas e identificadores de hardware'
    Check ((Get-GNUtilityInventory Network).Detail -like '*192.0.2.10*192.0.2.1*192.0.2.53*') 'Red incluye IP gateway y DNS'
}finally{Remove-Item -LiteralPath $root -Recurse -Force}
