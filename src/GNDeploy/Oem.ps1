function Get-GNOemDriverPack {
    [CmdletBinding()]param(
        [Parameter(Mandatory)][ValidateSet('Dell','HP')][string]$Manufacturer,
        [Parameter(Mandatory)][string]$CatalogPath,
        [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9]{4,12}$')][string]$SystemId,
        [string]$Release='24H2'
    )
    $doc=Read-GNXml $CatalogPath
    if($Manufacturer -eq 'Dell') {
        $ns=New-Object Xml.XmlNamespaceManager($doc.NameTable)
        $ns.AddNamespace('d',$doc.DocumentElement.NamespaceURI)
        foreach($pack in @($doc.SelectNodes('/d:DriverPackManifest/d:DriverPackage',$ns))) {
            $models=@($pack.SelectNodes('d:SupportedSystems/d:Brand/d:Model',$ns) | Where-Object {$_.GetAttribute('systemID') -ieq $SystemId})
            if($models.Count -eq 0){continue}
            $os=$pack.SelectSingleNode('d:SupportedOperatingSystems/d:OperatingSystem[@osCode="Windows11" and @osArch="x64"]',$ns)
            if(-not $os){continue}
            $hashNode=$pack.SelectSingleNode('d:Cryptography/d:Hash[@algorithm="SHA256"]',$ns)
            if(-not $hashNode -or $hashNode.InnerText -notmatch '^[a-fA-F0-9]{64}$'){continue}
            $uri=[uri]('https://downloads.dell.com/'+$pack.GetAttribute('path'))
            [pscustomobject]@{Manufacturer='Dell';Model=$models[0].GetAttribute('name');SystemId=$SystemId;Release='Windows11';Date=[datetime]$pack.GetAttribute('dateTime');Uri=$uri.AbsoluteUri;Sha256=$hashNode.InnerText;Size=[long]$pack.GetAttribute('size');FileName=[IO.Path]::GetFileName($uri.AbsolutePath)}
        }
    } else {
        $softpaqs=@{}
        foreach($softpaq in @($doc.SelectNodes('//*[local-name()="SoftPaq"]'))) {$softpaqs[$softpaq.Id]=$softpaq}
        foreach($mapping in @($doc.SelectNodes('//*[local-name()="ProductOSDriverPack"]'))) {
            if($SystemId -notin @(([string]$mapping.SystemId -split ',') | ForEach-Object {$_.Trim()})){continue}
            if([string]$mapping.OSName -notlike "Windows 11*${Release}*" -or [string]$mapping.Architecture -ne '64-bit'){continue}
            if(-not $softpaqs.ContainsKey([string]$mapping.SoftPaqId)){continue}
            $pack=$softpaqs[[string]$mapping.SoftPaqId]
            if([string]$pack.SHA256 -notmatch '^[a-fA-F0-9]{64}$'){continue}
            $uri=[uri][string]$pack.Url
            if($uri.Scheme -ne 'https' -or $uri.Host -notmatch '(^|\.)hp\.com$'){throw 'Origen HP no permitido.'}
            [pscustomobject]@{Manufacturer='HP';Model=[string]$mapping.SystemName;SystemId=$SystemId;Release=$Release;Date=[datetime]::Parse([string]$pack.DateReleased,[Globalization.CultureInfo]::GetCultureInfo('en-US'));Uri=$uri.AbsoluteUri;Sha256=[string]$pack.SHA256;Size=[long]$pack.Size;FileName=[IO.Path]::GetFileName($uri.AbsolutePath)}
        }
    }
}

function Save-GNOemDriverPack {
    [CmdletBinding()]param([Parameter(Mandatory)]$Pack,[Parameter(Mandatory)][string]$CacheRoot,[Parameter(Mandatory)][string]$Extractor)
    $archive=Save-GNDownload -Uri $Pack.Uri -Destination (Join-Path $CacheRoot $Pack.FileName) -Sha256 $Pack.Sha256 -ExpectedSize $Pack.Size
    $out=Join-Path $CacheRoot $Pack.Sha256
    $marker=Join-Path $out '.gndeploy-complete'
    if(-not(Test-Path -LiteralPath $marker)) {
        New-Item -ItemType Directory -Force -Path $out | Out-Null
        Invoke-GNNative $Extractor @('x',$archive,"-o$out",'-y','-bso0')
        if(@(Get-ChildItem -LiteralPath $out -Filter *.inf -Recurse).Count -eq 0) {throw 'El extractor no produjo INF. Se requiere un pack extraido manualmente para este formato OEM.'}
        Set-Content -LiteralPath $marker -Value $Pack.Sha256 -Encoding ASCII
    }
    return $out
}
