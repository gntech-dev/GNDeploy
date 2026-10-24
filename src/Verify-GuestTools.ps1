function Invoke-GNGuestToolChecks([string]$ReportRoot){
    if(-not(Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')){throw 'Solo WinRE.'}
    $computer=Get-CimInstance Win32_ComputerSystem
    if($computer.Manufacturer -ne 'Microsoft Corporation' -or $computer.Model -ne 'Virtual Machine'){throw 'Solo Hyper-V.'}
    if((Get-Volume -DriveLetter $ReportRoot.Substring(0,1)).FileSystemLabel -ne 'GNMenuLab'){throw 'Solo disco de laboratorio.'}
    New-Item -ItemType Directory -Path $ReportRoot -Force | Out-Null
    $checks=New-Object Collections.Generic.List[object]
    $form.Show();[Windows.Forms.Application]::DoEvents()
    try{
        $limit=(Get-Date).AddMinutes(2)
        while($script:State.Job){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 100;if((Get-Date) -gt $limit){throw 'Inventario no completo.'}}
        $tabs.SelectedIndex=6;GN-RefreshTools
        foreach($toolName in @('Explorer++','7zFM')){
            $row=@($script:Ui.Tools.Items | Where-Object {$_.Text -eq $toolName})
            if($row.Count -ne 1){throw "No se encuentra $toolName"}
            $process=GN-LaunchTool ([string]$row[0].Tag)
            try{
                $limit=(Get-Date).AddSeconds(20)
                do{[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 200;$process.Refresh()}while(-not $process.HasExited -and $process.MainWindowHandle -eq [IntPtr]::Zero -and (Get-Date) -lt $limit)
                if($process.HasExited -or $process.MainWindowHandle -eq [IntPtr]::Zero){throw "$toolName no abrio una ventana en WinRE."}
                $checks.Add(@{Tool=$toolName;Status='WindowOpened';PID=$process.Id})
                Start-Sleep -Seconds 10
            }finally{if(-not $process.HasExited){$null=$process.CloseMainWindow();if(-not $process.WaitForExit(3000)){$process.Kill()}};$process.Dispose()}
        }
        $fixture=Join-Path $ReportRoot 'editor-fixture.txt'
        if(Test-Path $fixture){$fixture=Join-Path $ReportRoot ([guid]::NewGuid().ToString()+'.txt')}
        $editor=GN-NewTextEditor
        try{$editor.Form.Show($form);$editor.Path.Text=$fixture;$editor.Content.Text='GNDeploy editor UTF-8: prueba';$editor.Save.PerformClick();$editor.Content.Clear();$editor.Open.PerformClick();if($editor.Content.Text -ne 'GNDeploy editor UTF-8: prueba'){throw 'Editor no conserva contenido.'};$checks.Add(@{Tool='Editor';Status='ReadWritePassed'})}finally{$editor.Form.Dispose()}
        $bitmap=New-Object Drawing.Bitmap($form.Width,$form.Height)
        try{$form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height)));$bitmap.Save("$ReportRoot\tools.png",[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
        $checks | ConvertTo-Json | Set-Content "$ReportRoot\checks.json"
        @{Status='Passed';Checks=$checks.Count;WindowsInstalled=$false} | ConvertTo-Json | Set-Content "$ReportRoot\result.json"
        $script:Ui.Status.Text='HERRAMIENTAS VERIFICADAS. No se instalo Windows.'
    }catch{$_ | Out-String | Set-Content "$ReportRoot\error.txt";@{Status='Failed';Error=$_.Exception.Message} | ConvertTo-Json | Set-Content "$ReportRoot\result.json";$script:Ui.Status.Text='PRUEBA DETENIDA: '+$_.Exception.Message}
}
