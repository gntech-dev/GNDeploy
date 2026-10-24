# GUI workflow helpers; loaded after GuiDialogs, before controls are created.
function GN-RenderPreviewDialog($Dialog,[string]$Name){
    if(-not $Preview -or -not $script:State.PreviewDialogDirectory){return $false}
    $Dialog.Show();[Windows.Forms.Application]::DoEvents()
    $bitmap=New-Object Drawing.Bitmap($Dialog.Width,$Dialog.Height)
    try{$Dialog.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$Dialog.Width,$Dialog.Height)));$bitmap.Save((Join-Path $script:State.PreviewDialogDirectory ($Name+'.png')),[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose();$Dialog.Hide()}
    return $true
}
function GN-Error([string]$Text){
    $script:Ui.Status.Text='No se pudo completar la operacion. Revise el mensaje y vuelva a intentarlo.'
    $script:State.LastError=$Text
    if($VerifyGuest){return}
    $hint=switch -Regex ($Text){
        'cache|carpeta|espacio|disco lleno|root folder' {'Elija una carpeta en la USB o en un segundo disco con espacio suficiente.';break}
        'curl|HTTPS|HTTP|descarga|SHA|hash|Range' {'Compruebe la conexion. Puede reintentar la descarga; se conserva el progreso valido y se verifica la integridad.';break}
        'driver|INF|WLAN|Wi-Fi' {'Seleccione drivers adecuados para el modelo y la version de Windows. Si no hay Wi-Fi, puede usar Ethernet.';break}
        'perfil|tenant|Autopilot' {'Revise el JSON y la edicion de Windows, o seleccione Sin Autopilot.';break}
        'disco|particion|DiskPart' {'Actualice la lista y revise el disco elegido. No reintente una instalacion sin revisar antes los registros.';break}
        default {'Revise los detalles. Puede guardar un informe para diagnosticar el problema.'}
    }
    $d=New-Object Windows.Forms.Form;$d.Text='Necesitamos revisar un paso';$d.ClientSize=New-Object Drawing.Size(720,400);$d.Font=$script:Ui.Form.Font;$d.StartPosition='CenterParent';$d.MinimizeBox=$false;$d.MaximizeBox=$false
    $title=GN-Label $d $hint 18 18 680;$title.Height=64
    $details=GN-Text $d 18 94 680 $Text;$details.Multiline=$true;$details.ReadOnly=$true;$details.ScrollBars='Both';$details.Height=224;$details.Visible=$false
    $toggle=GN-Button $d 'Mostrar / ocultar detalles' 18 340 210 {$dialog=$this.FindForm();$box=$dialog.Tag.Details;$box.Visible=-not $box.Visible;$dialog.ClientSize=New-Object Drawing.Size(720,$(if($box.Visible){400}else{180}));foreach($button in $dialog.Tag.Buttons){$button.Top=if($box.Visible){340}else{120}}}
    $save=GN-Button $d 'Guardar informe...' 242 340 200 {
        $folder=GN-Folder 'Guardar informe del problema'
        if($folder){$report=@{Error=$script:State.LastError;Image=$script:State.ImagePath;Version=$script:State.ImageVersion;Time=(Get-Date).ToString('o')};$target=Join-Path $folder ('GNDeploy-error-'+(Get-Date -Format yyyyMMdd-HHmmss)+'.json');$report | ConvertTo-Json | Set-Content -LiteralPath $target -Encoding UTF8}
    }
    $retry=GN-Button $d 'Reintentar descarga' 456 340 240 {$this.FindForm().DialogResult='Retry';$this.FindForm().Close()}
    $retry.Enabled=($null -ne $script:State.LastFailedDownload)
    $d.Tag=@{Details=$details;Buttons=@($toggle,$save,$retry)}
    $d.ClientSize=New-Object Drawing.Size(720,180);foreach($button in $d.Tag.Buttons){$button.Top=120}
    if(GN-RenderPreviewDialog $d 'error-preview'){$d.Dispose();return}
    try{$result=$d.ShowDialog($script:Ui.Form)}finally{$d.Dispose()}
    if($result -eq 'Retry' -and $script:State.LastFailedDownload){$r=$script:State.LastFailedDownload;GN-Download $r.Record $r.Cache $r.Legacy}
}
function GN-UpdateWizard {
    if(-not $script:Ui.ContainsKey('Next')){return}
    $order=@(3,0,1,2,4);$names=@('Conexion','Windows','Drivers','Autopilot','Revision e instalacion')
    $position=[array]::IndexOf($order,$script:Ui.Tabs.SelectedIndex)
    $script:Ui.Back.Enabled=$position -gt 0 -and -not $script:State.Job
    $script:Ui.Next.Enabled=$position -lt 4 -and -not $script:State.Job
    $script:Ui.StepTitle.Text=if($position -ge 0){'Paso '+($position+1)+' de 5: '+$names[$position]}else{'Informacion y herramientas de soporte'}
    $script:Ui.Next.Text=if($position -lt 0){'Comenzar'}else{'Siguiente >'}
    if($script:Ui.ContainsKey('Restart')){$script:Ui.Restart.Enabled=-not $script:State.Job;$script:Ui.Exit.Enabled=-not $script:State.Job}
    if($script:Ui.ContainsKey('StepChips')){foreach($i in 0..4){$chip=$script:Ui.StepChips[$i];$chip.BackColor=if($i -eq $position){[Drawing.Color]::FromArgb(40,160,191)}else{[Drawing.Color]::FromArgb(38,58,82)};$chip.ForeColor=[Drawing.Color]::White}}
    if($script:State.Started -and $script:Ui.Tabs.SelectedIndex -eq 0 -and -not $Preview -and -not $script:State.Job -and -not $script:State.CatalogAttempted){$script:State.CatalogAttempted=$true;$script:Ui.LoadCatalog.PerformClick()}
}
function GN-RefreshMedia {
    $script:State.Images=@(GN-Media | ForEach-Object {Get-ChildItem "$_\Images\*" -Include *.wim,*.esd -ErrorAction SilentlyContinue} | Sort-Object FullName -Unique)
    $script:Ui.Local.Items.Clear();$null=$script:Ui.Local.Items.Add('Seleccione una imagen incluida...');foreach($file in $script:State.Images){$null=$script:Ui.Local.Items.Add($file.Name)};$script:Ui.Local.SelectedIndex=0
    $script:State.OfflineDrivers=@(GN-Media | ForEach-Object {Get-ChildItem "$_\Drivers\Offline" -Directory -ErrorAction SilentlyContinue})
    $script:Ui.OfflineDrivers.Items.Clear();$null=$script:Ui.OfflineDrivers.Items.Add('Packs incluidos en el medio...');foreach($folder in $script:State.OfflineDrivers){$null=$script:Ui.OfflineDrivers.Items.Add($folder.Name)};$script:Ui.OfflineDrivers.SelectedIndex=0
    $script:Ui.Profiles.Items.Clear();$invalid=0
    foreach($file in @(GN-Media | ForEach-Object {Get-ChildItem "$_\Autopilot\Profiles\*.json" -ErrorAction SilentlyContinue})){
        try{$profile=Get-GNAutopilotProfile $file.FullName;GN-Row $script:Ui.Profiles @($profile.Name,$profile.TenantDomain,$profile.TenantId) $profile}catch{$invalid++}
    }
    $script:Ui.Status.Text="Contenido encontrado: $($script:State.Images.Count) imagenes, $($script:State.OfflineDrivers.Count) packs. Perfiles invalidos: $invalid."
    GN-InvalidatePlan
}
function GN-ReviewChecklist($plan){
    $d=New-Object Windows.Forms.Form;$d.Text='Revision antes de instalar';$d.ClientSize=New-Object Drawing.Size(780,500);$d.Font=$script:Ui.Form.Font;$d.StartPosition='CenterParent';$d.MinimizeBox=$false;$d.MaximizeBox=$false
    $list=GN-List $d 16 16 748 260 @(@('Comprobacion',180),@('Resultado',130),@('Detalle',420))
    $detail=GN-Text $d 16 294 748 'Seleccione una fila para leer el detalle completo.';$detail.Multiline=$true;$detail.ReadOnly=$true;$detail.ScrollBars='Vertical';$detail.Height=100
    $list.Tag=$detail;$list.Add_SelectedIndexChanged({if($this.SelectedItems.Count -eq 1){$this.Tag.Text=$this.SelectedItems[0].SubItems[2].Text}})
    GN-Row $list @('Disco destino','Validado',("{0}, {1:N0} GB. Se borrara completo." -f $plan.DiskName,($plan.DiskSize/1GB))) $null
    GN-Row $list @('Imagen e integridad','Validado',$plan.ImageName) $null
    GN-Row $list @('Arranque','Validado',$plan.FirmwareMode) $null
    GN-Row $list @('Drivers',$(if($plan.DriverPath){'Carpeta INF'}else{'Sin adicionales'}),$(if($plan.DriverPath){$plan.DriverPath}else{'Se usaran los drivers incluidos en Windows; no garantiza todos los dispositivos.'})) $null
    if($plan.DriverPath){$compat=Get-GNDriverCompatibility -Path $plan.DriverPath -ImageVersion $plan.ImageVersion;GN-Row $list @('Compatibilidad INF',$compat.Status,$compat.Detail) $null}
    GN-Row $list @('Autopilot',$(if($plan.AutopilotProfile){'JSON valido'}else{'Sin perfil'}),$(if($plan.AutopilotProfile){$plan.AutopilotProfile.TenantDomain+'; registro, asignacion y licencias sin verificar.'}else{'No se inyectara un perfil.'})) $null
    if($script:State.Hardware){foreach($r in Get-GNAutopilotReadiness -Hardware $script:State.Hardware -Edition $script:State.Edition -ImageVersion $script:State.ImageVersion){GN-Row $list @($r.Check,$r.Status,$r.Detail) $null}}
    GN-Row $list @('Conexion','Informacion','Una imagen local puede instalarse offline. Autopilot requiere red durante OOBE.') $null
    if($plan.CompatibilityNotes){GN-Row $list @('Compatibilidad','Revisar',$plan.CompatibilityNotes) $null}
    $null=GN-Label $d 'No se ha borrado nada. Revise tambien las particiones existentes del disco.' 16 408 748
    $null=GN-Button $d 'Volver y cambiar' 16 442 230 {$this.FindForm().DialogResult='Cancel';$this.FindForm().Close()}
    $null=GN-Button $d 'Resumen revisado' 532 442 230 {$this.FindForm().DialogResult='OK';$this.FindForm().Close()}
    if(GN-RenderPreviewDialog $d 'checklist-preview'){$d.Dispose();return $false}
    try{return $d.ShowDialog($script:Ui.Form) -eq 'OK'}finally{$d.Dispose()}
}
function GN-ShowCompletion($result,$plan){
    $script:State.LastResult=$result
    $script:State.LastCompletionReport=@{Result=$result;Windows=$plan.ImageName;DiskModel=$plan.DiskName;DiskUniqueId=$plan.DiskUniqueId;Firmware=$plan.FirmwareMode;Drivers=$plan.DriverPath;AutopilotTenant=$(if($plan.AutopilotProfile){$plan.AutopilotProfile.TenantDomain}else{$null});LogRoot=(Join-Path $plan.LogRoot $plan.Id)}
    $d=New-Object Windows.Forms.Form;$d.Text='Instalacion completada';$d.ClientSize=New-Object Drawing.Size(740,380);$d.Font=$script:Ui.Form.Font;$d.StartPosition='CenterParent';$d.MinimizeBox=$false;$d.MaximizeBox=$false
    $text="Windows: $($plan.ImageName)`r`nDestino: $($plan.DiskName)`r`nArranque: $($plan.FirmwareMode)`r`nDrivers: $(if($plan.DriverPath){$plan.DriverPath}else{'Sin adicionales'})`r`nAutopilot: $(if($plan.AutopilotProfile){$plan.AutopilotProfile.TenantDomain}else{'Sin perfil'})`r`n`r`nInstalacion y configuracion offline completadas. OOBE y el registro de Autopilot se comprueban al iniciar Windows. Retire la USB antes de arrancar desde el disco interno."
    $label=GN-Label $d $text 18 18 704;$label.Height=250
    $null=GN-Button $d 'Guardar informe...' 18 316 220 {
        $folder=GN-Folder 'Guardar resultado de instalacion'
        if($folder){$target=Join-Path $folder ('GNDeploy-'+$script:State.LastResult.Id+'.json');$script:State.LastCompletionReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $target -Encoding UTF8}
    }
    $null=GN-Button $d 'Cerrar' 254 316 160 {$this.FindForm().Close()}
    $null=GN-Button $d 'Reiniciar equipo' 430 316 290 {
        $null=GN-RequestPowerAction Restart
    }
    if(GN-RenderPreviewDialog $d 'completion-preview'){$d.Dispose();return}
    try{$null=$d.ShowDialog($script:Ui.Form)}finally{$d.Dispose()}
}
function Initialize-GNWorkflow {
    $script:Ui.Summary.Width=700
    $script:Ui.Back=GN-Button $brand 'Anterior' 735 97 105 {
        $order=@(3,0,1,2,4);$pos=[array]::IndexOf($order,$script:Ui.Tabs.SelectedIndex);if($pos -gt 0){$script:Ui.Tabs.SelectedIndex=$order[$pos-1]}
    }
    $script:Ui.Next=GN-Button $brand 'Siguiente >' 850 97 110 {
        if($script:State.Job){throw 'Espere a que termine la operacion actual.'}
        $order=@(3,0,1,2,4);$pos=[array]::IndexOf($order,$script:Ui.Tabs.SelectedIndex)
        if($pos -eq 1 -and -not $script:State.Index){throw 'Seleccione una edicion de Windows y pulse Usar edicion.'}
        if($pos -lt 4){$script:Ui.Tabs.SelectedIndex=$order[$pos+1];if($script:Ui.Tabs.SelectedIndex -eq 4){$script:Ui.RefreshDisks.PerformClick()}}
    }
    $script:Ui.Tabs.Add_SelectedIndexChanged({GN-UpdateWizard})
    $null=GN-Button $toolsPage 'Actualizar contenido de USB' 570 387 330 {GN-RefreshMedia}
    $script:Ui.ProfileDetail=GN-Label $a 'Sin perfil. Un JSON valido no confirma inscripcion ni asignacion del equipo.' 18 338 885;$script:Ui.ProfileDetail.Height=28
    $script:Ui.Partitions=GN-Label $p 'Seleccione un disco para ver sus particiones actuales.' 255 140 640;$script:Ui.Partitions.Height=42
    $script:Ui.Disks.Add_SelectedIndexChanged({if($script:Ui.Disks.SelectedItems.Count -eq 1){$script:Ui.Partitions.Text='Se eliminaran: '+$script:Ui.Disks.SelectedItems[0].Tag.PartitionSummary}else{$script:Ui.Partitions.Text='Seleccione un disco para ver sus particiones actuales.'}})
    Initialize-GNAppearance
    GN-UpdateWizard
}

function GN-RequestPowerAction([ValidateSet('Restart','Shutdown')][string]$Action){
    if($script:State.Job){throw 'Hay una operacion en curso. Espere a que termine antes de salir o reiniciar.'}
    if($Preview -or $VerifyGuest){$script:State.SessionActionRequested=$Action;$script:Ui.Status.Text='Vista previa/prueba: accion registrada, no se apagara ni reiniciara el equipo.';return $true}
    if(-not(Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')){throw 'Apagar y reiniciar solo estan disponibles dentro de WinPE/WinRE.'}
    $verb=if($Action -eq 'Restart'){'reiniciar'}else{'apagar'}
    if([Windows.Forms.MessageBox]::Show($script:Ui.Form,"Desea $verb el equipo? Guarde los registros que necesite conservar. Para arrancar desde el disco interno, retire la USB cuando corresponda.",'Confirmar '+$verb,'YesNo','Question','Button2') -ne 'Yes'){return $false}
    $argument=if($Action -eq 'Restart'){'reboot'}else{'shutdown'}
    Start-Process -FilePath "$env:SystemRoot\System32\wpeutil.exe" -ArgumentList $argument -WindowStyle Hidden -ErrorAction Stop
    return $true
}
function GN-ShowExitOptions {
    if($script:State.Job){throw 'Hay una operacion en curso. Espere a que termine antes de salir.'}
    if(-not $VerifyPreview -and ($Preview -or -not(Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT'))){$script:Ui.Form.Close();return}
    $d=New-Object Windows.Forms.Form;$d.Text='Salir de GNDeploy';$d.ClientSize=New-Object Drawing.Size(680,205);$d.Font=$script:Ui.Form.Font;$d.StartPosition='CenterParent';$d.MinimizeBox=$false;$d.MaximizeBox=$false;$d.BackColor=[Drawing.Color]::FromArgb(248,250,252)
    $title=GN-Label $d 'Como quieres terminar?' 20 18 640;$title.Font=New-Object Drawing.Font($script:Ui.FontFamily,16,[Drawing.FontStyle]::Bold);$title.Height=38
    $message=GN-Label $d 'Guarda los registros que quieras conservar antes de apagar o reiniciar. Puedes volver al asistente para continuar trabajando.' 20 67 640;$message.Height=55
    $null=GN-Button $d 'Volver al asistente' 20 149 205 {$this.FindForm().Close()}
    $null=GN-Button $d 'Reiniciar equipo' 237 149 205 {if(GN-RequestPowerAction Restart){$this.FindForm().Close()}}
    $null=GN-Button $d 'Apagar equipo' 454 149 205 {if(GN-RequestPowerAction Shutdown){$this.FindForm().Close()}}
    if(GN-RenderPreviewDialog $d 'exit-preview'){$d.Dispose();return}
    try{$null=$d.ShowDialog($script:Ui.Form)}finally{$d.Dispose()}
}
function GN-AccentButton($Button,[string]$Kind='Primary'){
    $color=if($Kind -eq 'Danger'){[Drawing.Color]::FromArgb(166,42,56)}else{[Drawing.Color]::FromArgb(20,101,170)}
    $Button | Add-Member NoteProperty GNAccentColor $color -Force
    $Button.FlatAppearance.BorderSize=0
    $Button.Add_EnabledChanged({
        $this.BackColor=if($this.Enabled){$this.GNAccentColor}else{[Drawing.Color]::FromArgb(226,232,240)}
        $this.ForeColor=if($this.Enabled){[Drawing.Color]::White}else{[Drawing.Color]::FromArgb(100,116,139)}
    })
    $Button.BackColor=if($Button.Enabled){$color}else{[Drawing.Color]::FromArgb(226,232,240)}
    $Button.ForeColor=if($Button.Enabled){[Drawing.Color]::White}else{[Drawing.Color]::FromArgb(100,116,139)}
    $Button.FlatAppearance.MouseOverBackColor=if($Kind -eq 'Danger'){[Drawing.Color]::FromArgb(139,31,45)}else{[Drawing.Color]::FromArgb(14,79,137)}
}
function Initialize-GNAppearance {
    $script:Ui.Tips=New-Object Windows.Forms.ToolTip;$script:Ui.Tips.AutoPopDelay=15000
    $script:Ui.StepTitle.Visible=$false
    $script:Ui.StepChips=@()
    $names=@('1  Conexion','2  Windows','3  Drivers','4  Autopilot','5  Instalar')
    foreach($i in 0..4){$chip=GN-Label $brand $names[$i] (22+138*$i) 56 130;$chip.Height=27;$chip.TextAlign='MiddleCenter';$chip.Font=New-Object Drawing.Font($script:Ui.FontFamily,9);$script:Ui.StepChips+= $chip}
    foreach($button in @($script:Ui.Next,$script:Ui.UseEdition,$script:Ui.Download,$script:Ui.ReviewPlan,$script:Ui.UseProfile)) {GN-AccentButton $button}
    GN-AccentButton $script:Ui.Deploy Danger
    $script:Ui.Console.BackColor=[Drawing.Color]::FromArgb(38,58,82);$script:Ui.Console.ForeColor=[Drawing.Color]::White;$script:Ui.Console.FlatAppearance.BorderSize=0
    $script:Ui.Console.Text='Consola de soporte'
    $footer=New-Object Windows.Forms.Panel;$footer.Dock='Bottom';$footer.Height=73;$footer.BackColor=[Drawing.Color]::White;$form.Controls.Add($footer);$footer.BringToFront()
    $footer.Controls.Add($script:Ui.Progress);$script:Ui.Progress.SetBounds(20,8,940,7);$script:Ui.Progress.Anchor='Top,Left,Right'
    $footer.Controls.Add($script:Ui.Status);$script:Ui.Status.SetBounds(20,30,660,32);$script:Ui.Status.Anchor='Top,Left,Right';$script:Ui.Status.ForeColor=[Drawing.Color]::FromArgb(51,65,85)
    $script:Ui.Restart=GN-Button $footer 'Reiniciar' 700 30 125 {$null=GN-RequestPowerAction Restart};$script:Ui.Restart.Anchor='Top,Right'
    $script:Ui.Exit=GN-Button $footer 'Salir' 835 30 125 {GN-ShowExitOptions};$script:Ui.Exit.Anchor='Top,Right'
    $script:Ui.Tips.SetToolTip($script:Ui.Restart,'Reiniciar el equipo con confirmacion. No disponible durante una operacion.')
    $script:Ui.Tips.SetToolTip($script:Ui.Exit,'Volver al asistente, apagar o reiniciar. Cerrar la ventana no reinicia automaticamente.')
}

