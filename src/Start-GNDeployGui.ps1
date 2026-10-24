#Requires -Version 5.1
[CmdletBinding()]param([switch]$Preview,[string]$RenderPath,[switch]$VerifyPreview,[switch]$VerifyGuest,[switch]$VerifyToolsGuest,[string]$ReportRoot,[ValidateSet('Windows','Instalar','Herramientas')][string]$RenderTab='Windows',[switch]$ExitAfterVerification)
if($VerifyToolsGuest){$VerifyGuest=$true}
if($ExitAfterVerification -and -not $VerifyGuest){throw 'ExitAfterVerification requiere el modo de pruebas protegido.'}
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
if(-not $Preview -and (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')){
    if(-not('GNDeployKeyboard' -as [type])){
        Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class GNDeployKeyboard { [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr LoadKeyboardLayout(string name, uint flags); }'
    }
    if([GNDeployKeyboard]::LoadKeyboardLayout('00000409',0x101) -eq [IntPtr]::Zero){throw 'No se pudo activar el teclado English US.'}
    New-Item 'HKCU:\Keyboard Layout\Preload' -Force | Out-Null
    Set-ItemProperty 'HKCU:\Keyboard Layout\Preload' -Name '1' -Value '00000409'
}
$script:ModulePath=Join-Path $PSScriptRoot 'Modules\GNDeploy\GNDeploy.psd1'
if(-not(Test-Path $script:ModulePath)){$script:ModulePath=Join-Path $PSScriptRoot 'GNDeploy\GNDeploy.psd1'}
Import-Module $script:ModulePath -Force
$script:State=@{ImagePath=$null;Index=$null;DriverPath=$null;Profile=$null;Plan=$null;Catalog=@();Images=@();Disks=@();Profiles=@();Job=$null;Preview=[bool]$Preview}
$script:Ui=@{}
if(-not ('GNDeployFonts' -as [type])){Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class GNDeployFonts { [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] public static extern int AddFontResourceEx(string path, uint flags, IntPtr reserved); [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] public static extern bool RemoveFontResourceEx(string path, uint flags, IntPtr reserved); }'}
$script:Ui.RegisteredFonts=@()
$script:Ui.FontCollection=New-Object Drawing.Text.PrivateFontCollection
foreach($fontName in @('segoeui.ttf','segoeuib.ttf')){
    $fontPath=Join-Path "$PSScriptRoot\Fonts" $fontName
    if(-not(Test-Path $fontPath)){$fontPath=Join-Path "$env:SystemRoot\Fonts" $fontName}
    if(Test-Path $fontPath){if([GNDeployFonts]::AddFontResourceEx($fontPath,16,[IntPtr]::Zero) -gt 0){$script:Ui.RegisteredFonts+= $fontPath};$script:Ui.FontCollection.AddFontFile($fontPath)}
}
$script:Ui.FontFamily=$script:Ui.FontCollection.Families | Where-Object Name -eq 'Segoe UI' | Select-Object -First 1
if(-not $script:Ui.FontFamily){$script:Ui.FontFamily=New-Object Drawing.FontFamily('Microsoft Sans Serif')}
function GN-Label($Parent,$Text,$X,$Y,$Width=850){
    $c=New-Object Windows.Forms.Label;$c.Text=$Text;$c.UseMnemonic=$false;$c.AutoEllipsis=$true;$c.SetBounds($X,$Y,$Width,24);$Parent.Controls.Add($c);return $c
}
function GN-Text($Parent,$X,$Y,$Width,$Text=''){
    $c=New-Object Windows.Forms.TextBox;$c.Text=$Text;$c.SetBounds($X,$Y,$Width,28);$Parent.Controls.Add($c);return $c
}
function GN-Button($Parent,$Text,$X,$Y,$Width,$Action){
    $c=New-Object Windows.Forms.Button;$c.Text=$Text;$c.UseVisualStyleBackColor=$false;$c.BackColor=[Drawing.Color]::White;$c.ForeColor=[Drawing.Color]::FromArgb(30,41,59);$c.FlatStyle='Flat';$c.FlatAppearance.BorderColor=[Drawing.Color]::FromArgb(203,213,225);$c.FlatAppearance.MouseOverBackColor=[Drawing.Color]::FromArgb(226,239,250);$c.Cursor=[Windows.Forms.Cursors]::Hand;$c.SetBounds($X,$Y,$Width,32);$c.Add_Click({try {& $this.Tag}catch{GN-Error $_.Exception.Message}});$c.Tag=$Action;$Parent.Controls.Add($c);return $c
}
function GN-Combo($Parent,$X,$Y,$Width,$Values){
    $c=New-Object Windows.Forms.ComboBox;$c.DropDownStyle='DropDownList';$c.SetBounds($X,$Y,$Width,28);$c.Items.AddRange([object[]]$Values);$c.SelectedIndex=0;$Parent.Controls.Add($c);return $c
}
function GN-List($Parent,$X,$Y,$Width,$Height,$Columns){
    $c=New-Object Windows.Forms.ListView;$c.View='Details';$c.FullRowSelect=$true;$c.MultiSelect=$false;$c.HideSelection=$false;$c.GridLines=$false;$c.BorderStyle='FixedSingle';$c.ShowItemToolTips=$true;$c.SetBounds($X,$Y,$Width,$Height)
    foreach($column in $Columns){$null=$c.Columns.Add($column[0],[int]$column[1])};$Parent.Controls.Add($c);return $c
}
function GN-Row($List,$Values,$Value){
    $item=New-Object Windows.Forms.ListViewItem([string]$Values[0]);foreach($v in @($Values | Select-Object -Skip 1)){$null=$item.SubItems.Add([string]$v)};$item.BackColor=if($List.Items.Count % 2){[Drawing.Color]::FromArgb(243,247,251)}else{[Drawing.Color]::White};$item.ToolTipText=$Values -join ' | ';$item.Tag=$Value;$null=$List.Items.Add($item)
}
function GN-Selected($List,$Message){if($List.SelectedItems.Count -ne 1){throw $Message};return $List.SelectedItems[0].Tag}
function GN-DownloadState {
    $unavailable=$script:Ui.Catalog.SelectedItems.Count -eq 1 -and $script:Ui.Catalog.SelectedItems[0].Tag.Acquisition -eq 'Unavailable'
    $licensed=$script:Ui.Catalog.SelectedItems.Count -eq 1 -and $script:Ui.Catalog.SelectedItems[0].Tag.Acquisition -in @('LicensedMedia','Unavailable')
    $script:Ui.Download.Text=if($unavailable){'Ver disponibilidad'}elseif($licensed){'Importar WIM / ESD'}else{'Descargar seleccion'}
    $script:Ui.Download.Enabled=($script:Ui.Catalog.SelectedItems.Count -eq 1 -and ($licensed -or -not [string]::IsNullOrWhiteSpace($script:Ui.Cache.Text)))
}
function GN-Error([string]$Text){$script:Ui.Status.Text=$Text;if($VerifyGuest){$script:State.LastError=$Text;return};[Windows.Forms.MessageBox]::Show($script:Ui.Form,$Text,'GNDeploy','OK','Error')|Out-Null}
function GN-Media { @(Get-PSDrive -PSProvider FileSystem | Where-Object {Test-Path (Join-Path $_.Root 'GNDeploy')} | ForEach-Object {Join-Path $_.Root 'GNDeploy'}) }
function GN-Folder([string]$Title){
    $initial='';if($script:Ui.ContainsKey('Cache')){$initial=$script:Ui.Cache.Text}
    $d=GN-NewFolderDialog $Title $initial
    try{if($d.Form.ShowDialog($script:Ui.Form) -eq 'OK'){return $d.Path.Text}}finally{$d.Form.Dispose()}
}

. (Join-Path $PSScriptRoot 'GuiDialogs.ps1')
. (Join-Path $PSScriptRoot 'GuiTools.ps1')
. (Join-Path $PSScriptRoot 'GuiWorkflow.ps1')
function GN-File([string]$Filter){
    $extensions=@($Filter.Split('|')[1].Split(';') | ForEach-Object {$_.TrimStart('*')})
    $d=GN-NewFolderDialog $Filter.Split('|')[0] '' $extensions
    try{if($d.Form.ShowDialog($script:Ui.Form) -eq 'OK'){return $d.Path.Text}}finally{$d.Form.Dispose()}
}
function GN-Summary {
    $image='Sin imagen';if($script:State.ImagePath){$image=Split-Path $script:State.ImagePath -Leaf}
    if($script:State.Index -and $script:State.ImageName){$image=$script:State.ImageName}
    $profile='Sin perfil';if($script:State.Profile){$profile=$script:State.Profile.TenantDomain}
    $script:Ui.Summary.Text="Imagen: $image`r`nAutopilot: $profile"
    if($script:Ui.ContainsKey('Tips')){$script:Ui.Tips.SetToolTip($script:Ui.Summary,([string]$script:State.ImagePath+"`r`n"+$profile))}
    if($script:Ui.ContainsKey('ProfileDetail')){$script:Ui.ProfileDetail.Text=if($script:State.Profile){'Organizacion: '+$script:State.Profile.TenantDomain+' | Union: '+$(if($script:State.Profile.Profile.CloudAssignedDomainJoinMethod -eq 0){'Microsoft Entra ID'}else{'Hibrida'})+' | JSON valido; inscripcion sin verificar.'}else{'Sin perfil. Un JSON valido no confirma inscripcion ni asignacion del equipo.'}}
    GN-InvalidatePlan
}
function GN-InvalidatePlan {
    $script:State.Plan=$null;$script:Ui.Deploy.Enabled=$false;$script:Ui.Confirm.Checked=$false
    $script:Ui.Plan.Text='Prepare la instalacion para revisar el destino, Windows y Autopilot.'
}
function GN-Task([string]$Label,[scriptblock]$Work,[object[]]$Parameters,[scriptblock]$Done){
    if($script:State.Job){throw 'Espere a que termine la operacion actual.'}
    $ps=[PowerShell]::Create()
    $null=$ps.AddScript('param($module,$code,$values) $ErrorActionPreference="Stop";Import-Module $module -Force; & ([scriptblock]::Create($code)) @values').AddArgument($script:ModulePath).AddArgument($Work.ToString()).AddArgument($Parameters)
    $script:Ui.Tabs.Enabled=$false;$script:Ui.Progress.Style='Marquee';$script:Ui.Status.Text=$Label
    $script:State.Job=@{PS=$ps;Handle=$ps.BeginInvoke();Done=$Done;Label=$Label}
    $script:Ui.Timer.Start()
    GN-UpdateWizard
}
function GN-FilterCatalog {
    $script:Ui.Catalog.Items.Clear();$query=$script:Ui.Search.Text.Trim();$lang=$script:Ui.Language.Text
    foreach($r in $script:State.Catalog){
        if($lang -ne 'Todos' -and $r.Language -ne $lang){continue}
        if($query -and ($r.Family+' '+$r.Edition+' '+$r.FileName) -notlike "*$query*"){continue}
        $method=switch($r.Acquisition){'LicensedMedia'{'Importar WIM/ESD'} 'EvaluationISO'{'ISO evaluacion'} 'Unavailable'{'No disponible'} default{('{0:N2} GB' -f ($r.Size/1GB))}}
        GN-Row $script:Ui.Catalog @(($r.Family+' '+$r.Edition),$r.Language,$r.Architecture,$method,($r.FileName -replace '^([0-9]+\.[0-9]+).*','$1')) $r
    }
    $script:Ui.CatalogCount.Text=('{0} medios. Seleccione una fila; las ediciones exactas se eligen despues de descargar.' -f $script:Ui.Catalog.Items.Count)
}
function GN-LoadImage([string]$Path){
    if(-not $Path){return};$script:State.ImagePath=$Path;$script:State.Index=$null;GN-Summary
    GN-Task 'Leyendo ediciones de la imagen...' {param($path) Get-GNImage -Path $path | Where-Object {$_.Edition -and $_.Edition -notmatch 'WindowsPE|WindowsSetup'} } @($Path) {
        param($rows) $script:Ui.Editions.Items.Clear()
        foreach($r in $rows){GN-Row $script:Ui.Editions @($r.Index,$r.Name,$r.Edition,$r.Version) $r}
        $script:Ui.Tabs.SelectedTab=$script:Ui.WindowsTab;$script:Ui.Status.Text='Seleccione la edicion y pulse Usar edicion.'
    }
}
function GN-Download($Record,[string]$Cache,[bool]$Legacy=$false){
    $script:State.LastFailedDownload=$null
    if($Record.Acquisition -in @('LicensedMedia','Unavailable')){throw $Record.Notes}
    if($Record.Acquisition -eq 'EvaluationISO' -and -not $VerifyGuest){
        if([Windows.Forms.MessageBox]::Show($script:Ui.Form,'Esta ISO es una evaluacion de 90 dias. Desea descargarla?','ISO de evaluacion','YesNo','Information','Button2') -ne 'Yes'){return}
    }
    GN-Task 'Descargando y verificando imagen Windows...' {param($r,$cache,$legacy)
        try{
            if($r.Acquisition -eq 'EvaluationISO'){
                $drive=New-Object IO.DriveInfo ([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($cache)))
                if($drive.AvailableFreeSpace -lt (2*$r.Size+128MB)){throw 'La carpeta cache necesita espacio para la ISO y la imagen extraida. Elija otra carpeta con mas espacio.'}
            }
            $uri=$r.Uri;if($legacy){$uri=$uri -replace '^https:','http:'}
            $p=@{Uri=$uri;Destination=(Join-Path $cache $r.FileName);ExpectedSize=$r.Size;AllowMicrosoftHttp=$legacy}
            if($r.Sha256){$p.Sha256=$r.Sha256}else{$p.Sha1=$r.Sha1}
            $path=Save-GNDownload @p
            if($r.Acquisition -eq 'EvaluationISO'){
                $seven=@("$env:SystemDrive\GNDeploy\Tools\7z.exe","$env:SystemDrive\GNDeploy\PortableTools\7Zip\7z.exe") | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
                if(-not $seven){throw 'No se encontro 7-Zip para extraer la imagen de la ISO.'}
                $folder=Join-Path $cache ([IO.Path]::GetFileNameWithoutExtension($r.FileName)+'-'+[guid]::NewGuid().ToString('N'))
                & $seven x $path 'sources/install.wim' 'sources/install.esd' "-o$folder" -y | Out-Null
                if($LASTEXITCODE -ne 0){throw 'No se pudo extraer el WIM/ESD de la ISO.'}
                $path=@(Get-ChildItem -LiteralPath "$folder\sources" -File | Where-Object Extension -in @('.wim','.esd'))
                if($path.Count -ne 1){throw 'La ISO no contiene una imagen instalable unica.'}
                $path=$path[0].FullName
            }
            [pscustomobject]@{Success=$true;Path=$path}
        }catch{[pscustomobject]@{Success=$false;Message=$_.Exception.Message;Record=$r;Cache=$cache;Legacy=$legacy}}
    } @($Record,$Cache,$Legacy) {
        param($data)$result=$data[-1]
        if($result.Success){GN-LoadImage $result.Path;return}
        if(-not $result.Legacy -and ([uri]$result.Record.Uri).Host -eq 'dl.delivery.mp.microsoft.com'){
            $answer=if($VerifyGuest){'Yes'}else{[Windows.Forms.MessageBox]::Show($script:Ui.Form,"HTTPS no completo la descarga: $($result.Message)`r`n`r`nReintentar por el enlace HTTP historico de Microsoft, verificando hash y tamano del catalogo?",'Descarga Microsoft','YesNo','Warning','Button2')}
            if($answer -eq 'Yes'){GN-Download $result.Record $result.Cache $true;return}
        }
        $script:State.LastFailedDownload=@{Record=$result.Record;Cache=$result.Cache;Legacy=$result.Legacy}
        GN-Error $result.Message
    }
}

$form=New-Object Windows.Forms.Form;$script:Ui.Form=$form
$form.Text='GNDeploy | Despliegue Windows';$form.AutoScaleMode='None';$form.ClientSize=New-Object Drawing.Size(980,680);$form.MinimumSize=New-Object Drawing.Size(996,719);$form.StartPosition='CenterScreen';$form.Font=New-Object Drawing.Font($script:Ui.FontFamily,10);$form.BackColor=[Drawing.Color]::FromArgb(241,245,250)
$header=GN-Label $form 'GNDeploy' 20 12 300;$header.Font=New-Object Drawing.Font($script:Ui.FontFamily,22,[Drawing.FontStyle]::Bold);$header.Height=42
$script:Ui.StepTitle=GN-Label $form 'Asistente de instalacion' 22 58 620
$keyboard=GN-Label $form 'Teclado: English (US)' 735 25 225;$keyboard.ForeColor=[Drawing.Color]::FromArgb(20,90,155)
$script:Ui.Console=GN-Button $form 'Abrir CMD' 735 55 225 {
    if($script:State.Preview){$script:Ui.Status.Text='Vista previa: CMD solo se abre en WinPE/WinRE.';return}
    if(-not(Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')){throw 'La consola de soporte se abre dentro de WinPE/WinRE.'}
    Start-Process "$env:SystemRoot\System32\cmd.exe" -ArgumentList '/k title GNDeploy - Consola de soporte' -WindowStyle Normal
}
$script:Ui.Summary=GN-Label $form '' 22 88 930;$script:Ui.Summary.Height=48
$brand=New-Object Windows.Forms.Panel;$brand.SetBounds(0,0,980,136);$brand.Anchor='Top,Left,Right';$brand.BackColor=[Drawing.Color]::FromArgb(18,35,58);$form.Controls.Add($brand);$brand.SendToBack()
foreach($headerControl in @($form.Controls | Where-Object {$_.Top -lt 136 -and $_ -ne $brand})){$brand.Controls.Add($headerControl);if($headerControl -is [Windows.Forms.Label]){$headerControl.ForeColor=[Drawing.Color]::White;$headerControl.BackColor=$brand.BackColor}}
$keyboard.ForeColor=[Drawing.Color]::FromArgb(139,209,240)
$tabs=New-Object Windows.Forms.TabControl;$tabs.SetBounds(18,140,944,465);$tabs.Anchor='Top,Bottom,Left,Right';$form.Controls.Add($tabs);$script:Ui.Tabs=$tabs
foreach($name in @('Windows','Drivers','Autopilot','Red / Wi-Fi','Instalar','Equipo','Herramientas')){$p=New-Object Windows.Forms.TabPage;$p.Text=$name;$p.BackColor=[Drawing.Color]::White;$null=$tabs.TabPages.Add($p)}
$tabs.Padding=New-Object Drawing.Point(14,5)
$w=$tabs.TabPages[0];$script:Ui.WindowsTab=$w
$null=GN-Label $w 'Imagen incluida o local' 14 10 260
$script:Ui.Local=GN-Combo $w 14 39 600 @('Seleccione una imagen incluida...')
$null=GN-Button $w 'Abrir WIM / ESD...' 626 37 160 { $path=GN-File 'Imagen Windows (*.wim;*.esd)|*.wim;*.esd';GN-LoadImage $path }
$null=GN-Button $w 'Leer imagen' 795 37 120 {if($script:Ui.Local.SelectedIndex -lt 1){throw 'Seleccione una imagen incluida o abra un archivo.'};GN-LoadImage $script:State.Images[$script:Ui.Local.SelectedIndex-1].FullName}
$script:Ui.Editions=GN-List $w 14 82 900 94 @(@('Indice',60),@('Edicion de Windows',400),@('Edition ID',220),@('Version',180))
$script:Ui.UseEdition=GN-Button $w 'Usar edicion' 775 182 140 {$r=GN-Selected $script:Ui.Editions 'Seleccione una edicion de Windows.';$script:State.Index=[int]$r.Index;$script:State.ImageName=$r.Name;$script:State.Edition=$r.Edition;$script:State.ImageVersion=[string]$r.Version;GN-Summary;if($script:State.ContainsKey('Hardware')){GN-ShowHardware $script:State.Hardware};$script:Ui.Status.Text="Edicion elegida: $($r.Name). Elija drivers o continue sin drivers adicionales.";$script:Ui.Tabs.SelectedIndex=1}
$null=GN-Label $w 'Descargar desde Microsoft' 14 187 600
$script:Ui.Language=GN-Combo $w 14 219 120 @('en-us','es-es','es-mx','Todos')
$script:Ui.Search=GN-Text $w 146 219 510
$script:Ui.Search.Add_TextChanged({GN-FilterCatalog});$script:Ui.Language.Add_SelectedIndexChanged({GN-FilterCatalog})
$script:Ui.LoadCatalog=GN-Button $w 'Cargar catalogos' 670 217 244 {
    $files=@(GN-Media | ForEach-Object {Get-ChildItem "$_\Catalogs\*" -File -ErrorAction SilentlyContinue | Where-Object {$_.Extension -eq '.xml' -or $_.Name -like '*.media.json'}} | Select-Object -ExpandProperty FullName)
    if(-not $files){throw 'No se encontraron catalogos Microsoft en los medios.'}
    GN-Task 'Leyendo catalogos Microsoft...' {param($files) foreach($file in $files){foreach($lang in @('en-us','es-es','es-mx')){Get-GNWindowsCatalog -Path $file -Language $lang}}} @(,$files) {param($rows) $script:State.Catalog=@($rows | Sort-Object FileName,Edition -Unique);GN-FilterCatalog}
}
$script:Ui.Search.Text='';$script:Ui.Search.AccessibleName='Filtrar por edicion o nombre de imagen'
$script:Ui.Catalog=GN-List $w 14 260 900 100 @(@('Familia / edicion',310),@('Idioma',100),@('Arquitectura',110),@('Tamano',115),@('Build',190))
$script:Ui.CatalogCount=GN-Label $w 'Filtre por idioma y escriba Pro, Enterprise u otra edicion en el cuadro de busqueda.' 14 364 900
$script:Ui.Cache=GN-Text $w 14 395 525
$null=GN-Button $w 'Carpeta cache...' 549 392 175 {$folder=GN-Folder 'Carpeta cache en USB o segundo disco, distinta al disco destino';if($folder){$script:Ui.Cache.Text=$folder}}
$script:Ui.Download=GN-Button $w 'Descargar seleccion' 734 392 180 {
    $record=GN-Selected $script:Ui.Catalog 'Seleccione una fila del catalogo.'
    if($record.Acquisition -eq 'Unavailable'){[Windows.Forms.MessageBox]::Show($script:Ui.Form,$record.Notes,'Disponibilidad del medio','OK','Information') | Out-Null;return}
    if($record.Acquisition -eq 'LicensedMedia'){
        [Windows.Forms.MessageBox]::Show($script:Ui.Form,$record.Notes,'Importar medio LTSC','OK','Information') | Out-Null
        $path=GN-File 'Imagen licenciada (*.wim;*.esd)|*.wim;*.esd';if($path){GN-LoadImage $path};return
    }
    $cache=$script:Ui.Cache.Text.Trim();if(-not $cache){throw 'Elija una carpeta cache en USB o segundo disco antes de descargar.'}
    $script:State.Index=$null
    GN-Download $record $cache
}
$script:Ui.Download.Enabled=$false
$script:Ui.Cache.Add_TextChanged({GN-DownloadState})
$script:Ui.Catalog.Add_SelectedIndexChanged({GN-DownloadState})

$d=$tabs.TabPages[1]
$null=GN-Label $d 'Drivers: seleccione una carpeta INF o descargue el pack del modelo detectado.' 18 18
$script:Ui.Driver=GN-Text $d 18 58 690
$null=GN-Button $d 'Examinar...' 720 56 185 {$folder=GN-Folder 'Carpeta de drivers INF';if($folder){$script:Ui.Driver.Text=$folder}}
$script:Ui.OfflineDrivers=GN-Combo $d 18 101 690 @('Packs incluidos en el medio...')
$null=GN-Button $d 'Usar pack incluido' 720 99 185 {if($script:Ui.OfflineDrivers.SelectedIndex -lt 1){throw 'Seleccione un pack incluido.'};$script:Ui.Driver.Text=$script:State.OfflineDrivers[$script:Ui.OfflineDrivers.SelectedIndex-1].FullName}
$script:Ui.ValidateDrivers=GN-Button $d 'Validar y usar carpeta' 18 147 250 {
    $path=$script:Ui.Driver.Text.Trim();if(-not $path){throw 'Seleccione una carpeta de drivers.'}
    GN-Task 'Comprobando archivos INF...' {param($path) if(-not(Get-ChildItem -LiteralPath $path -Filter *.inf -Recurse | Select-Object -First 1)){throw 'La carpeta no contiene archivos INF.'};(Resolve-Path -LiteralPath $path).Path} @($path) {param($paths)$script:State.DriverPath=[string]$paths[-1];GN-Summary;$script:Ui.Status.Text='Drivers seleccionados.'}
}
$null=GN-Button $d 'Sin drivers adicionales' 283 147 250 {$script:State.DriverPath=$null;$script:Ui.Driver.Clear();GN-Summary}
$null=GN-Label $d 'Descarga automatica por hardware: Lenovo, Dell o HP' 18 215
$null=GN-Label $d 'Windows destino' 18 250 180
$script:Ui.Release=GN-Combo $d 200 247 200 @('24H2','25H2')
$null=GN-Button $d 'Detectar y descargar drivers' 18 300 335 {
    if($script:State.ImageVersion -match '^6\.1\.' -or ($script:State.ImageVersion -match '^10\.0\.' -and ([version]$script:State.ImageVersion).Build -lt 22000)) {throw 'Para Windows 7 o 10 seleccione su pack INF especifico. La descarga OEM automatica actual corresponde a Windows 11.'}
    $cache=$script:Ui.Cache.Text.Trim();if(-not $cache){throw 'Elija primero la carpeta cache en la pestana Windows.'}
    GN-Task 'Detectando hardware y descargando drivers OEM...' {param($cache,$release,$tools)
        $i=Get-GNInventory;$cat=Join-Path $cache ('oem-'+(Get-Date -Format yyyyMMddHHmmss)+'.xml')
        if($i.Manufacturer -match 'Lenovo'){
            $null=Save-GNDownload -Uri 'https://download.lenovo.com/cdrt/td/catalogv2.xml' -Destination $cat
            $pack=Get-GNLenovoDriverPack -CatalogPath $cat -MachineType $i.Model.Substring(0,4) -Release $release | Sort-Object Date -Descending | Select-Object -First 1
            if(-not $pack){throw 'No hay pack Lenovo exacto para este modelo y release.'}
            Save-GNLenovoDriverPack -Pack $pack -CacheRoot $cache -Extractor "$tools\innoextract.exe"
        }elseif($i.Manufacturer -match 'Dell|HP|Hewlett'){
            $maker='HP';$id=$i.BoardProduct;$uri='https://hpia.hpcloud.hp.com/downloads/driverpackcatalog/HPClientDriverPackCatalog.cab'
            if($i.Manufacturer -match 'Dell'){$maker='Dell';$id=$i.SKU;$uri='https://downloads.dell.com/catalog/DriverPackCatalog.cab'}
            $null=Save-GNDownload -Uri $uri -Destination "$cat.cab";& expand.exe "$cat.cab" $cat | Out-Null;if($LASTEXITCODE){throw 'No se pudo extraer el catalogo OEM.'}
            $pack=Get-GNOemDriverPack -Manufacturer $maker -CatalogPath $cat -SystemId $id -Release $release | Sort-Object Date -Descending | Select-Object -First 1
            if(-not $pack){throw 'No hay pack OEM exacto para el equipo.'};Save-GNOemDriverPack -Pack $pack -CacheRoot $cache -Extractor "$tools\7z.exe"
        }else{throw 'Fabricante sin proveedor automatico; seleccione una carpeta INF.'}
    } @($cache,$script:Ui.Release.Text,"$PSScriptRoot\Tools") {param($paths)$script:State.DriverPath=[string]$paths[-1];$script:Ui.Driver.Text=$script:State.DriverPath;GN-Summary}
}
$null=GN-Label $d 'El cache y los drivers deben estar fuera del disco que se va a borrar.' 18 355
$null=GN-Button $d 'Continuar: perfil Autopilot' 570 389 335 {$script:Ui.Tabs.SelectedIndex=2}

$a=$tabs.TabPages[2]
$null=GN-Label $a 'Seleccione el JSON de Autopilot. Se aplicara offline al Windows instalado.' 18 18
$script:Ui.Profiles=GN-List $a 18 55 885 220 @(@('Perfil',240),@('Organizacion / tenant',300),@('Tenant ID',320))
$null=GN-Button $a 'Abrir JSON...' 18 300 200 {$path=GN-File 'Perfil Autopilot (*.json)|*.json';if($path){$p=Get-GNAutopilotProfile $path;GN-Row $script:Ui.Profiles @($p.Name,$p.TenantDomain,$p.TenantId) $p}}
$script:Ui.UseProfile=GN-Button $a 'Usar perfil seleccionado' 235 300 260 {$p=GN-Selected $script:Ui.Profiles 'Seleccione un perfil de Autopilot.';$script:State.Profile=$p;GN-Summary;$script:Ui.Status.Text="Autopilot: $($p.TenantDomain)"}
$script:Ui.ClearProfile=GN-Button $a 'Sin Autopilot' 510 300 200 {$script:State.Profile=$null;GN-Summary}
$null=GN-Label $a 'El perfil elegido se muestra en el resumen antes de confirmar el despliegue.' 18 365
$null=GN-Button $a 'Continuar: elegir disco e instalar' 570 395 335 {$script:Ui.Tabs.SelectedIndex=4;$script:Ui.RefreshDisks.PerformClick()}

$n=$tabs.TabPages[3]
$script:Ui.Network=GN-Text $n 18 16 885;$script:Ui.Network.Multiline=$true;$script:Ui.Network.ReadOnly=$true;$script:Ui.Network.ScrollBars='Vertical';$script:Ui.Network.Height=72
$script:Ui.CheckNetwork=GN-Button $n 'Comprobar conexion' 18 101 225 {GN-Task 'Comprobando direccion IP y HTTPS...' {Get-GNNetworkStatus | Format-List | Out-String} @() {param($data)$script:Ui.Network.Text=$data -join "`r`n"}}
$script:Ui.ScanWifi=GN-Button $n 'Actualizar redes Wi-Fi' 260 101 255 {
    GN-Task 'Buscando redes Wi-Fi...' {Get-GNWifiNetwork | Sort-Object Signal -Descending | Sort-Object SSID,InterfaceId -Unique} @() {
        param($data)$script:Ui.Wifi.Items.Clear()
        foreach($network in $data){GN-Row $script:Ui.Wifi @($network.SSID,([string]$network.Signal+' %'),$network.Security,$(if($network.Connected){'Conectada'}else{'Disponible'})) $network}
        $script:Ui.Network.Text=if($data.Count){'Seleccione su red y pulse Conectar. La contrasena se solicita en una ventana.'}else{'No hay redes disponibles. Revise el adaptador WLAN y sus drivers, o use una conexion Ethernet.'}
    }
}
$script:Ui.Wifi=GN-List $n 18 150 885 170 @(@('Red Wi-Fi',350),@('Senal',100),@('Seguridad',230),@('Estado',170))
$script:Ui.ConnectWifi=GN-Button $n 'Conectar a la red seleccionada' 18 335 330 {
    $network=GN-Selected $script:Ui.Wifi 'Seleccione una red Wi-Fi de la lista.'
    if(-not $network.Supported){throw 'Esta red empresarial requiere un perfil WLAN XML con su metodo de autenticacion.'}
    $password=$null
    if($network.Security -ne 'Abierta'){$password=GN-RequestWifiPassword $network;if($null -eq $password){return}}
    $auth=if($network.Security -eq 'WPA3 Personal'){'WPA3SAE'}else{'WPA2PSK'}
    GN-Task ('Conectando a '+$network.SSID+'...') {param($ssid,$password,$open,$auth,$adapter)
        if($open){Connect-GNWifi -SSID $ssid -Open -InterfaceName $adapter | Format-List | Out-String}else{Connect-GNWifi -SSID $ssid -Password $password -Authentication $auth -InterfaceName $adapter | Format-List | Out-String}
    } @($network.SSID,$password,($network.Security -eq 'Abierta'),$auth,$network.InterfaceName) {param($data)$script:Ui.Network.Text=$data -join "`r`n"}
}
$null=GN-Button $n 'Importar perfil WLAN XML' 365 335 260 {$path=GN-File 'Perfil WLAN (*.xml)|*.xml';if($path){GN-Task 'Aplicando perfil WLAN...' {param($path) Connect-GNWifi -ProfilePath $path | Format-List | Out-String} @($path) {param($data)$script:Ui.Network.Text=$data -join "`r`n"}}}
$null=GN-Button $n 'Exportar diagnostico...' 18 385 280 {$folder=GN-Folder 'Destino de diagnostico';if($folder){GN-Task 'Exportando diagnostico...' {param($folder) Export-GNDiagnostics -Destination $folder} @($folder) {param($data)$script:Ui.Status.Text="Diagnostico: $($data[-1])"}}}

$equipment=$tabs.TabPages[5]
$null=GN-Label $equipment 'Hardware detectado y comprobaciones locales de Autopilot' 18 15 700
$script:Ui.Hardware=GN-List $equipment 18 48 885 152 @(@('Dato',190),@('Valor',650))
$script:Ui.Readiness=GN-List $equipment 18 251 885 163 @(@('Comprobacion',215),@('Estado',130),@('Detalle',510))
function GN-ShowHardware($hardware){
    $script:State.Hardware=$hardware;$script:Ui.Hardware.Items.Clear()
    foreach($row in @(@('Equipo',($hardware.Manufacturer+' '+$hardware.Model+' '+$hardware.ProductName)),@('Serie',$hardware.Serial),@('CPU',$hardware.CPU),@('RAM / CPU',("{0} GB / {1} nucleos / {2} hilos" -f $hardware.MemoryGB,$hardware.Cores,$hardware.LogicalProcessors)),@('Discos',(($hardware.Disks | ForEach-Object {'{0}: {1} ({2:N0} GB, {3})' -f $_.Number,$_.FriendlyName,($_.Size/1GB),$_.BusType}) -join '; ')),@('Firmware / TPM',($hardware.Firmware+' / TPM '+$hardware.TPMVersion)))){GN-Row $script:Ui.Hardware $row $null}
    $edition=$null;if($script:State.ContainsKey('Edition')){$edition=$script:State.Edition}
    $script:Ui.Readiness.Items.Clear();foreach($row in Get-GNAutopilotReadiness -Hardware $hardware -Edition $edition -ImageVersion $script:State.ImageVersion){GN-Row $script:Ui.Readiness @($row.Check,$row.Status,$row.Detail) $row}
}
$script:Ui.RefreshHardware=GN-Button $equipment 'Actualizar hardware' 18 210 230 {GN-Task 'Consultando CPU, RAM, discos, firmware y TPM...' {Get-GNHardwareStatus} @() {param($data)GN-ShowHardware $data[-1]}}
$null=GN-Label $equipment 'La compatibilidad completa requiere validar tambien red, tenant y licencias.' 267 215 630

$toolsPage=$tabs.TabPages[6]
$null=GN-Label $toolsPage 'Herramientas x64 incluidas y agregadas en GNDeploy\Tools de la USB.' 18 14 885
$script:Ui.Tools=GN-List $toolsPage 18 45 885 95 @(@('Herramienta',200),@('Ubicacion',660))
$script:Ui.RefreshTools=GN-Button $toolsPage 'Actualizar lista' 18 150 205 {GN-RefreshTools}
$script:Ui.OpenTool=GN-Button $toolsPage 'Abrir seleccionada' 240 150 215 {$path=GN-Selected $script:Ui.Tools 'Seleccione una herramienta.';$null=GN-LaunchTool $path}
$null=GN-Button $toolsPage 'Editor / logs' 472 150 205 {$editor=GN-NewTextEditor;try{$null=$editor.Form.ShowDialog($script:Ui.Form)}finally{$editor.Form.Dispose()}}
$null=GN-Button $toolsPage 'Procesos' 694 150 205 {GN-ShowProcesses}
$script:Ui.UtilityKind=GN-Combo $toolsPage 18 203 245 @('Unidades y espacio libre','Dispositivos con problemas','Configuracion de red','Exportar diagnostico completo')
$script:Ui.UtilityRun=GN-Button $toolsPage 'Consultar' 280 201 175 {GN-RunUtilityInventory}
$script:Ui.UtilityHash=GN-Button $toolsPage 'Verificar SHA-256...' 472 201 205 {GN-ShowFileIntegrity}
$script:Ui.UtilityDriver=GN-Button $toolsPage 'Cargar driver INF...' 694 201 205 {GN-LoadSessionDriver}
$script:Ui.UtilityOutput=GN-Text $toolsPage 18 245 885 'Seleccione una utilidad. Las consultas de unidades, dispositivos y red no modifican el equipo.'
$script:Ui.UtilityOutput.Multiline=$true;$script:Ui.UtilityOutput.ReadOnly=$true;$script:Ui.UtilityOutput.ScrollBars='Both';$script:Ui.UtilityOutput.WordWrap=$false;$script:Ui.UtilityOutput.Height=128
$null=GN-Button $toolsPage 'Guardar resultado...' 18 387 240 {GN-SaveUtilityReport}
$null=GN-Button $toolsPage 'Consola CMD' 275 387 240 {$script:Ui.Console.PerformClick()}
GN-RefreshTools

$p=$tabs.TabPages[4]
$null=GN-Label $p '1. Elija donde instalar Windows. Identifique el disco por su modelo y capacidad.' 18 14
$script:Ui.Disks=GN-List $p 18 47 885 85 @(@('Disco / modelo',325),@('Capacidad',120),@('Conexion',100),@('Identificador',240),@('Nro.',65))
$script:Ui.RefreshDisks=GN-Button $p 'Actualizar discos' 18 140 220 {GN-Task 'Consultando discos permitidos...' {foreach($disk in Get-GNTargetDisk){$summary='No se pudo leer el inventario';try{$parts=@(Get-Partition -DiskNumber $disk.Number -ErrorAction Stop);$summary=if($parts.Count){($parts | ForEach-Object {'{0} ({1:N1} GB)' -f $_.Type,($_.Size/1GB)}) -join ', '}else{'Disco sin particiones'}}catch{};$disk | Add-Member NoteProperty PartitionSummary $summary -Force -PassThru}} @() {param($rows)$script:Ui.Disks.Items.Clear();foreach($r in $rows){GN-Row $script:Ui.Disks @($r.FriendlyName,('{0:N0} GB' -f ($r.Size/1GB)),$r.BusType,$r.UniqueId,$r.Number) $r}}}
$script:Ui.Disks.Add_SelectedIndexChanged({GN-InvalidatePlan})
$null=GN-Label $p 'Registro de instalacion (opcional). Se guardara tambien en el Windows instalado.' 18 184
$script:Ui.Logs=GN-Text $p 18 211 640
$null=GN-Button $p 'Examinar...' 680 209 220 {$folder=GN-Folder 'Carpeta persistente de logs';if($folder){$script:Ui.Logs.Text=$folder}}
$script:Ui.ReviewPlan=GN-Button $p '2. Preparar instalacion' 18 252 220 {
    GN-InvalidatePlan
    if(-not $script:State.ImagePath -or -not $script:State.Index){throw 'Elija una imagen y pulse Usar edicion en la pestana Windows.'}
    $disk=GN-Selected $script:Ui.Disks 'Seleccione un disco destino.';$logs=$script:Ui.Logs.Text.Trim();if(-not $logs){$logs='X:\GNDeploy\Logs'}
    $profile=$null;if($script:State.Profile){$profile=$script:State.Profile.Path}
    $mode='UEFI';if($script:State.Hardware -and $script:State.Hardware.Firmware -eq 'BIOS'){$mode='BIOS'}
    GN-Task 'Validando plan y hash de la imagen...' {param($disk,$image,$index,$drivers,$profile,$logs,$mode) New-GNDeploymentPlan -DiskNumber $disk -ImagePath $image -ImageIndex $index -DriverPath $drivers -AutopilotProfile $profile -LogRoot $logs -FirmwareMode $mode} @($disk.Number,$script:State.ImagePath,$script:State.Index,$script:State.DriverPath,$profile,$logs,$mode) {
        param($data)$script:State.Plan=$data[-1];$plan=$script:State.Plan;$tenant='Sin Autopilot';if($plan.AutopilotProfile){$tenant=$plan.AutopilotProfile.TenantDomain}
        if(-not $VerifyGuest -and -not $Preview -and -not (GN-ReviewChecklist $plan)){GN-InvalidatePlan;return}
        $script:Ui.Plan.Text="Destino: $($plan.DiskName) - $([math]::Round($plan.DiskSize/1GB)) GB`r`nWindows: $($plan.ImageName)`r`nAutopilot: $tenant | Arranque: $($plan.FirmwareMode)"
        $script:Ui.Status.Text="Revise el destino y la edicion. Marque la casilla para habilitar la instalacion."
    }
}
$script:Ui.Plan=GN-Label $p 'Revise la imagen, el disco y el tenant antes de confirmar.' 255 251 640;$script:Ui.Plan.Height=62
$script:Ui.Plan.Height=80
$script:Ui.Confirm=New-Object Windows.Forms.CheckBox
$script:Ui.Confirm.Text='Entiendo que se eliminaran todos los archivos del disco seleccionado.'
$script:Ui.Confirm.SetBounds(18,338,885,30);$p.Controls.Add($script:Ui.Confirm)
$script:Ui.Deploy=GN-Button $p '3. Instalar Windows en el disco seleccionado' 18 380 885 {
    if($VerifyGuest){throw 'La prueba de menus prohibe instalar Windows.'}
    $plan=$script:State.Plan;if(-not $plan -or -not $script:Ui.Confirm.Checked){throw 'Prepare la instalacion y confirme que se borrara el disco elegido.'}
    $destination="$($plan.DiskName) - $([math]::Round($plan.DiskSize/1GB)) GB"
    $message="Instalar $($plan.ImageName) en:`r`n$destination`r`nIdentificador: $($plan.DiskUniqueId)`r`n`r`nSe eliminaran TODOS los archivos y particiones de este disco.`r`n$($plan.CompatibilityNotes)`r`n`r`nDesea borrar este disco e instalar Windows?"
    if([Windows.Forms.MessageBox]::Show($script:Ui.Form,$message,'Confirmar instalacion y borrado','YesNo','Warning','Button2') -ne 'Yes'){return}
    $script:Ui.Confirm.Checked=$false
    $script:State.CompletedPlan=$plan
    GN-Task 'Instalando Windows. No retire los medios ni apague el equipo...' {param($plan) Invoke-GNDeployment -Plan $plan -Confirmation ("BORRAR $($plan.DiskNumber)") -Confirm:$false} @($plan) {
        param($data)$result=$data[-1];$script:State.Plan=$null;$script:Ui.Deploy.Enabled=$false;$script:Ui.Confirm.Checked=$false
        if($result.State -eq 'Succeeded'){GN-ShowCompletion $result $script:State.CompletedPlan}
    }
}
$script:Ui.Confirm.Add_CheckedChanged({$script:Ui.Deploy.Enabled=($null -ne $script:State.Plan -and $script:Ui.Confirm.Checked -and -not $script:State.Preview -and -not $VerifyGuest)})
$script:Ui.Logs.Add_TextChanged({GN-InvalidatePlan})
$script:Ui.Progress=New-Object Windows.Forms.ProgressBar;$script:Ui.Progress.SetBounds(20,614,940,12);$script:Ui.Progress.Anchor='Bottom,Left,Right';$form.Controls.Add($script:Ui.Progress)
$script:Ui.Status=GN-Label $form 'Listo. Seleccione una imagen incluida o cargue el catalogo Microsoft.' 20 637 940;$script:Ui.Status.Anchor='Bottom,Left,Right'
$timer=New-Object Windows.Forms.Timer;$timer.Interval=250;$script:Ui.Timer=$timer
$timer.Add_Tick({
    $j=$script:State.Job;if(-not $j){return}
    if(-not $j.Handle.IsCompleted){if($j.PS.Streams.Progress.Count){$pr=$j.PS.Streams.Progress[$j.PS.Streams.Progress.Count-1];$script:Ui.Status.Text=$j.Label+' '+$pr.StatusDescription;if($pr.PercentComplete -ge 0){$script:Ui.Progress.Style='Blocks';$script:Ui.Progress.Value=[math]::Min(100,[math]::Max(0,$pr.PercentComplete))}};return}
    $timer.Stop();$script:State.Job=$null;$script:Ui.Tabs.Enabled=$true;$script:Ui.Progress.Style='Blocks';GN-UpdateWizard
    try{$data=@($j.PS.EndInvoke($j.Handle));if($j.PS.HadErrors){throw ($j.PS.Streams.Error | Out-String)};$script:Ui.Status.Text='Operacion completada.';& $j.Done $data}catch{$reason=$_.Exception;while($reason.InnerException){$reason=$reason.InnerException};GN-Error $reason.Message}finally{$j.PS.Dispose()}
})
$form.Add_FormClosing({
    param($sender,$event)
    if($script:State.Job){$event.Cancel=$true;GN-Error 'Hay una operacion en curso. Espere a que termine antes de cerrar.';return}
    if(-not $script:State.Preview -and (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')){
        $event.Cancel=$true;GN-ShowExitOptions
    }
})
$form.Add_Shown({$form.Activate();if(-not $script:State.Preview){$script:Ui.Tabs.SelectedIndex=5;$script:State.Started=$true;$script:Ui.RefreshHardware.PerformClick()};GN-UpdateWizard})
Initialize-GNWorkflow
GN-Summary
if($Preview){
    $script:State.Catalog=@(
        [pscustomobject]@{Edition='Professional';Language='en-us';Architecture='x64';Size=4680320173;FileName='26100.4349_CLIENT_x64_en-us.esd'},
        [pscustomobject]@{Edition='Education';Language='en-us';Architecture='x64';Size=4680320173;FileName='26100.4349_CLIENT_x64_en-us.esd'},
        [pscustomobject]@{Edition='Professional';Language='es-es';Architecture='x64';Size=4680692940;FileName='26100.4349_CLIENT_x64_es-es.esd'})
    GN-FilterCatalog;$script:Ui.Status.Text='Vista previa: datos de ejemplo. Despliegue deshabilitado.'
}else{
    # Prefer the data partition of an existing GNDeploy USB; never use optical/RAM media.
    $cacheMedia=@(GN-Media | Where-Object {Test-Path (Join-Path $_ 'usb-manifest.json')} | Where-Object {
        try{$drive=New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($_));$drive.DriveType -notin @('CDRom','Ram','Network') -and $drive.AvailableFreeSpace -gt 6GB}catch{$false}
    })
    if($cacheMedia.Count -eq 1){$script:Ui.Cache.Text=Join-Path $cacheMedia[0] 'Cache';$script:Ui.Logs.Text=Join-Path $cacheMedia[0] 'Logs'}
    $script:State.Images=@(GN-Media | ForEach-Object {Get-ChildItem "$_\Images\*" -Include *.wim,*.esd -ErrorAction SilentlyContinue})
    foreach($file in $script:State.Images){$null=$script:Ui.Local.Items.Add($file.Name)}
    $script:State.OfflineDrivers=@(GN-Media | ForEach-Object {Get-ChildItem "$_\Drivers\Offline" -Directory -ErrorAction SilentlyContinue})
    foreach($folder in $script:State.OfflineDrivers){$null=$script:Ui.OfflineDrivers.Items.Add($folder.Name)}
    foreach($file in @(GN-Media | ForEach-Object {Get-ChildItem "$_\Autopilot\Profiles\*.json" -ErrorAction SilentlyContinue})){
        try{$profile=Get-GNAutopilotProfile $file.FullName;GN-Row $script:Ui.Profiles @($profile.Name,$profile.TenantDomain,$profile.TenantId) $profile}catch{$script:Ui.Status.Text="Perfil no valido: $($file.Name)"}
    }
}
try {
    if($VerifyToolsGuest){. (Join-Path $PSScriptRoot 'Verify-GuestTools.ps1');Invoke-GNGuestToolChecks -ReportRoot $ReportRoot}
    elseif($VerifyGuest){. (Join-Path $PSScriptRoot 'Verify-GuestMenus.ps1');Invoke-GNGuestMenuChecks -ReportRoot $ReportRoot}
    if($VerifyPreview){
        if(-not $Preview){throw 'VerifyPreview requiere Preview.'}
        $form.Show();[Windows.Forms.Application]::DoEvents()
        $script:Ui.Tabs.SelectedIndex=3;GN-UpdateWizard
        if($script:Ui.StepTitle.Text -notlike 'Paso 1 de 5*'){throw 'Paso de conexion incorrecto.'}
        $script:Ui.Next.PerformClick();[Windows.Forms.Application]::DoEvents()
        if($script:Ui.Tabs.SelectedIndex -ne 0){throw 'Siguiente no lleva a Windows.'}
        $script:Ui.Back.PerformClick();[Windows.Forms.Application]::DoEvents()
        if($script:Ui.Tabs.SelectedIndex -ne 3){throw 'Anterior no lleva a conexion.'}
        $script:Ui.Tabs.SelectedIndex=0
        if($script:Ui.Catalog.Items.Count -ne 2){throw 'Filtro inicial en-us incorrecto.'}
        $script:Ui.Language.SelectedItem='es-es';if($script:Ui.Catalog.Items.Count -ne 1){throw 'Filtro de idioma incorrecto.'}
        $script:Ui.Search.Text='Education';if($script:Ui.Catalog.Items.Count -ne 0){throw 'Filtro combinado incorrecto.'}
        $script:Ui.Search.Clear();$script:Ui.Language.SelectedItem='en-us'
        if($script:Ui.Download.Enabled -or $script:Ui.Deploy.Enabled){throw 'Accion habilitada sin seleccion o cache.'}
        $script:State.Plan=[pscustomobject]@{DiskNumber=2};$script:Ui.Confirm.Checked=$true
        if($script:Ui.Deploy.Enabled){throw 'Vista previa permite instalar.'}
        GN-InvalidatePlan
        if($script:Ui.Confirm.Checked -or $script:State.Plan){throw 'Confirmacion no se invalida al cambiar seleccion.'}
        GN-Task 'Prueba de trabajo en segundo plano...' {Get-Command Get-GNWindowsCatalog | Select-Object -ExpandProperty Name} @() {param($result)$script:State.VerifiedWorker=[string]$result[-1]}
        if($script:Ui.Next.Enabled -or $script:Ui.Back.Enabled -or $script:Ui.Restart.Enabled -or $script:Ui.Exit.Enabled){throw 'Navegacion o salida habilitada durante un trabajo.'}
        $blocked=$false;try{$null=GN-RequestPowerAction Restart}catch{$blocked=$true};if(-not $blocked){throw 'Reinicio permitido durante un trabajo.'}
        $deadline=(Get-Date).AddSeconds(20)
        while($script:State.Job -and (Get-Date) -lt $deadline){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 25}
        if($script:State.Job -or $script:State.VerifiedWorker -ne 'Get-GNWindowsCatalog'){throw 'El trabajo en segundo plano no completo la operacion.'}
        $folder=GN-NewFolderDialog 'Prueba de selector WinRE' $env:TEMP
        try{if($folder.Tree.Nodes.Count -lt 1){throw 'Selector sin unidades.'};$folder.Form.Show();[Windows.Forms.Application]::DoEvents();$folder.Accept.PerformClick();if($folder.Form.DialogResult -ne 'OK'){throw 'El selector no acepta una carpeta existente.'}}finally{$folder.Form.Dispose()}
        Write-Host 'PASS GUI: filtros idioma/busqueda, acciones protegidas y trabajo en segundo plano.'
        foreach($action in @('Restart','Shutdown')){$null=GN-RequestPowerAction $action;if($script:State.SessionActionRequested -ne $action){throw 'Accion de energia no registrada.'}}
        if($RenderPath){
            $script:State.PreviewDialogDirectory=Split-Path $RenderPath
            $fixture=[pscustomobject]@{Id='preview';DiskName='Samsung SSD 860 EVO';DiskSize=477GB;DiskUniqueId='PREVIEW';ImageName='Windows 10 Enterprise LTSC 2021';ImageVersion='10.0.19044.1';FirmwareMode='UEFI';DriverPath=$null;AutopilotProfile=$null;CompatibilityNotes='';LogRoot=$env:TEMP}
            $null=GN-ReviewChecklist $fixture
            GN-ShowCompletion ([pscustomobject]@{Id='preview';State='Succeeded'}) $fixture
            GN-Error 'No hay espacio suficiente en la carpeta cache.'
            GN-ShowExitOptions
            GN-ShowFileIntegrity
            $script:State.PreviewDialogDirectory=$null
            Write-Host 'PASS GUI: revision, resultado y error renderizados sin instalar ni reiniciar.'
        }
        $script:Ui.Status.Text='Vista previa: datos de ejemplo. Despliegue deshabilitado.'
    }
    if($RenderPath){
        if($Preview -and $RenderTab -eq 'Instalar'){
            $script:Ui.Tabs.SelectedIndex=4
            GN-Row $script:Ui.Disks @('Samsung SSD 860 EVO','477 GB','SATA','S3Z9-DEMO-1234','0') $null
            $script:Ui.Plan.Text="Destino: Samsung SSD 860 EVO - 477 GB`r`nWindows: Windows 10 Enterprise LTSC 2021`r`nAutopilot: Sin perfil | Arranque: UEFI"
        }
        if($Preview -and $RenderTab -eq 'Herramientas'){$script:Ui.Tabs.SelectedIndex=6}
        $form.Show();[Windows.Forms.Application]::DoEvents();$bitmap=New-Object Drawing.Bitmap($form.Width,$form.Height);try{$form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height)));$bitmap.Save($RenderPath,[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()};$form.Hide()
    }elseif($VerifyGuest){if(-not $ExitAfterVerification){[Windows.Forms.Application]::Run($form)}}else{$null=$form.ShowDialog()}
}finally{$timer.Dispose();$form.Dispose();$script:Ui.FontCollection.Dispose();foreach($registeredFont in $script:Ui.RegisteredFonts){$null=[GNDeployFonts]::RemoveFontResourceEx($registeredFont,16,[IntPtr]::Zero)}}









