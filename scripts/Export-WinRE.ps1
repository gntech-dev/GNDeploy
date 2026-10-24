#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]param(
    [Parameter(Mandatory)][string]$ImagePath,
    [ValidateRange(0,100)][int]$Index=0,
    [string]$Root="$env:LOCALAPPDATA\GNDeploy"
)
$ErrorActionPreference='Stop'
if ($Root -match '(?i)OneDrive') { throw 'Extraer WinRE fuera de OneDrive.' }
$adk="${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit"
$dism=Join-Path $adk 'Deployment Tools\amd64\DISM\dism.exe'
$work=Join-Path $Root ('Build\ExtractWinRE-'+(Get-Date -Format yyyyMMddHHmmss))
$mount=Join-Path $env:ProgramData ('GNDeploy\M\'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $mount,$work,"$Root\Sources" | Out-Null
function Run([string[]]$ArgumentList) { & $dism @ArgumentList | Out-Host; if ($LASTEXITCODE -ne 0) { throw "DISM fallo: $LASTEXITCODE" } }
$mounted=$false
Start-Transcript -Path "$work\extract.log"
try {
    if ($Index -eq 0) {
        $available=@(Get-WindowsImage -ImagePath $ImagePath)
        $available | Select-Object ImageIndex,ImageName | Format-Table
        $selected=@($available | Where-Object ImageName -eq 'Windows 11 Pro')
        if ($selected.Count -ne 1) {throw 'Indique -Index para seleccionar una imagen Windows instalable.'}
        $Index=[int]$selected[0].ImageIndex
    }
    # Export first: recovery-compressed ESD cannot be mounted directly.
    Run @('/Export-Image',"/SourceImageFile:$ImagePath","/SourceIndex:$Index","/DestinationImageFile:$work\install.wim",'/Compress:max','/CheckIntegrity')
    Run @('/Mount-Image',"/ImageFile:$work\install.wim",'/Index:1',"/MountDir:$mount",'/ReadOnly')
    $mounted=$true
    $source="$mount\Windows\System32\Recovery\winre.wim"
    if (-not (Test-Path -LiteralPath $source)) { throw 'La imagen seleccionada no tiene winre.wim.' }
    $destination=Join-Path "$Root\Sources" ('winre-'+(Get-Date -Format yyyyMMddHHmmss)+'.wim')
    Copy-Item -LiteralPath $source -Destination $destination
    Write-Host "WinRE extraido: $destination"
    @{Path=$destination;Source=$ImagePath;Index=$Index;Sha256=(Get-FileHash $destination).Hash} | ConvertTo-Json | Set-Content "$Root\Sources\latest-winre.json" -Encoding UTF8
} catch {
    @{Error=$_.Exception.Message;Location=[string]$_.InvocationInfo.PositionMessage} | ConvertTo-Json | Set-Content "$work\failure.json"
    throw
} finally { if ($mounted) { & $dism /Unmount-Image "/MountDir:$mount" /Discard | Out-Host };Stop-Transcript }
