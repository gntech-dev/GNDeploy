function GN-ToolRoots {
    @((Join-Path $PSScriptRoot 'PortableTools')) + @(GN-Media | Where-Object {$_.TrimEnd('\') -ine $PSScriptRoot.TrimEnd('\')} | ForEach-Object {Join-Path $_ 'Tools'})
}
function GN-RefreshTools {
    $script:Ui.Tools.Items.Clear()
    foreach($root in GN-ToolRoots){
        if(-not(Test-Path -LiteralPath $root)){continue}
        foreach($file in Get-ChildItem -LiteralPath $root -Filter *.exe -Recurse -File -ErrorAction SilentlyContinue | Where-Object Name -notmatch '^(unins|uninstall|7zG|7z\.)'){
            GN-Row $script:Ui.Tools @($file.BaseName,$file.FullName) $file.FullName
        }
    }
}
function GN-LaunchTool([string]$Path){
    if($script:State.Job){throw 'Espere a que termine la operacion actual antes de abrir herramientas.'}
    if($script:State.Preview){$script:Ui.Status.Text='Vista previa: no se ejecutan herramientas.';return}
    if(-not(Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')){throw 'Las herramientas se ejecutan dentro de WinRE.'}
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'No se encuentra la herramienta.'}
    Start-Process -FilePath $Path -WorkingDirectory (Split-Path $Path) -WindowStyle Normal -PassThru
}
function GN-RunUtilityInventory {
    if($script:Ui.UtilityKind.SelectedIndex -eq 3){
        $folder=GN-Folder 'Guardar diagnostico completo'
        if($folder){$target=Join-Path $folder ('GNDeploy-diagnostico-'+(Get-Date -Format yyyyMMdd-HHmmss));GN-Task 'Exportando diagnostico completo...' {param($target) Export-GNDiagnostics -Destination $target} @($target) {param($data)$script:Ui.UtilityOutput.Text='Diagnostico guardado en: '+$data[-1]}}
        return
    }
    $kind=@('Volumes','Devices','Network')[$script:Ui.UtilityKind.SelectedIndex]
    GN-Task 'Consultando diagnostico...' {param($kind) @(Get-GNUtilityInventory -Kind $kind) | Format-List Name,Status,Detail | Out-String -Width 220} @($kind) {param($data)
        $text=($data -join "`r`n").Trim();$script:Ui.UtilityOutput.Text=if($text){$text}else{'Sin resultados. En dispositivos, esto significa que CIM no informa problemas; no garantiza que todos los dispositivos esten detectados.'}
    }
}
function GN-SaveUtilityReport {
    $folder=GN-Folder 'Guardar resultado de utilidad'
    if($folder){$target=Join-Path $folder ('GNDeploy-utilidad-'+(Get-Date -Format yyyyMMdd-HHmmss)+'-'+[guid]::NewGuid().ToString('N').Substring(0,6)+'.txt');[IO.File]::WriteAllText($target,$script:Ui.UtilityOutput.Text,(New-Object Text.UTF8Encoding($false)));$script:Ui.Status.Text='Resultado guardado: '+$target}
}
function GN-LoadSessionDriver {
    if($script:State.Job){throw 'Espere a que termine la operacion actual.'}
    if($Preview -or $VerifyGuest){throw 'La carga real de drivers esta desactivada en vista previa y pruebas.'}
    $path=GN-File 'Driver extraido (*.inf)|*.inf'
    if(-not $path){return}
    if([Windows.Forms.MessageBox]::Show($script:Ui.Form,"Cargar este driver en la sesion actual?`r`n$path`r`n`r`nNo se agrega automaticamente a Windows. Para ello use la pestana Drivers.",'Driver de sesion','YesNo','Question','Button2') -ne 'Yes'){return}
    GN-Task 'Cargando driver en WinPE...' {param($path) Import-GNSessionDriver -Path $path} @($path) {param($data)$script:Ui.UtilityOutput.Text=($data -join "`r`n")+"`r`nActualice hardware o vuelva a buscar Wi-Fi segun corresponda."}
}
function GN-NewIntegrityDialog {
    $d=New-Object Windows.Forms.Form;$d.Text='Verificar integridad SHA-256';$d.ClientSize=New-Object Drawing.Size(740,245);$d.Font=$script:Ui.Form.Font;$d.StartPosition='CenterParent';$d.MinimizeBox=$false;$d.MaximizeBox=$false
    $null=GN-Label $d 'Archivo (WIM, ESD, ISO o cualquier otro archivo)' 18 15 700
    $path=GN-Text $d 18 44 535
    $browse=GN-Button $d 'Examinar...' 568 42 150 {$p=GN-File 'Todos los archivos (*.*)|*.*';if($p){$this.FindForm().Tag.Path.Text=$p}}
    $null=GN-Label $d 'SHA-256 esperado (opcional). Sin referencia solo se calcula la huella.' 18 89 700
    $expected=GN-Text $d 18 118 700
    $null=GN-Button $d 'Cancelar' 18 185 210 {$this.FindForm().DialogResult='Cancel';$this.FindForm().Close()}
    $accept=GN-Button $d 'Calcular / comparar' 488 185 230 {$s=$this.FindForm().Tag;if(-not(Test-Path -LiteralPath $s.Path.Text -PathType Leaf)){GN-Error 'Seleccione un archivo existente.';return};if($s.Expected.Text.Trim() -and $s.Expected.Text.Trim() -notmatch '^[a-fA-F0-9]{64}$'){GN-Error 'El SHA-256 esperado debe tener 64 caracteres hexadecimales.';return};$s.Form.DialogResult='OK';$s.Form.Close()}
    $s=@{Form=$d;Path=$path;Expected=$expected;Accept=$accept};$d.Tag=$s;return $s
}
function GN-ShowFileIntegrity {
    if($script:State.Job){throw 'Espere a que termine la operacion actual.'}
    $s=GN-NewIntegrityDialog
    try{if(GN-RenderPreviewDialog $s.Form 'integrity-preview'){return};if($s.Form.ShowDialog($script:Ui.Form) -ne 'OK'){return};$path=$s.Path.Text;$expected=$s.Expected.Text}finally{$s.Form.Dispose()}
    GN-Task 'Calculando SHA-256; puede tardar con archivos grandes...' {param($path,$expected) Test-GNFileIntegrity -Path $path -ExpectedSha256 $expected | Format-List | Out-String -Width 220} @($path,$expected) {param($data)$script:Ui.UtilityOutput.Text=$data -join "`r`n"}
}
function GN-NewTextEditor {
    $dialog=New-Object Windows.Forms.Form;$dialog.Text='GNDeploy - Editor de texto';$dialog.ClientSize=New-Object Drawing.Size(860,560);$dialog.StartPosition='CenterParent';$dialog.Font=$script:Ui.Form.Font
    $path=GN-Text $dialog 12 12 650
    $browse=GN-Button $dialog 'Examinar...' 680 10 160 {$state=$this.FindForm().Tag;$picker=GN-NewFolderDialog 'Abrir texto / log' $state.Path.Text @('*');try{if($picker.Form.ShowDialog($state.Form) -eq 'OK'){$state.Path.Text=$picker.Path.Text;$state.Open.PerformClick()}}finally{$picker.Form.Dispose()}}
    $content=New-Object Windows.Forms.TextBox;$content.Multiline=$true;$content.ScrollBars='Both';$content.WordWrap=$false;$content.AcceptsTab=$true;$content.AcceptsReturn=$true;$content.SetBounds(12,94,830,450);$content.Anchor='Top,Bottom,Left,Right';$dialog.Controls.Add($content)
    $open=GN-Button $dialog 'Abrir archivo' 12 50 180 {$state=$this.FindForm().Tag;try{if((Get-Item -LiteralPath $state.Path.Text).Length -gt 10MB){throw 'Abra archivos de hasta 10 MB.'};$state.Content.Text=[IO.File]::ReadAllText($state.Path.Text)}catch{GN-Error $_.Exception.Message}}
    $save=GN-Button $dialog 'Guardar como...' 206 50 180 {$state=$this.FindForm().Tag;try{if(-not [IO.Path]::IsPathRooted($state.Path.Text)){throw 'Escriba una ruta absoluta.'};if(Test-Path -LiteralPath $state.Path.Text){if([Windows.Forms.MessageBox]::Show($state.Form,'Reemplazar el archivo existente?','Guardar','YesNo','Question') -ne 'Yes'){return}};[IO.File]::WriteAllText($state.Path.Text,$state.Content.Text,(New-Object Text.UTF8Encoding($false)))}catch{GN-Error $_.Exception.Message}}
    $null=GN-Label $dialog 'Ruta completa; guardado UTF-8 sin BOM.' 405 55 430
    $state=@{Form=$dialog;Path=$path;Content=$content;Open=$open;Save=$save};$dialog.Tag=$state;return $state
}
function GN-ShowProcesses {
    $dialog=New-Object Windows.Forms.Form;$dialog.Text='GNDeploy - Procesos';$dialog.ClientSize=New-Object Drawing.Size(720,450);$dialog.Font=$script:Ui.Form.Font;$dialog.StartPosition='CenterParent'
    $list=GN-List $dialog 12 12 696 425 @(@('PID',90),@('Proceso',380),@('RAM MB',180))
    foreach($process in Get-Process | Sort-Object ProcessName){GN-Row $list @($process.Id,$process.ProcessName,('{0:N1}' -f ($process.WorkingSet64/1MB))) $null}
    try{$null=$dialog.ShowDialog($script:Ui.Form)}finally{$dialog.Dispose()}
}

