#Requires -Version 5.1
$ErrorActionPreference='Stop'
Import-Module "$PSScriptRoot\..\src\GNDeploy\GNDeploy.psd1" -Force
$root=Join-Path $env:TEMP ('GNDeploy-Workflow-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $root | Out-Null
function Check($condition,$message){if(-not $condition){throw $message};Write-Host "PASS $message"}
try{
    $r=Get-GNDriverCompatibility -Path $root -ImageVersion 10.0.19045.3803
    Check ($r.Status -eq 'No verificado') 'No declara compatible un pack sin metadatos'
    @{Name='Fixture Windows 11';Architecture='x64';MinBuild=26100;MaxBuild=26100} | ConvertTo-Json | Set-Content "$root\GNDeploy-pack.json"
    Check ((Get-GNDriverCompatibility -Path $root -ImageVersion 10.0.19045.3803).Status -eq 'No compatible') 'Detecta pack Windows 11 elegido para Windows 10'
    Check ((Get-GNDriverCompatibility -Path $root -ImageVersion 10.0.26100.1).Status -eq 'SO compatible') 'Compatibilidad de SO no afirma validacion fisica'
    $blocked=$false
    try{Save-GNDownload -Uri 'https://download.microsoft.com/fixture.esd' -Destination "$root\no-space.esd" -ExpectedSize 1PB | Out-Null}catch{$blocked=$_.Exception.Message -match 'espacio suficiente'}
    Check $blocked 'Cache sin espacio se bloquea antes de iniciar la red'
    $module=Get-Module GNDeploy
    & $module {Assert-GNDownloadRange -Headers "HTTP/1.1 206 Partial Content`r`nContent-Range: bytes 64-127/256`r`n" -Start 64 -End 127 -Total 256}
    Check $true 'Rango HTTP exacto admitido'
    foreach($headers in @('Content-Range: bytes 0-63/256','Content-Range: bytes 64-127/512','HTTP/1.1 200 OK')){
        $blocked=$false;try{& $module {param($h) Assert-GNDownloadRange -Headers $h -Start 64 -End 127 -Total 256} $headers}catch{$blocked=$true}
        Check $blocked 'Respuesta HTTP incorrecta no se agrega al parcial'
    }
    'image' | Set-Content "$root\install.wim"
    & $module {
        function script:Get-WindowsImage {param($ImagePath,$Index) [pscustomobject]@{Architecture=9;ImageName='Windows 10 Home';EditionId='Core';Version=[version]'10.0.19045.3803';ImageSize=16GB}}
        function script:Get-GNPathDiskNumber {param($Path) return $null}
        function script:Get-GNTargetDisk {param($ExcludeDiskNumber) [pscustomobject]@{Number=2;UniqueId='workflow-test';FriendlyName='Test';Size=64GB}}
    }
    $rejected=$false;try{New-GNDeploymentPlan -DiskNumber 2 -ImagePath "$root\install.wim" -ImageIndex 1 -LogRoot "$root\logs" -AutopilotProfile "$root\missing.json" | Out-Null}catch{$rejected=$_.Exception.Message -match 'Home no admite Autopilot'}
    Check $rejected 'Home con Autopilot se bloquea antes de intentar leer el perfil'
}finally{Remove-Module GNDeploy -ErrorAction SilentlyContinue;Remove-Item -LiteralPath $root -Recurse -Force}


