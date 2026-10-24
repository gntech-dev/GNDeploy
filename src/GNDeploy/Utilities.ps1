function Get-GNUtilityInventory {
    [CmdletBinding()]param([ValidateSet('Volumes','Devices','Network')][string]$Kind)
    switch($Kind){
        'Volumes' {foreach($v in Get-Volume | Where-Object DriveLetter | Sort-Object DriveLetter){[pscustomobject]@{Name=([string]$v.DriveLetter+': '+$v.FileSystemLabel);Status=[string]$v.HealthStatus;Detail=('{0}; libre {1:N1} GB / {2:N1} GB' -f $v.FileSystem,($v.SizeRemaining/1GB),($v.Size/1GB))}}}
        'Devices' {foreach($d in Get-CimInstance Win32_PnPEntity | Where-Object {$_.ConfigManagerErrorCode -ne 0}){[pscustomobject]@{Name=if($d.Name){$d.Name}else{$d.DeviceID};Status=('Codigo '+$d.ConfigManagerErrorCode);Detail=($d.DeviceID+'; '+($d.HardwareID -join '; '))}}}
        'Network' {foreach($n in Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object IPEnabled){[pscustomobject]@{Name=$n.Description;Status=if($n.DHCPEnabled){'DHCP'}else{'IP estatica'};Detail=('IP: '+($n.IPAddress -join ', ')+'; gateway: '+($n.DefaultIPGateway -join ', ')+'; DNS: '+($n.DNSServerSearchOrder -join ', '))}}}
    }
}
function Test-GNFileIntegrity {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$Path,[string]$ExpectedSha256)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'Seleccione un archivo existente.'}
    $expected=$ExpectedSha256.Trim()
    if($expected -and $expected -notmatch '^[a-fA-F0-9]{64}$'){throw 'El SHA-256 esperado debe tener 64 caracteres hexadecimales.'}
    $hash=(Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
    [pscustomobject]@{Path=$Path;Bytes=(Get-Item -LiteralPath $Path).Length;SHA256=$hash;Status=if(-not $expected){'Calculado; sin referencia para comparar'}elseif($hash -ieq $expected){'Coincide'}else{'NO COINCIDE'}}
}
function Import-GNSessionDriver {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$Path)
    if(-not(Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')){throw 'La carga de drivers de sesion solo esta permitida en WinPE/WinRE.'}
    if([IO.Path]::GetExtension($Path) -ine '.inf' -or -not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'Seleccione un archivo INF existente y extraido.'}
    $output=& "$env:SystemRoot\System32\drvload.exe" $Path 2>&1 | Out-String
    if($LASTEXITCODE -ne 0){throw ('No se pudo cargar el driver: '+$output)}
    return $output
}
