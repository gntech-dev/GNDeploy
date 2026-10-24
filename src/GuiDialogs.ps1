function GN-NewFolderDialog([string]$Title,[string]$InitialPath='',[string[]]$FileExtensions=@()){
    $dialog=New-Object Windows.Forms.Form;$dialog.Text=$Title;$dialog.ClientSize=New-Object Drawing.Size(720,490);$dialog.StartPosition='CenterParent';$dialog.Font=$script:Ui.Form.Font;$dialog.MinimizeBox=$false;$dialog.MaximizeBox=$false
    $path=GN-Text $dialog 16 16 685 $InitialPath
    $tree=New-Object Windows.Forms.TreeView;$tree.SetBounds(16,58,685,316);$tree.HideSelection=$false;$dialog.Controls.Add($tree)
    foreach($drive in [IO.DriveInfo]::GetDrives()){
        try{if(-not $drive.IsReady){continue};$node=$tree.Nodes.Add(('{0}  {1}  ({2:N1} GB libres)' -f $drive.Name,$drive.VolumeLabel,($drive.AvailableFreeSpace/1GB)));$node.Tag=$drive.RootDirectory.FullName;$null=$node.Nodes.Add('...')}catch{}
    }
    $tree.Add_BeforeExpand({param($sender,$event) $node=$event.Node;if($node.Nodes.Count -eq 1 -and $node.Nodes[0].Text -eq '...'){$node.Nodes.Clear();foreach($folder in @(Get-ChildItem -LiteralPath ([string]$node.Tag) -Directory -ErrorAction SilentlyContinue | Where-Object Name -notin @('System Volume Information','$RECYCLE.BIN'))){$child=$node.Nodes.Add($folder.Name);$child.Tag=$folder.FullName;$null=$child.Nodes.Add('...')};$extensions=$sender.FindForm().Tag.Extensions;if($extensions.Count){foreach($file in Get-ChildItem -LiteralPath ([string]$node.Tag) -File -ErrorAction SilentlyContinue | Where-Object {'*' -in $extensions -or $_.Extension -in $extensions}){$child=$node.Nodes.Add($file.Name);$child.Tag=$file.FullName}}}})
    $tree.Add_AfterSelect({param($sender,$event)$sender.FindForm().Tag.Path.Text=[string]$event.Node.Tag})
    $tree.Add_NodeMouseDoubleClick({param($sender,$event) if($sender.FindForm().Tag.Extensions.Count -and (Test-Path -LiteralPath ([string]$event.Node.Tag) -PathType Leaf)){$sender.FindForm().Tag.Accept.PerformClick()}})
    $errorText=GN-Label $dialog 'Seleccione una carpeta o escriba una ruta. Puede crear una carpeta nueva.' 16 389 685;$errorText.Height=40
    $create=GN-Button $dialog 'Crear carpeta' 16 442 180 {
        $state=$this.FindForm().Tag
        try{if(-not [IO.Path]::IsPathRooted($state.Path.Text)){throw 'Escriba una ruta absoluta, por ejemplo E:\GNDeploy\Cache.'};$null=New-Item -ItemType Directory -Path $state.Path.Text -Force;$state.Error.Text='Carpeta creada.'}catch{$state.Error.Text=$_.Exception.Message}
    }
    $accept=GN-Button $dialog 'Usar esta carpeta' 388 442 165 {
        $state=$this.FindForm().Tag
        $kind=if($state.Extensions.Count){'Leaf'}else{'Container'}
        if(-not [IO.Path]::IsPathRooted($state.Path.Text) -or -not(Test-Path -LiteralPath $state.Path.Text -PathType $kind)){$state.Error.Text='La ruta no existe o no corresponde al tipo seleccionado.';return}
        if($state.Extensions.Count -and '*' -notin $state.Extensions -and [IO.Path]::GetExtension($state.Path.Text) -notin $state.Extensions){$state.Error.Text='Seleccione un archivo compatible: '+($state.Extensions -join ', ');return}
        $state.Form.DialogResult='OK';$state.Form.Close()
    }
    $cancel=GN-Button $dialog 'Cancelar' 566 442 135 {$this.FindForm().DialogResult='Cancel';$this.FindForm().Close()}
    if($FileExtensions.Count){$create.Visible=$false;$accept.Text='Abrir archivo';$errorText.Text='Seleccione un archivo: '+($FileExtensions -join ', ')}
    $state=@{Form=$dialog;Path=$path;Tree=$tree;Accept=$accept;Cancel=$cancel;Create=$create;Error=$errorText;Extensions=$FileExtensions};$dialog.Tag=$state;$dialog.AcceptButton=$accept;$dialog.CancelButton=$cancel
    return $state
}
function GN-RequestWifiPassword($Network){
    $dialog=New-Object Windows.Forms.Form;$dialog.Text='Conectar a Wi-Fi';$dialog.ClientSize=New-Object Drawing.Size(490,230);$dialog.StartPosition='CenterParent';$dialog.Font=$script:Ui.Form.Font;$dialog.FormBorderStyle='FixedDialog';$dialog.MinimizeBox=$false;$dialog.MaximizeBox=$false
    $name=GN-Label $dialog $Network.SSID 18 16 450;$name.Font=New-Object Drawing.Font($script:Ui.FontFamily,13,[Drawing.FontStyle]::Bold);$name.Height=34
    $null=GN-Label $dialog 'Contrasena de la red' 18 62 450
    $password=GN-Text $dialog 18 92 450;$password.UseSystemPasswordChar=$true
    $show=New-Object Windows.Forms.CheckBox;$show.Text='Mostrar contrasena';$show.SetBounds(18,129,450,26);$dialog.Controls.Add($show);$show.Add_CheckedChanged({$this.FindForm().Tag.Password.UseSystemPasswordChar=-not $this.Checked})
    $errorText=GN-Label $dialog '' 18 159 450
    $accept=GN-Button $dialog 'Conectar' 190 190 135 {$state=$this.FindForm().Tag;if($state.Password.Text.Length -lt 8 -or $state.Password.Text.Length -gt 63){$state.Error.Text='Use entre 8 y 63 caracteres.';return};$state.Form.DialogResult='OK';$state.Form.Close()}
    $cancel=GN-Button $dialog 'Cancelar' 335 190 135 {$this.FindForm().DialogResult='Cancel';$this.FindForm().Close()}
    $dialog.Tag=@{Form=$dialog;Password=$password;Error=$errorText};$dialog.AcceptButton=$accept;$dialog.CancelButton=$cancel
    try{if($dialog.ShowDialog($script:Ui.Form) -eq 'OK'){return (ConvertTo-SecureString $password.Text -AsPlainText -Force)}}finally{$password.Clear();$dialog.Dispose()}
}

