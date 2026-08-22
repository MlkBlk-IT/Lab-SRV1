$File = "$env:USERPROFILE\Desktop\USB_Audit.txt"
"=== AUDIT SÉCURITÉ USB ===" | Out-File $File
"Date: $(Get-Date)" | Add-Content $File
"" | Add-Content $File

# 1. Vérification AutoPlay / AutoRun
" [1] AUTOPLAY / AUTORUN" | Add-Content $File
$AutoRun = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoDriveTypeAutoRun" -ErrorAction SilentlyContinue
if ($AutoRun.NoDriveTypeAutoRun -eq 255) {
    "✅ AutoRun est COMPLÈTEMENT DÉSACTIVÉ (Valeur: 255)" | Add-Content $File
} elseif ($AutoRun.NoDriveTypeAutoRun -eq 181 -or $AutoRun.NoDriveTypeAutoRun -eq 29) {
    "⚠️ AutoRun est partiellement désactivé (Valeur: $($AutoRun.NoDriveTypeAutoRun))" | Add-Content $File
} else {
    "❌ AutoRun est ACTIVÉ ou non configuré (Vulnérable)" | Add-Content $File
}
"" | Add-Content $File

# 2. Protection DMA du noyau (Kernel DMA Protection)
" [2] PROTECTION DMA DU NOYAU (Anti-PCILeech)" | Add-Content $File
$DMA = Get-CimInstance Win32_DeviceGuard -ErrorAction SilentlyContinue
if ($DMA.VirtualizationBasedSecurityServices -contains "Kernel DMA Protection") {
    "✅ Protection DMA du noyau : ACTIVÉE" | Add-Content $File
} else {
    "❌ Protection DMA du noyau : DÉSACTIVÉE ou non supportée" | Add-Content $File
}
"" | Add-Content $File

# 3. Restriction d'accès au stockage amovible (GPO/Registre)
" [3] ACCÈS AU STOCKAGE AMOVIBLE" | Add-Content $File
$DenyRead = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices" -Name "Deny_Read" -ErrorAction SilentlyContinue
$DenyWrite = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices" -Name "Deny_Write" -ErrorAction SilentlyContinue
if ($DenyRead.Deny_Read -eq 1 -or $DenyWrite.Deny_Write -eq 1) {
    "🔒 Accès USB restreint par stratégie (Lecture ou Écriture bloquée)" | Add-Content $File
} else {
    "ℹ️ Accès USB : LIBRE (Lecture et Écriture autorisées par défaut)" | Add-Content $File
}
"" | Add-Content $File

# 4. Historique des derniers périphériques USB connectés (Top 5)
" [4] DERNIERS PÉRIPHÉRIQUES USB CONNECTÉS" | Add-Content $File
$USBHistory = Get-ChildItem -Path "HKLM:\SYSTEM\CurrentControlSet\Enum\USB" -ErrorAction SilentlyContinue | ForEach-Object {
    Get-ChildItem -Path $_.PSPath -ErrorAction SilentlyContinue
} | Select-Object -First 5 PSChildName, @{Name="FriendlyName";Expression={(Get-ItemProperty $_.PSPath).FriendlyName}}

foreach ($Dev in $USBHistory) {
    "  - $($Dev.FriendlyName) (ID: $($Dev.PSChildName))" | Add-Content $File
}
"" | Add-Content $File

"=== FIN DE L'AUDIT ===" | Add-Content $File
notepad $File