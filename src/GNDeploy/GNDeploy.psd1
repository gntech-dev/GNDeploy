@{
    RootModule = 'GNDeploy.psm1'
    ModuleVersion = '0.2.0'
    GUID = '34b03eb9-adb4-4d73-8888-164f676a6042'
    Author = 'GNTECH'
    Description = 'Motor independiente de despliegue Windows para laboratorio WinPE/WinRE.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('New-GNDeployUSB','Export-GNDeployWinRE','New-GNDeployWindowsImage','Get-GNDeployVersion','New-GNDeployWorkspace','Start-GNDeploy','Install-GNDeployDependency','New-GNDeployISO','Get-GNUtilityInventory','Test-GNFileIntegrity','Import-GNSessionDriver','Get-GNDriverCompatibility','Get-GNHardwareStatus','Get-GNAutopilotReadiness','Get-GNWifiNetwork','Get-GNInventory','Get-GNTargetDisk','Get-GNWindowsCatalog','Save-GNDownload','Get-GNImage','Get-GNAutopilotProfile','Set-GNAutopilotProfile','Get-GNLenovoDriverPack','Save-GNLenovoDriverPack','Get-GNOemDriverPack','Save-GNOemDriverPack','Connect-GNWifi','Get-GNNetworkStatus','New-GNDeploymentPlan','Invoke-GNDeployment','Export-GNDiagnostics')
    # Additional OEM providers are exported explicitly; no upstream module is imported.
    CmdletsToExport = @()
    AliasesToExport = @()
    VariablesToExport = @()
    PrivateData = @{PSData=@{Tags=@('Windows','Deployment','WinPE','Autopilot');LicenseUri='https://www.gnu.org/licenses/gpl-3.0.html';ReleaseNotes='Public module distribution based on r12; experimental, physical validation pending.'}}
}




