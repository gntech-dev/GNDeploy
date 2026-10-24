function Invoke-GNLegacyDeployment {
    [CmdletBinding()]param([Parameter(Mandatory)]$Plan)
    # Private entry point; destructive guard is repeated even when called from module scope.
    if(-not(Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')){throw 'Solo WinPE/WinRE.'}
    Assert-GNAdministrator
    if($Plan.FirmwareMode -ne 'BIOS' -or $Plan.ImageVersion -notmatch '^6\.1\.' -or $Plan.AutopilotProfile){throw 'Plan legacy no valido.'}
    if((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control').PEFirmwareType -ne 1){throw 'Solo arranque BIOS.'}
    $bootsect=Join-Path $env:SystemRoot 'System32\bootsect.exe'
    if(-not(Test-Path $bootsect)){$bootsect=Join-Path (Split-Path (Split-Path $PSScriptRoot)) 'Tools\bootsect.exe'}
    if(-not(Test-Path -LiteralPath $bootsect)){throw 'Falta bootsect.exe; no se modifico el disco.'}
    $occupied=@(Get-Partition | ForEach-Object {[string]$_.DriveLetter})+@(Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Name)
    $letters=@('W','S','R','T','U','V','Y','Z' | Where-Object {$_ -notin $occupied -and -not(Test-Path "${_}:\")})
    if($letters.Count -lt 2){throw 'No hay letras disponibles.'}
    $os=$letters[0];$system=$letters[1]
    $run=Join-Path $Plan.LogRoot $Plan.Id;New-Item -ItemType Directory -Path $run -Force | Out-Null
    $Plan | ConvertTo-Json -Depth 10 | Set-Content "$run\plan.json"
    $result=[ordered]@{Id=$Plan.Id;State='Running';Step='Partition';FirmwareMode='BIOS';Started=(Get-Date).ToString('o');Recovery='Windows 7 default; no separate WinRE registration';Finished=$null;Error=$null}
    Start-Transcript "$run\deployment.log"
    try{
        $disk=Get-Disk -Number $Plan.DiskNumber
        if($disk.UniqueId -ne $Plan.DiskUniqueId -or $disk.Size -ne $Plan.DiskSize -or $disk.IsBoot -or $disk.IsSystem -or $disk.IsOffline -or $disk.IsReadOnly -or $disk.BusType -in @('USB','SD','MMC')){throw 'El disco cambio o no esta permitido.'}
        $commands=@"
select disk $($Plan.DiskNumber)
clean
convert mbr
create partition primary size=500
format quick fs=ntfs label=System
active
assign letter=$system
create partition primary
format quick fs=ntfs label=Windows
assign letter=$os
exit
"@
        Write-GNDiskpartScript -Path "$run\diskpart.txt" -Commands $commands
        & diskpart.exe /s "$run\diskpart.txt" 2>&1 | Tee-Object "$run\diskpart.log" | Out-Host
        if($LASTEXITCODE){throw "DiskPart fallo: $LASTEXITCODE"}
        Get-Partition | Select-Object DiskNumber,PartitionNumber,DriveLetter,AccessPaths,MbrType,IsActive,Size | ConvertTo-Json -Depth 5 | Set-Content "$run\partitions-after.json"
        Wait-GNDeploymentPartitions -DiskNumber $Plan.DiskNumber -Assignments @(@{Letter=$system;Number=1;MbrType=7;Active=$true},@{Letter=$os;Number=2;MbrType=7;Active=$false})
        $scratch="${os}:\GNDeployScratch";New-Item -ItemType Directory -Path $scratch -Force | Out-Null
        $result.Step='ApplyImage';$result | ConvertTo-Json | Set-Content "$run\result.json"
        Invoke-GNNative dism.exe @('/Apply-Image',"/ImageFile:$($Plan.ImagePath)","/Index:$($Plan.ImageIndex)","/ApplyDir:${os}:\",'/CheckIntegrity',"/ScratchDir:$scratch","/LogPath:$run\dism-apply.log")
        if($Plan.DriverPath){$result.Step='Drivers';Invoke-GNNative dism.exe @("/Image:${os}:\",'/Add-Driver',"/Driver:$($Plan.DriverPath)",'/Recurse',"/ScratchDir:$scratch","/LogPath:$run\dism-drivers.log")}
        $result.Step='Boot';$result | ConvertTo-Json | Set-Content "$run\result.json"
        Invoke-GNNative bcdboot.exe @("${os}:\Windows",'/s',"${system}:",'/f','BIOS')
        Invoke-GNNative $bootsect @('/nt60',"${system}:",'/mbr')
        if(-not(Test-Path "${system}:\bootmgr") -or -not(Test-Path "${system}:\Boot\BCD")){throw 'Faltan BOOTMGR o BCD.'}
        $result.State='Succeeded';$result.Step='ReadyForOOBE'
    }catch{$result.State='Failed';$result.Error=$_.Exception.Message;throw}
    finally{$result.Finished=(Get-Date).ToString('o');$result | ConvertTo-Json | Set-Content "$run\result.json";Stop-Transcript;if(Test-Path "${os}:\Windows"){$dest="${os}:\ProgramData\GNDeploy\Logs\$($Plan.Id)";New-Item -ItemType Directory -Path $dest -Force | Out-Null;Copy-Item "$run\*" $dest -Recurse -Force}}
    [pscustomobject]$result
}
