#Requires -Version 5.1
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\scripts\New-GNDeployUSB.ps1'),[ref]$tokens,[ref]$errors)
if($errors){throw 'Error de sintaxis en el creador USB.'}
$guard=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Check-USB'},$true).Body.GetScriptBlock()
$DiskNumber=1;$ExpectedSerial='TEST-USB';$ExpectedSize=62021173248
function Get-Disk {param($Number) if($Number -ne 1){throw 'Disco inesperado.'};[pscustomobject]$script:fixture}
foreach($case in @('Valid','WrongSerial','WrongSize','NVMe','Boot','System')){
    $script:fixture=@{BusType='USB';IsBoot=$false;IsSystem=$false;SerialNumber='TEST-USB';Size=62021173248}
    switch($case){
        'WrongSerial' {$script:fixture.SerialNumber='OTHER'}
        'WrongSize' {$script:fixture.Size=100GB}
        'NVMe' {$script:fixture.BusType='NVMe'}
        'Boot' {$script:fixture.IsBoot=$true}
        'System' {$script:fixture.IsSystem=$true}
    }
    $rejected=$false
    try{$null=& $guard}catch{$rejected=$true}
    if(($case -eq 'Valid' -and $rejected) -or ($case -ne 'Valid' -and -not $rejected)){throw "Fallo de proteccion: $case"}
    Write-Host "PASS USB guard: $case"
}
Write-Host '6 comprobaciones correctas; no se consultaron ni modificaron discos reales.'
