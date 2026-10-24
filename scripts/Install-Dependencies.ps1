#Requires -Version 5.1
[CmdletBinding()]
param([string]$Root = "$env:LOCALAPPDATA\GNDeploy")
$ErrorActionPreference = 'Stop'
if ($Root -match '(?i)OneDrive') { throw 'Las dependencias deben estar fuera de OneDrive.' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Ejecutar este script como administrador para instalar ADK y WinPE.'
}
New-Item -ItemType Directory -Force -Path "$Root\Downloads","$Root\Logs","$Root\Modules","$Root\Build","$Root\Cache","$Root\Autopilot\Profiles","$Root\Drivers\Boot","$Root\Drivers\Offline" | Out-Null
$machineLog = Join-Path $env:ProgramData 'GNDeploy\InstallerLogs'
New-Item -ItemType Directory -Force -Path $machineLog | Out-Null
Start-Transcript -Path "$Root\Logs\dependencies.log" -Append
try {
    foreach ($item in @(
        @{Name='adksetup.exe';Url='https://go.microsoft.com/fwlink/?linkid=2289980';Feature='OptionId.DeploymentTools'},
        @{Name='adkwinpesetup.exe';Url='https://go.microsoft.com/fwlink/?linkid=2289981';Feature='OptionId.WindowsPreinstallationEnvironment'}
    )) {
        $file = Join-Path "$Root\Downloads" $item.Name
        if (-not (Test-Path -LiteralPath $file)) { Invoke-WebRequest -UseBasicParsing -Uri $item.Url -OutFile $file }
        $signature = Get-AuthenticodeSignature -FilePath $file
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') { throw "Firma no valida: $file" }
        $process = Start-Process -FilePath $file -ArgumentList @('/quiet','/norestart','/ceip','off','/features',$item.Feature,'/log',"`"$machineLog\$($item.Name).log`"") -Wait -PassThru
        if ($process.ExitCode -notin @(0,3010)) { throw "Instalacion $($item.Name) fallo: $($process.ExitCode)" }
    }
    $adk = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit"
    foreach ($file in @("$adk\Deployment Tools\amd64\Oscdimg\oscdimg.exe","$adk\Windows Preinstallation Environment\amd64\en-us\winpe.wim")) {
        if (-not (Test-Path -LiteralPath $file)) { throw "Instalacion incompleta: $file" }
    }
    @{State='Succeeded';Finished=(Get-Date).ToString('o');Root=$Root;ADK=$adk} | ConvertTo-Json | Set-Content "$Root\Logs\dependencies-result.json" -Encoding UTF8
} catch {
    @{State='Failed';Error=$_.Exception.Message;Finished=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content "$Root\Logs\dependencies-result.json" -Encoding UTF8
    throw
} finally { Stop-Transcript }
