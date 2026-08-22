# ============================================================
# AUDIT HYPER-V COMPLET - HÔTE + TOUTES VMs
# ============================================================

Write-Host "`n===== 1. HÔTE HYPER-V =====" -ForegroundColor Cyan
Get-VMHost | Select-Object EnableEnhancedSessionMode, EnableEnhancedSessionModePolicy, VirtualMachinePath, VirtualHardDiskPath | Format-List

Write-Host "`n===== 2. ÉTAT + CONFIG DE CHAQUE VM =====" -ForegroundColor Cyan
Get-VM | Format-Table Name, State, Generation, Version, EnhancedSessionTransportType, AutomaticStartAction, AutomaticStopAction, AutomaticCheckpointsEnabled -AutoSize

Write-Host "`n===== 3. INTEGRATION SERVICES DÉTAILLÉ =====" -ForegroundColor Cyan
foreach ($vm in (Get-VM)) {
    Write-Host "`n--- $($vm.Name) ---" -ForegroundColor Yellow
    Get-VMIntegrationService -VMName $vm.Name | Format-Table Name, Enabled, PrimaryStatusDescription, SecondaryStatusDescription -AutoSize
}

Write-Host "`n===== 4. MÉMOIRE =====" -ForegroundColor Cyan
Get-VM | Get-VMMemory | Format-Table VMName, Startup, Minimum, Maximum, DynamicMemoryEnabled, Buffer -AutoSize

Write-Host "`n===== 5. CPU =====" -ForegroundColor Cyan
Get-VM | Get-VMProcessor | Format-Table VMName, Count, Reserve, Maximum, RelativeWeight -AutoSize

Write-Host "`n===== 6. DISQUES =====" -ForegroundColor Cyan
Get-VM | Get-VMHardDiskDrive | Format-Table VMName, Path, ControllerType, ControllerNumber, ControllerLocation -AutoSize

Write-Host "`n===== 7. RÉSEAU =====" -ForegroundColor Cyan
Get-VM | Get-VMNetworkAdapter | Format-Table VMName, SwitchName, MacAddress, Connected, DynamicMacAddressEnabled -AutoSize

Write-Host "`n===== 8. VIRTUAL SWITCHES =====" -ForegroundColor Cyan
Get-VMSwitch | Format-Table Name, SwitchType, NetAdapterInterfaceDescription, AllowManagementOS -AutoSize

Write-Host "`n===== 9. SERVICES HYPER-V SUR HÔTE =====" -ForegroundColor Cyan
Get-Service vm*, hv* | Format-Table Name, DisplayName, Status, StartType -AutoSize

Write-Host "`n===== 10. GROUP POLICY - CLIPBOARD REDIRECTION =====" -ForegroundColor Cyan
$gpResult = reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v fDisableClip 2>&1
Write-Host $gpResult
$gpResult2 = reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v fDenyTSConnections 2>&1
Write-Host $gpResult2

Write-Host "`n===== 11. ENHANCED SESSION MODE POLICY (REGISTRE HÔTE) =====" -ForegroundColor Cyan
reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization" /v EnableEnhancedSessionMode 2>&1

Write-Host "`n===== 12. SÉCURITÉ PAR VM (SecureBoot, TPM) =====" -ForegroundColor Cyan
foreach ($vm in (Get-VM)) {
    Write-Host "`n--- $($vm.Name) ---" -ForegroundColor Yellow
    Get-VMSecurity -VMName $vm.Name | Format-Table VMName, SecureBootEnabled, TpmEnabled, EncryptStateAndVmMigrationTraffic -AutoSize
}

Write-Host "`n===== 13. CHECKPOINTS PAR VM =====" -ForegroundColor Cyan
Get-VM | Format-Table Name, CheckpointType, AutomaticCheckpointsEnabled -AutoSize

Write-Host "`n===== 14. VERSION HYPER-V HÔTE =====" -ForegroundColor Cyan
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V | Format-List

Write-Host "`nAUDIT TERMINÉ" -ForegroundColor Green