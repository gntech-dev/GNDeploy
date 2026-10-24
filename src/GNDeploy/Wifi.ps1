function Initialize-GNWifiNative {
    if('GNDeploy.Wifi' -as [type]){return}
    Add-Type -Path (Join-Path $PSScriptRoot 'WifiNative.cs')
}
function Get-GNWifiNetwork {
    [CmdletBinding()]param()
    $service=Get-Service WlanSvc -ErrorAction SilentlyContinue
    if(-not $service){return}
    if($service.Status -ne 'Running'){Start-Service WlanSvc -ErrorAction Stop}
    Initialize-GNWifiNative
    $aliases=@(Get-CimInstance Win32_NetworkAdapter -ErrorAction SilentlyContinue | Where-Object GUID)
    foreach($network in [GNDeploy.Wifi]::Networks()){
        $alias=$aliases | Where-Object {$_.GUID.Trim('{}') -eq $network.InterfaceId.ToString()} | Select-Object -First 1
        $network.InterfaceName=if($alias){[string]$alias.NetConnectionID}else{$null}
        $network
    }
}
