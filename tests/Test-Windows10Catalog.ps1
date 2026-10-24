#Requires -Version 5.1
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
Import-Module "$repo\src\GNDeploy\GNDeploy.psd1" -Force
$module=Get-Module GNDeploy
$root=Join-Path $env:TEMP ('GNDeploy-Windows10-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $root | Out-Null
function Check($value,$message){if(-not $value){throw $message};Write-Host "PASS $message"}
try{
    'fixture' | Set-Content "$root\install.wim"
    & $module {
        $script:ModernImage=[pscustomobject]@{Architecture=9;ImageName='Windows 10 Pro';EditionId='Professional';Version=[version]'10.0.19045.3803';ImageSize=16GB}
        function script:Get-WindowsImage {param($ImagePath,$Index) $script:ModernImage}
        function script:Get-GNPathDiskNumber {param($Path) return $null}
        function script:Get-GNTargetDisk {param($ExcludeDiskNumber) [pscustomobject]@{Number=2;UniqueId='modern-test';FriendlyName='Test';Size=40GB}}
    }
    foreach($name in @('Windows 10 Pro','Windows 10 Enterprise LTSC 2021','Windows 10 IoT Enterprise LTSC 2021')){
        & $module {param($name) $script:ModernImage.ImageName=$name} $name
        $plan=New-GNDeploymentPlan -DiskNumber 2 -ImagePath "$root\install.wim" -ImageIndex 1 -LogRoot "$root\logs"
        Check ($plan.ImageName -eq $name -and $plan.FirmwareMode -eq 'UEFI') "$name admite plan UEFI en 40 GB"
    }
    & $module {$script:ModernImage.ImageName='Windows 11 IoT Enterprise LTSC';$script:ModernImage.Version=[version]'10.0.26100.1742'}
    $rejected=$false;try{New-GNDeploymentPlan -DiskNumber 2 -ImagePath "$root\install.wim" -ImageIndex 1 -LogRoot "$root\logs" | Out-Null}catch{$rejected=$true}
    Check $rejected 'Windows 11 IoT conserva minimo 64 GB'
    & $module {$script:ModernImage.ImageName='Windows 10 Windows PE';$script:ModernImage.EditionId='WindowsPE';$script:ModernImage.Version=[version]'10.0.19045.3803'}
    $rejected=$false;try{New-GNDeploymentPlan -DiskNumber 2 -ImagePath "$root\install.wim" -ImageIndex 1 -LogRoot "$root\logs" | Out-Null}catch{$rejected=$true}
    Check $rejected 'Windows PE sigue bloqueado'
    $catalog=@(Get-GNWindowsCatalog "$repo\config\catalogs\Microsoft-LTSC.media.json" -Language en-us)
    Check (@($catalog | Where-Object Acquisition -eq LicensedMedia).Count -eq 4) 'Catalogo distingue cuatro familias comerciales LTSC'
    Check (@($catalog | Where-Object Acquisition -eq Unavailable).Count -eq 1) 'IoT 11 evaluacion bloqueada hasta resolver hash oficial'
    $xml=Get-ChildItem "$repo\config\catalogs\Microsoft-19045-*.xml" | Select-Object -First 1
    $records=@(Get-GNWindowsCatalog $xml.FullName -Language en-us)
    Check ($records.Count -gt 0 -and @($records | Where-Object Family -ne 'Windows 10').Count -eq 0) 'Catalogo Microsoft 19045 identificado como Windows 10'
}finally{
    Remove-Module GNDeploy -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $root -Recurse -Force
}

