#Requires -Version 5.1
$ErrorActionPreference='Stop'
Import-Module "$PSScriptRoot\..\src\GNDeploy\GNDeploy.psd1" -Force
$module=Get-Module GNDeploy
$root=Join-Path $env:TEMP ('GNDeploy-LegacyTests-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $root | Out-Null
function Check($value,$message){if(-not $value){throw $message};Write-Host "PASS $message"}
function Reject([scriptblock]$action,$message){$rejected=$false;try{& $action | Out-Null}catch{$rejected=$true};Check $rejected $message}
try{
    'fixture' | Set-Content "$root\install.wim"
    & $module {
        $script:LegacyImage=[pscustomobject]@{Architecture=9;ImageName='Windows 7 Ultimate';EditionId='Ultimate';Version=[version]'6.1.7601.17514';ImageSize=12GB}
        function script:Get-WindowsImage {param($ImagePath,$Index) $script:LegacyImage}
        function script:Get-GNPathDiskNumber {param($Path) return $null}
        function script:Get-GNTargetDisk {param($ExcludeDiskNumber) [pscustomobject]@{Number=2;UniqueId='legacy-test';FriendlyName='Virtual';Size=64GB}}
    }
    $plan=New-GNDeploymentPlan -DiskNumber 2 -ImagePath "$root\install.wim" -ImageIndex 1 -LogRoot "$root\logs" -FirmwareMode BIOS
    Check ($plan.FirmwareMode -eq 'BIOS' -and $plan.ImageVersion -like '6.1.*') 'Windows 7 x64 produce plan BIOS'
    $uefi=New-GNDeploymentPlan -DiskNumber 2 -ImagePath "$root\install.wim" -ImageIndex 1 -LogRoot "$root\logs" -FirmwareMode UEFI
    Check ($uefi.FirmwareMode -eq 'UEFI' -and $uefi.CompatibilityNotes -match 'Secure Boot') 'Windows 7 admite plan UEFI con requisitos explicitos'
    $layouts=& $module { @((Get-GNUefiDeploymentLayout -DiskNumber 2 -OSLetter W -SystemLetter S -RecoveryLetter R -Windows7),(Get-GNUefiDeploymentLayout -DiskNumber 2 -OSLetter W -SystemLetter S -RecoveryLetter R)) }
    Check ($layouts[0].Commands -match 'convert gpt' -and $layouts[0].Commands -match 'msr size=128' -and $layouts[0].Commands -notmatch 'active|convert mbr|shrink' -and $layouts[0].Assignments.Count -eq 2) 'Windows 7 UEFI usa ESP FAT32, MSR 128 MB y Windows sin particiones MBR'
    Check ($layouts[1].Commands -match 'msr size=16' -and $layouts[1].Commands -match 'shrink minimum=2048' -and $layouts[1].Assignments.Count -eq 3) 'Windows 11 conserva GPT y Recovery separado'
    Reject {New-GNDeploymentPlan -DiskNumber 2 -ImagePath "$root\install.wim" -ImageIndex 1 -LogRoot "$root\logs" -FirmwareMode BIOS -AutopilotProfile "$root\profile.json"} 'Windows 7 rechaza Autopilot antes de desplegar'
    & $module {$script:LegacyImage.Architecture=0}
    Reject {New-GNDeploymentPlan -DiskNumber 2 -ImagePath "$root\install.wim" -ImageIndex 1 -LogRoot "$root\logs" -FirmwareMode BIOS} 'Runtime amd64 rechaza imagen x86'
    & $module {$script:LegacyImage.Architecture=9;$script:LegacyImage.ImageName='Windows 11 Pro';$script:LegacyImage.Version=[version]'10.0.26100.1'}
    Reject {New-GNDeploymentPlan -DiskNumber 2 -ImagePath "$root\install.wim" -ImageIndex 1 -LogRoot "$root\logs" -FirmwareMode BIOS} 'Windows 11 rechaza BIOS'
    Reject {& $module {param($plan) Invoke-GNLegacyDeployment -Plan $plan} $plan} 'Entrada legacy bloqueada fuera de WinPE'
    & $module {
        $script:LegacyPart=[pscustomobject]@{DiskNumber=2;PartitionNumber=1;DriveLetter='S';AccessPaths=@('S:\');MbrType=7;IsActive=$true}
        function script:Get-Partition {$script:LegacyPart}
        function script:Update-HostStorageCache {}
        function script:Test-Path {param($LiteralPath,$Path) $value=if($LiteralPath){$LiteralPath}else{$Path};if($value -match '^[A-Z]:\\$'){return $true};Microsoft.PowerShell.Management\Test-Path -LiteralPath $value}
        Wait-GNDeploymentPartitions -DiskNumber 2 -Assignments @(@{Letter='S';Number=1;MbrType=7;Active=$true}) -Attempts 1
    }
    Check $true 'Valida particion MBR NTFS activa en disco exacto'
    & $module {$script:LegacyPart.IsActive=$false}
    Reject {& $module {Wait-GNDeploymentPartitions -DiskNumber 2 -Assignments @(@{Letter='S';Number=1;MbrType=7;Active=$true}) -Attempts 1}} 'Rechaza particion sistema MBR inactiva'
    & $module {$script:LegacyPart.IsActive=$true;$script:LegacyPart.MbrType=12}
    Reject {& $module {Wait-GNDeploymentPartitions -DiskNumber 2 -Assignments @(@{Letter='S';Number=1;MbrType=7;Active=$true}) -Attempts 1}} 'Rechaza tipo MBR inesperado'
    $hardware=[pscustomobject]@{Architecture='AMD64';Firmware='BIOS';SecureBoot=$null;TPMVersion=$null;TPMEnabled=$false;IsVirtual=$true}
    $rows=@(Get-GNAutopilotReadiness -Hardware $hardware -Edition Professional -ImageVersion '6.1.7601.17514')
    Check (($rows | Where-Object Check -eq 'Autopilot con usuario').Status -eq 'No compatible') 'Windows 7 Professional nunca aparece compatible con Autopilot'
    & $module {function script:Get-CimInstance {param($ClassName) [pscustomobject]@{Manufacturer='Microsoft Corporation';Model='Virtual Machine'}}}
    Reject {& $module {Assert-GNWindows7UefiFirmware}} 'Windows 7 UEFI rechaza Hyper-V Gen2 antes de borrar'
    & $module {function script:Get-CimInstance {param($ClassName) [pscustomobject]@{Manufacturer='LENOVO';Model='ThinkPad T420'}};function script:Confirm-SecureBootUEFI {param($ErrorAction) return $true}}
    Reject {& $module {Assert-GNWindows7UefiFirmware}} 'Windows 7 UEFI rechaza Secure Boot activo'
    & $module {function script:Confirm-SecureBootUEFI {param($ErrorAction) return $false};Assert-GNWindows7UefiFirmware}
    Check $true 'Windows 7 UEFI admite firmware fisico compatible sin Secure Boot'
}finally{
    Remove-Module GNDeploy -Force
    $resolved=[IO.Path]::GetFullPath($root);$parent=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
    if($resolved.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'GNDeploy-LegacyTests-*'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
