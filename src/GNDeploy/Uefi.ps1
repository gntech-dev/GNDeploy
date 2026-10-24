function Get-GNUefiDeploymentLayout {
    [CmdletBinding()]param([int]$DiskNumber,[ValidatePattern('^[A-Z]$')][string]$OSLetter,[ValidatePattern('^[A-Z]$')][string]$SystemLetter,[ValidatePattern('^[A-Z]$')][string]$RecoveryLetter,[switch]$Windows7)
    $msr=if($Windows7){128}else{16}
    $recovery='';$shrink=''
    $assignments=@(@{Letter=$SystemLetter;Number=1;Type='c12a7328-f81f-11d2-ba4b-00a0c93ec93b'},@{Letter=$OSLetter;Number=3;Type='ebd0a0a2-b9e5-4433-87c0-68b6b72699c7'})
    if(-not $Windows7){
        $shrink='shrink minimum=2048'
        $recovery=@"
create partition primary
format quick fs=ntfs label=Recovery
assign letter=$RecoveryLetter
set id=de94bba4-06d1-4d40-a16a-bfd50179d6ac
gpt attributes=0x8000000000000001
"@
        $assignments+=@{Letter=$RecoveryLetter;Number=4;Type='de94bba4-06d1-4d40-a16a-bfd50179d6ac'}
    }
    $commands=@"
select disk $DiskNumber
clean
convert gpt
create partition efi size=260
format quick fs=fat32 label=System
assign letter=$SystemLetter
create partition msr size=$msr
create partition primary
$shrink
format quick fs=ntfs label=Windows
assign letter=$OSLetter
$recovery
exit
"@
    [pscustomobject]@{Commands=$commands;Assignments=$assignments;SeparateRecovery=(-not $Windows7)}
}

function Assert-GNWindows7UefiFirmware {
    [CmdletBinding()]param()
    $system=Get-CimInstance Win32_ComputerSystem
    if($system.Manufacturer -eq 'Microsoft Corporation' -and $system.Model -eq 'Virtual Machine'){throw 'Windows 7 UEFI no admite Hyper-V de generacion 2. No se modifico el disco; pruebe el T420 fisico.'}
    $secure=$null
    try{$secure=[bool](Confirm-SecureBootUEFI -ErrorAction Stop)}catch{}
    if($null -eq $secure){try{$secure=[bool](Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -Name UEFISecureBootEnabled -ErrorAction Stop)}catch{}}
    if($secure -eq $true){throw 'Windows 7 requiere Secure Boot desactivado. No se modifico el disco.'}
    # Older firmware may have no Secure Boot provider. The plan explicitly records
    # this requirement; no firmware/security setting is changed by GNDeploy.
}
