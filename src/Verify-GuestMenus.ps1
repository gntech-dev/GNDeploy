function Invoke-GNGuestMenuChecks([string]$ReportRoot){
    if(-not(Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')){throw 'La prueba requiere WinRE.'}
    $computer=Get-CimInstance Win32_ComputerSystem
    if($computer.Manufacturer -ne 'Microsoft Corporation' -or $computer.Model -ne 'Virtual Machine'){throw 'Solo se permiten las pruebas en Hyper-V.'}
    if(-not $ReportRoot -or -not [IO.Path]::IsPathRooted($ReportRoot)){throw 'Falta carpeta de evidencia.'}
    $volume=Get-Volume -DriveLetter $ReportRoot.Substring(0,1)
    if($volume.FileSystemLabel -ne 'GNMenuLab'){throw 'La evidencia debe quedar en el disco GNMenuLab.'}
    New-Item -ItemType Directory -Path $ReportRoot -Force | Out-Null
    $checks=New-Object Collections.Generic.List[object]
    function Record([string]$Name,[string]$Detail=''){$checks.Add([pscustomobject]@{Check=$Name;Passed=$true;Detail=$Detail});$checks | ConvertTo-Json -Depth 6 | Set-Content "$ReportRoot\checks.json"}
    function Wait-UiJob {
        $limit=(Get-Date).AddMinutes(45)
        while($script:State.Job){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 75;if((Get-Date) -gt $limit){throw 'Tiempo agotado en tarea GUI.'}}
        if($script:State.LastError){throw $script:State.LastError}
    }
    function Capture([string]$Name){
        [Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 350
        $bitmap=New-Object Drawing.Bitmap($form.Width,$form.Height)
        try{$form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height)));$bitmap.Save("$ReportRoot\$Name.png",[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
    }
    $script:State.LastError=$null
    $form.Show();[Windows.Forms.Application]::DoEvents()
    try{
        Wait-UiJob
        foreach($action in @('Restart','Shutdown')){$null=GN-RequestPowerAction $action;if($script:State.SessionActionRequested -ne $action){throw 'Accion de energia no registrada en modo protegido.'}}
        Record 'Reiniciar y apagar: simulacion protegida sin ejecutar energia'
        $script:State.Job=@{Test=$true}
        try{
            GN-UpdateWizard
            if($script:Ui.Restart.Enabled -or $script:Ui.Exit.Enabled){throw 'Salida disponible durante operacion.'}
            $blocked=$false;try{$null=GN-RequestPowerAction Restart}catch{$blocked=$true};if(-not $blocked){throw 'Reinicio permitido durante operacion.'}
        }finally{$script:State.Job=$null;GN-UpdateWizard}
        Record 'Salida y reinicio bloqueados durante operacion'
        $tabs.SelectedIndex=6
        foreach($i in 0..2){$script:Ui.UtilityKind.SelectedIndex=$i;$script:Ui.UtilityRun.PerformClick();Wait-UiJob;if(-not $script:Ui.UtilityOutput.Text){throw 'Utilidad sin resultado.'};Record ('Utilidad: '+$script:Ui.UtilityKind.Text)}
        $hashFixture=Join-Path $ReportRoot 'hash-abc.txt';[IO.File]::WriteAllText($hashFixture,'abc',(New-Object Text.UTF8Encoding($false)))
        $integrity=GN-NewIntegrityDialog
        try{$integrity.Form.Show($form);$integrity.Path.Text=$hashFixture;$integrity.Expected.Text='BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD';$integrity.Accept.PerformClick();if($integrity.Form.DialogResult -ne 'OK'){throw 'Dialogo SHA-256 no acepta archivo.'}}finally{$integrity.Form.Dispose()}
        GN-Task 'Verificando fixture SHA-256...' {param($path) Test-GNFileIntegrity $path 'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD'} @($hashFixture) {param($data)$script:State.UtilityHashResult=$data[-1]};Wait-UiJob
        if($script:State.UtilityHashResult.Status -ne 'Coincide'){throw 'Hash de fixture incorrecto.'};Record 'Verificacion SHA-256 y dialogo de archivo'
        $blocked=$false;try{GN-LoadSessionDriver}catch{$blocked=$true};if(-not $blocked){throw 'La prueba permite cargar drivers reales.'};Record 'Carga INF bloqueada en modo de pruebas';Capture 'utilities'
        if($script:Ui.Hardware.Items.Count -lt 5){throw 'Inventario incompleto.'};Record 'Hardware y evaluacion Autopilot'
        $script:State.Hardware | ConvertTo-Json -Depth 8 | Set-Content "$ReportRoot\hardware.json"
        foreach($index in 0..6){$tabs.SelectedIndex=$index;Wait-UiJob;Capture ('menu-'+$index);foreach($control in $tabs.TabPages[$index].Controls){if($control.Right -gt $tabs.TabPages[$index].ClientSize.Width -or $control.Bottom -gt $tabs.TabPages[$index].ClientSize.Height){throw "Control fuera de la pestana: $($control.Text)"}};Record ('Menu '+$tabs.TabPages[$index].Text)}
        $cache=Join-Path (Split-Path $ReportRoot) 'Downloads'
        $folder=GN-NewFolderDialog 'Carpeta cache - prueba WinRE' $cache
        try{$folder.Form.Show($form);[Windows.Forms.Application]::DoEvents();$folder.Create.PerformClick();if(-not(Test-Path $cache)){throw $folder.Error.Text};$folder.Accept.PerformClick();if($folder.Form.DialogResult -ne 'OK'){throw 'El selector no acepto la carpeta cache.'}}finally{$folder.Form.Dispose()}
        $script:Ui.Cache.Text=$cache;Record 'Selector de cache, creacion y seleccion de carpeta'
        $tabs.SelectedIndex=3;$script:Ui.CheckNetwork.PerformClick();Wait-UiJob;Capture 'network-ethernet';Record 'Comprobacion de red Ethernet'
        $script:Ui.ScanWifi.PerformClick();Wait-UiJob;Record 'Busqueda WLAN sin adaptador en Hyper-V'
        $testNetwork=[pscustomobject]@{SSID='GNDeploy-QA (simulada)';Security='WPA2 Personal'}
        $passwordTimer=New-Object Windows.Forms.Timer;$passwordTimer.Interval=400
        $passwordTimer.Add_Tick({foreach($window in @([Windows.Forms.Application]::OpenForms)){if($window.Text -eq 'Conectar a Wi-Fi'){$window.Tag.Password.Text='fixture-only-123';$window.AcceptButton.PerformClick();$passwordTimer.Stop()}}})
        try{$passwordTimer.Start();$secret=GN-RequestWifiPassword $testNetwork;if($null -eq $secret){throw 'El dialogo de contrasena no devolvio SecureString.'};$secret.Dispose()}finally{$passwordTimer.Stop();$passwordTimer.Dispose()}
        Record 'Dialogo de contrasena Wi-Fi' 'UI simulada; sin conexion WLAN real en Hyper-V.'
        $tabs.SelectedIndex=1
        if($script:State.OfflineDrivers.Count -lt 1){throw 'No se detecto el pack offline.'}
        $pack=@($script:State.OfflineDrivers | Where-Object Name -like '*X1Nano*')[0]
        if(-not $pack){throw 'Falta pack Windows 11 para la prueba.'}
        $script:Ui.Driver.Text=$pack.FullName;$script:Ui.ValidateDrivers.PerformClick();Wait-UiJob;Record 'Seleccion y validacion de drivers INF';Capture 'drivers-selected'
        $tabs.SelectedIndex=2
        $profileFile=Join-Path $ReportRoot 'QA-ONLY.json'
        @{CloudAssignedTenantId='11111111-1111-4111-8111-111111111111';CloudAssignedTenantDomain='example.invalid';CloudAssignedOobeConfig=0;CloudAssignedDomainJoinMethod=0} | ConvertTo-Json | Set-Content $profileFile
        $picker=GN-NewFolderDialog 'Seleccionar perfil JSON' $profileFile @('.json')
        try{$picker.Form.Show($form);[Windows.Forms.Application]::DoEvents();$picker.Accept.PerformClick();if($picker.Form.DialogResult -ne 'OK'){throw 'El selector JSON no acepto el archivo.'}}finally{$picker.Form.Dispose()}
        Record 'Selector JSON sin shell Explorer'
        $profile=Get-GNAutopilotProfile $profileFile;GN-Row $script:Ui.Profiles @($profile.Name,$profile.TenantDomain,$profile.TenantId) $profile
        $script:Ui.Profiles.Items[$script:Ui.Profiles.Items.Count-1].Selected=$true;[Windows.Forms.Application]::DoEvents();$script:Ui.UseProfile.PerformClick()
        if(-not $script:State.Profile -or $script:State.Profile.TenantDomain -ne 'example.invalid'){throw 'No se selecciono el perfil QA.'}
        Capture 'autopilot-selected';$script:Ui.ClearProfile.PerformClick();Record 'Seleccion y retirada de perfil Autopilot' 'Fixture example.invalid, nunca desplegado.'
        $tabs.SelectedIndex=0;$script:Ui.LoadCatalog.PerformClick();Wait-UiJob
        $script:Ui.Language.SelectedItem='en-us';$script:Ui.Search.Text='Professional';[Windows.Forms.Application]::DoEvents()
        if($script:Ui.Catalog.Items.Count -lt 1){throw 'Catalogo sin Windows Pro en-US.'}
        $entry=@($script:Ui.Catalog.Items | Where-Object {$_.Tag.Family -eq 'Windows 11' -and $_.Tag.Acquisition -eq 'DirectESD' -and $_.Tag.Edition -eq 'Professional'})[0]
        if(-not $entry){throw 'No hay Windows 11 Pro en el catalogo.'}
        $entry.Selected=$true;[Windows.Forms.Application]::DoEvents();$record=$entry.Tag
        $download=Join-Path $cache $record.FileName
        if(Test-Path $download){
            # A second layout pass can reuse only a previously completed, hash-verified download.


            $sha=if($record.Sha256){(Get-FileHash $download -Algorithm SHA256).Hash}else{(Get-FileHash $download -Algorithm SHA1).Hash}
            $expected=if($record.Sha256){$record.Sha256}else{$record.Sha1}
            if($sha -ne $expected -or (Get-Item $download).Length -ne $record.Size){throw 'La descarga previa no coincide con el catalogo.'}
            GN-LoadImage $download;Wait-UiJob;Record 'Reutilizacion de descarga previa verificada' $download
        }else{
            $record | ConvertTo-Json -Depth 5 | Set-Content "$ReportRoot\download-source.json"
            $script:Ui.Download.PerformClick();Wait-UiJob
        }
        if(-not(Test-Path $script:State.ImagePath) -or $script:Ui.Editions.Items.Count -lt 1){throw 'No se completo la descarga/lectura WIM-ESD.'}
        Record 'Descarga completa Microsoft e integridad' ('Archivo: '+$script:State.ImagePath);Capture 'download-complete'
        $picker=GN-NewFolderDialog 'Seleccionar imagen WIM / ESD' $script:State.ImagePath @('.wim','.esd')
        try{$picker.Form.Show($form);[Windows.Forms.Application]::DoEvents();$picker.Accept.PerformClick();if($picker.Form.DialogResult -ne 'OK'){throw 'El selector WIM/ESD no acepto la imagen.'}}finally{$picker.Form.Dispose()}
        Record 'Selector WIM / ESD sin shell Explorer'
        $pro=@($script:Ui.Editions.Items | Where-Object {$_.Tag.Edition -eq 'Professional'})[0]
        if(-not $pro){throw 'Imagen sin edicion Professional.'};$pro.Selected=$true;[Windows.Forms.Application]::DoEvents();$script:Ui.UseEdition.PerformClick();Record 'Lectura y seleccion de indice de imagen'
        $tabs.SelectedIndex=4;$script:Ui.RefreshDisks.PerformClick();Wait-UiJob
        if($script:Ui.Disks.Items.Count -ne 1 -or $script:Ui.Disks.Items[0].Tag.Number -ne 0){throw 'No se aislo el disco destino virtual.'}
        $script:Ui.Disks.Items[0].Selected=$true;$script:Ui.Logs.Text=$ReportRoot;[Windows.Forms.Application]::DoEvents();$script:Ui.ReviewPlan.PerformClick();Wait-UiJob
        if(-not $script:State.Plan){throw 'No se genero el plan.'}
         $script:Ui.Confirm.Checked=$true;[Windows.Forms.Application]::DoEvents();if($script:Ui.Deploy.Enabled){throw 'La prueba no debe permitir instalar Windows.'};$script:Ui.Confirm.Checked=$false
        $script:State.Plan | ConvertTo-Json -Depth 8 | Set-Content "$ReportRoot\read-only-plan.json";Record 'Revision del plan sin instalar ni particionar';Capture 'plan-reviewed'
        $tabs.SelectedIndex=3;GN-UpdateWizard;$script:Ui.Next.PerformClick();Wait-UiJob
        if($tabs.SelectedIndex -ne 0){throw 'Asistente no navega de red a Windows.'};Record 'Asistente paso a paso'
        $windows10=@($script:State.Images | Where-Object Name -like '19045*.esd')[0]
        if(-not $windows10){throw 'Falta ESD Windows 10 verificado para la prueba.'}
        $script:State.DriverPath=$null;GN-LoadImage $windows10.FullName;Wait-UiJob
        $pro=@($script:Ui.Editions.Items | Where-Object {$_.Tag.Edition -eq 'Professional'})[0];if(-not $pro){throw 'Windows 10 sin Professional.'};$pro.Selected=$true;$script:Ui.UseEdition.PerformClick()
        $tabs.SelectedIndex=4;$script:Ui.ReviewPlan.PerformClick();Wait-UiJob
        if(-not $script:State.Plan -or $script:State.Plan.ImageName -notmatch 'Windows 10' -or ([version]$script:State.Plan.ImageVersion).Build -lt 19041 -or ([version]$script:State.Plan.ImageVersion).Build -gt 19045){throw 'Plan Windows 10 no validado.'}
        $script:Ui.Confirm.Checked=$true;if($script:Ui.Deploy.Enabled){throw 'La prueba habilito instalacion.'};GN-InvalidatePlan
        if($script:Ui.Confirm.Checked -or $script:State.Plan){throw 'Confirmacion no se invalido.'};Record 'Windows 10: lectura, plan e invalidacion sin instalar';Capture 'windows10-plan'
        $tabs.SelectedIndex=5;Capture 'hardware-final'
        @{Status='Passed';Checks=$checks.Count;WindowsInstalled=$false;PhysicalWifiTested=$false;Finished=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content "$ReportRoot\result.json"
        $script:Ui.Status.Text='PRUEBAS COMPLETADAS: menus y descarga verificados. No se instalo Windows.'
    }catch{
        @{Status='Failed';Error=($_ | Out-String);Checks=$checks.Count;WindowsInstalled=$false} | ConvertTo-Json -Depth 5 | Set-Content "$ReportRoot\result.json"
        $script:Ui.Status.Text='PRUEBA DETENIDA: '+$_.Exception.Message;Capture 'failure'
    }
}



