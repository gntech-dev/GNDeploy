#Requires -Version 5.1
$ErrorActionPreference='Stop'
Import-Module "$PSScriptRoot\..\src\GNDeploy\GNDeploy.psd1" -Force
$hardware=[pscustomobject]@{Architecture='AMD64';Firmware='UEFI';SecureBoot=$true;TPMVersion='2.0';TPMEnabled=$true;IsVirtual=$true}
$result=@(Get-GNAutopilotReadiness -Hardware $hardware -Edition Core)
if(($result | Where-Object Check -eq 'Edicion Windows').Status -ne 'No compatible'){throw 'Home no debe admitirse.'}
if(($result | Where-Object Check -eq 'Self-deploy / pre-provision').Status -ne 'No compatible'){throw 'Una VM con vTPM no debe admitirse para atestacion.'}
$hardware.IsVirtual=$false
$result=@(Get-GNAutopilotReadiness -Hardware $hardware -Edition EnterpriseS)
if(($result | Where-Object Check -eq 'Edicion Windows').Status -ne 'OK'){throw 'Enterprise LTSC debe reconocerse.'}
if(($result | Where-Object Check -eq 'Self-deploy / pre-provision').Status -ne 'Condicional'){throw 'La comprobacion local no debe certificar atestacion.'}
if(($result | Where-Object Check -eq 'Tenant / registro / licencias').Status -ne 'No verificado'){throw 'No se puede certificar el tenant offline.'}
$result=@(Get-GNAutopilotReadiness -Hardware $hardware -Edition IoTEnterpriseS)
if(($result | Where-Object Check -eq 'Edicion Windows').Status -ne 'Condicional'){throw 'IoT requiere la limitacion Teams Rooms.'}
Write-Host 'PASS Autopilot: Home, Enterprise LTSC, IoT, VM, TPM y tenant desconocido.'
& (Get-Module GNDeploy) {Initialize-GNWifiNative;$type=[GNDeploy.Wifi].GetNestedType('Network',[Reflection.BindingFlags]::NonPublic);$method=[Runtime.InteropServices.Marshal].GetMethod('SizeOf',[type[]]@([type]));if($method.Invoke($null,@($type)) -ne 628){throw 'Layout WLAN incorrecto.'}}
Write-Host 'PASS WLAN: C# compila y layout nativo de 628 bytes.'
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\src\GNDeploy\GNDeploy.psm1'),[ref]$tokens,[ref]$parseErrors)
$body=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Connect-GNWifi'},$true).Body.GetScriptBlock()
function Get-Service {param($Name,$ErrorAction) [pscustomobject]@{Status='Running'}}
function Start-Service {param($Name)}
function Start-Sleep {param($Seconds)}
function Get-GNNetworkStatus {[pscustomobject]@{HttpsReachable=$true}}
function Invoke-GNNative {
    param($File,$Arguments)
    if($File -ne 'netsh.exe'){throw 'Ejecutable inesperado.'}
    if($Arguments[0] -eq 'wlan' -and $Arguments[1] -eq 'add'){
        $script:profilePath=($Arguments | Where-Object {$_ -like 'filename=*'}).Substring(9)
        $script:profile=[xml](Get-Content -LiteralPath $script:profilePath -Raw)
    }
}
foreach($mode in @('WPA2PSK','WPA3SAE','Open')){
    $parameters=@{SSID='QA & <test>'}
    if($mode -eq 'Open'){$parameters.Open=$true}else{$parameters.Password=ConvertTo-SecureString 'test-&<>1234' -AsPlainText -Force;$parameters.Authentication=$mode}
    $null=& $body @parameters
    $auth=$script:profile.SelectSingleNode('//*[local-name()="authentication"]').InnerText
    if($auth -ne $(if($mode -eq 'Open'){'open'}else{$mode})){throw 'Autenticacion incorrecta.'}
    if($mode -eq 'Open'){if($script:profile.SelectSingleNode('//*[local-name()="sharedKey"]')){throw 'Una red abierta no lleva clave.'}}else{if($script:profile.SelectSingleNode('//*[local-name()="keyMaterial"]').InnerText -ne 'test-&<>1234'){throw 'Escape de clave incorrecto.'}}
    if(Test-Path -LiteralPath $script:profilePath){throw 'El perfil temporal no se limpio.'}
    Write-Host "PASS XML Wi-Fi $mode, escape y limpieza; sin ejecutar netsh real."
}
