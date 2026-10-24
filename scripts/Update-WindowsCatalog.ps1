#Requires -Version 5.1
[CmdletBinding()]param(
    [uri]$Uri='https://go.microsoft.com/fwlink/?LinkID=2156292',
    [string]$Root="$env:LOCALAPPDATA\GNDeploy"
)
$ErrorActionPreference='Stop'
if ($Uri.Scheme -ne 'https' -or $Uri.Host -notmatch '(^|\.)microsoft\.com$') { throw 'Se requiere un catalogo HTTPS de Microsoft.' }
Import-Module "$(Split-Path $PSScriptRoot)\src\GNDeploy\GNDeploy.psd1" -Force
$id=Get-Date -Format 'yyyyMMdd-HHmmss'
$work=Join-Path $Root "Downloads\Catalog-$id"
New-Item -ItemType Directory -Force -Path $work,"$Root\Catalogs" | Out-Null
$cab=Save-GNDownload -Uri $Uri -Destination "$work\products.cab"
$xml=Join-Path $work 'products.xml'
# This official CAB contains one XML file. Give expand an explicit output filename.
& expand.exe $cab $xml | Out-Host
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $xml)) { throw 'No se pudo extraer el catalogo.' }
$records=@(Get-GNWindowsCatalog $xml -Language 'en-us')
if ($records.Count -eq 0) { throw 'Catalogo sin imagenes validas.' }
$fileName=$records[0].FileName
$build=$fileName.Split('.')[0]
$destination=Join-Path "$Root\Catalogs" "Microsoft-$build-$id.xml"
Copy-Item -LiteralPath $xml -Destination $destination
@{Uri=$Uri.AbsoluteUri;Downloaded=(Get-Date).ToString('o');CabSha256=(Get-FileHash $cab).Hash;XmlSha256=(Get-FileHash $xml).Hash;Build=$build;Note='El fwlink puede publicar medios antiguos; no se declara automaticamente como ultima version.'} | ConvertTo-Json | Set-Content "$destination.provenance.json" -Encoding UTF8
Write-Host "Catalogo publicado: $destination (build $build)"
