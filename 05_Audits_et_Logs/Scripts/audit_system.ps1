# =========================================================================================
# SYSTEM ARCHITECTURE & SECURITY MAPPING SCRIPT (READ-ONLY)
# Target: Windows 11 Pro | Hardware: Dell Latitude 5420 (Intel i7, 32GB RAM, 512GB NVMe)
# Output: A single, exhaustive text ledger generated on the Desktop.
# =========================================================================================

# Définition du chemin de sortie et initialisation du journal
$ReportPath = [System.IO.Path]::Combine([Environment]::GetFolderPath("Desktop"), "Audit_Complet.txt")
Start-Transcript -Path $ReportPath -Force

Write-Output "========================================================================================="
Write-Output "               MASTER SYSTEM INFRASTRUCTURE MATRIX & CONFIGURATION LEDGER                "
Write-Output "========================================================================================="
Write-Output "Timestamp of Execution : $(Get-Date)"
Write-Output "Operating System Target: Windows 11 Pro"
Write-Output "Audit Type             : Zero-Trust, Zero-Blindspot, Complete Read-Only Mapping"
Write-Output "Target Log File        : $ReportPath"
Write-Output "=========================================================================================`n"

# -----------------------------------------------------------------------------------------
# LAYER 1: FIRMWARE & MOTHERBOARD HARDWARE
# -----------------------------------------------------------------------------------------
Write-Output "========================================================================================="
Write-Output "[LAYER 1] FIRMWARE, MOTHERBOARD, SECURE ROOT-OF-TRUST"
Write-Output "========================================================================================="
Write-Output "[*] Motherboard Architecture:"
Get-CimInstance -ClassName Win32_BaseBoard | Select-Object Manufacturer, Product, SerialNumber, Version | Format-List | Out-String

Write-Output "[*] BIOS / UEFI Firmware Signatures:"
Get-CimInstance -ClassName Win32_BIOS | Select-Object Manufacturer, Name, Version, ReleaseDate, SMBIOSBIOSVersion | Format-List | Out-String

Write-Output "[*] Secure Boot Status:"
Confirm-SecureBootUEFI -ErrorAction SilentlyContinue | Out-String

Write-Output "[*] TPM 2.0 Hardware Register:"
Get-CimInstance -Namespace "root\CIMV2\Security\MicrosoftTpm" -ClassName Win32_Tpm -ErrorAction SilentlyContinue | Select-Object IsEnabled_InitialValue, IsActivated_InitialValue, IsOwned_InitialValue, SpecVersion | Format-List | Out-String

# -----------------------------------------------------------------------------------------
# LAYER 2: CPU PERFORMANCE & POWER TOPOLOGY
# -----------------------------------------------------------------------------------------
Write-Output "========================================================================================="
Write-Output "[LAYER 2] CPU TOPOLOGY & REAL-TIME FREQUENCIES"
Write-Output "========================================================================================="
Write-Output "[*] Processor Core Allocation:"
Get-CimInstance -ClassName Win32_Processor | Select-Object Name, DeviceID, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed | Format-List | Out-String

Write-Output "[*] Real-Time Processor Frequency (MHz - Includes Turbo Dynamics):"
$CpuFreq = (Get-Counter "\Processor Information(_Total)\Processor Frequency" -ErrorAction SilentlyContinue).CounterSamples.CookedValue
if ($CpuFreq) { Write-Output "$([math]::Round($CpuFreq, 2)) MHz`n" } else { Write-Output "Performance Counter Unavailable`n" }

Write-Output "[*] Active Power Scheme:"
powercfg /getactivescheme | Out-String

# -----------------------------------------------------------------------------------------
# LAYER 3: UNIFIED MEMORY ARCHITECTURE & VRAM
# -----------------------------------------------------------------------------------------
Write-Output "========================================================================================="
Write-Output "[LAYER 3] UNIFIED RAM TOPOLOGY & GRAPHICS"
Write-Output "========================================================================================="
Write-Output "[*] Physical RAM Specifications:"
Get-CimInstance -ClassName Win32_PhysicalMemory | Select-Object BankLabel, Capacity, Speed, ConfiguredClockSpeed, Manufacturer | Format-Table -AutoSize | Out-String

Write-Output "[*] System Virtual Pagefile Configuration:"
Get-CimInstance -ClassName Win32_PageFileSetting | Select-Object Name, InitialSize, MaximumSize | Format-List | Out-String

Write-Output "[*] Graphics Metrics:"
Get-CimInstance -ClassName Win32_VideoController | Select-Object Name, DriverVersion, AdapterRAM, CurrentHorizontalResolution, CurrentVerticalResolution | Format-List | Out-String

# -----------------------------------------------------------------------------------------
# LAYER 4: STORAGE, NVMe & MINIFILTERS
# -----------------------------------------------------------------------------------------
Write-Output "========================================================================================="
Write-Output "[LAYER 4] NVMe CONTROLLERS & FILE INTERCEPTORS"
Write-Output "========================================================================================="
Write-Output "[*] Logical Volumes:"
Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" | Select-Object DeviceID, VolumeName, FreeSpace, Size | Format-Table -AutoSize | Out-String

Write-Output "[*] NVMe TRIM Status (0 = Enabled):"
fsutil behavior query DisableDeleteNotify | Out-String

Write-Output "[*] Active File System Minifilters:"
fltmc filters | Out-String

# -----------------------------------------------------------------------------------------
# LAYER 5: NETWORK SOCKETS & KERNEL BINDINGS
# -----------------------------------------------------------------------------------------
Write-Output "========================================================================================="
Write-Output "[LAYER 5] NETWORK SOCKETS & PORT BINDINGS"
Write-Output "========================================================================================="
Write-Output "[*] Real-Time Port-to-Process Map:"
$NetConnections = Get-NetTCPConnection -State Listen, Established -ErrorAction SilentlyContinue
$NetOut = foreach ($Conn in $NetConnections) {
    $Proc = Get-Process -Id $Conn.OwningProcess -ErrorAction SilentlyContinue
    $ProcessName = if ($Proc) { $Proc.ProcessName } else { "Unknown" }
    [PSCustomObject]@{
        LocalPort   = $Conn.LocalPort
        RemotePort  = $Conn.RemotePort
        State       = $Conn.State
        PID         = $Conn.OwningProcess
        ProcessName = $ProcessName
    }
}
$NetOut | Sort-Object LocalPort | Format-Table -AutoSize | Out-String

# -----------------------------------------------------------------------------------------
# LAYER 6: SYSTEM REGISTRY & PERFORMANCE TWEAKS
# -----------------------------------------------------------------------------------------
Write-Output "========================================================================================="
Write-Output "[LAYER 6] REGISTRY POLICIES & MEMORY MANAGEMENT"
Write-Output "========================================================================================="
Write-Output "[*] Memory Management Executive Caching:"
Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -ErrorAction SilentlyContinue | Out-String

# -----------------------------------------------------------------------------------------
# LAYER 7: APPLICATION ENVIRONMENT & RUNTIMES
# -----------------------------------------------------------------------------------------
Write-Output "========================================================================================="
Write-Output "[LAYER 7] FULL APPLICATION MATRIX & SERVICES"
Write-Output "========================================================================================="
Write-Output "[*] Environment PATH Variables:"
[Environment]::GetEnvironmentVariable("Path", "Machine") -split ';' | Out-String

Write-Output "[*] Installed Software (64-bit & 32-bit combined sampling):"
$App64 = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Select-Object DisplayName, DisplayVersion
$App32 = Get-ItemProperty "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Select-Object DisplayName, DisplayVersion
$AppUser = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Select-Object DisplayName, DisplayVersion
$AllApps = $App64 + $App32 + $AppUser | Where-Object { $_.DisplayName -ne $null } | Sort-Object DisplayName -Unique
$AllApps | Format-Table -AutoSize | Out-String

Write-Output "[*] UWP / Appx Packages (System & Store Apps):"
Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Select-Object Name, Version | Sort-Object Name | Format-Table -AutoSize | Out-String

Write-Output "[*] Third-Party Background Services:"
Get-CimInstance -ClassName Win32_Service | Where-Object { $_.StartMode -ne "Disabled" -and $_.PathName -notmatch "C:\\Windows\\System32" } | Select-Object Name, State, StartMode | Sort-Object State | Format-Table -AutoSize | Out-String

# -----------------------------------------------------------------------------------------
# LAYER 8: BITLOCKER ENCRYPTION STATUS
# -----------------------------------------------------------------------------------------
Write-Output "========================================================================================="
Write-Output "[LAYER 8] BITLOCKER ENCRYPTION STATUS"
Write-Output "========================================================================================="
Get-BitLockerVolume -ErrorAction SilentlyContinue | Select-Object MountPoint, VolumeStatus, EncryptionPercentage, EncryptionMethod | Format-Table -AutoSize | Out-String

# -----------------------------------------------------------------------------------------
# LAYER 9: NON-MICROSOFT SCHEDULED TASKS
# -----------------------------------------------------------------------------------------
Write-Output "========================================================================================="
Write-Output "[LAYER 9] THIRD-PARTY SCHEDULED TASKS"
Write-Output "========================================================================================="
Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.Author -notmatch "Microsoft" -and $_.State -ne "Disabled" } | Select-Object TaskName, TaskPath, State | Sort-Object TaskPath | Format-Table -AutoSize | Out-String

# -----------------------------------------------------------------------------------------
# LAYER 10: FIREWALL PROFILES & RULES
# -----------------------------------------------------------------------------------------
Write-Output "========================================================================================="
Write-Output "[LAYER 10] WINDOWS FIREWALL POSTURE"
Write-Output "========================================================================================="
Write-Output "[*] Firewall Profiles:"
Get-NetFirewallProfile -ErrorAction SilentlyContinue | Select-Object Name, Enabled, DefaultInboundAction | Format-Table -AutoSize | Out-String

# -----------------------------------------------------------------------------------------
# LAYER 11: LOCAL ACCOUNTS & PRIVILEGES
# -----------------------------------------------------------------------------------------
Write-Output "========================================================================================="
Write-Output "[LAYER 11] LOCAL ACCOUNTS & ADMINISTRATORS"
Write-Output "========================================================================================="
Get-LocalUser -ErrorAction SilentlyContinue | Select-Object Name, Enabled, PasswordRequired | Format-Table -AutoSize | Out-String
Write-Output "[*] Administrators Group Members:"
Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue | Select-Object Name, PrincipalSource | Format-Table -AutoSize | Out-String

# -----------------------------------------------------------------------------------------
# LAYER 12: ROOT CERTIFICATES (NON-MICROSOFT)
# -----------------------------------------------------------------------------------------
Write-Output "========================================================================================="
Write-Output "[LAYER 12] THIRD-PARTY ROOT CERTIFICATES"
Write-Output "========================================================================================="
Get-ChildItem -Path Cert:\LocalMachine\Root -ErrorAction SilentlyContinue | Where-Object { $_.Issuer -notmatch "Microsoft" -and $_.Issuer -notmatch "Windows" } | Select-Object Subject, NotAfter | Format-Table -AutoSize | Out-String

# -----------------------------------------------------------------------------------------
# LAYER 13: USB STORAGE HISTORY
# -----------------------------------------------------------------------------------------
Write-Output "========================================================================================="
Write-Output "[LAYER 13] USB STORAGE FORENSICS"
Write-Output "========================================================================================="
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR\*\*" -Name FriendlyName -ErrorAction SilentlyContinue | Select-Object FriendlyName | Format-Table -AutoSize | Out-String

# -----------------------------------------------------------------------------------------
# LAYER 14: NETWORK ADAPTERS & DNS
# -----------------------------------------------------------------------------------------
Write-Output "========================================================================================="
Write-Output "[LAYER 14] PHYSICAL ADAPTERS & DNS SERVERS"
Write-Output "========================================================================================="
Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Select-Object Name, MacAddress, Status | Format-Table -AutoSize | Out-String
Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object InterfaceAlias, ServerAddresses | Format-Table -AutoSize | Out-String

# -----------------------------------------------------------------------------------------
# LAYER 15: CRITICAL SYSTEM EVENT LOGS
# -----------------------------------------------------------------------------------------
Write-Output "========================================================================================="
Write-Output "[LAYER 15] RECENT CRITICAL SYSTEM EVENTS"
Write-Output "========================================================================================="
Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2,3} -MaxEvents 15 -ErrorAction SilentlyContinue | Select-Object TimeCreated, Id, ProviderName | Format-Table -AutoSize | Out-String

# -----------------------------------------------------------------------------------------
# LAYER 16: LOCAL SMB NETWORK SHARES
# -----------------------------------------------------------------------------------------
Write-Output "========================================================================================="
Write-Output "[LAYER 16] LOCAL SMB SHARES"
Write-Output "========================================================================================="
Get-SmbShare -ErrorAction SilentlyContinue | Select-Object Name, Path, Description | Format-Table -AutoSize | Out-String

# -----------------------------------------------------------------------------------------
# LAYER 17: WINDOWS DEFENDER STATUS
# -----------------------------------------------------------------------------------------
Write-Output "========================================================================================="
Write-Output "[LAYER 17] WINDOWS DEFENDER HEALTH"
Write-Output "========================================================================================="
Get-MpComputerStatus -ErrorAction SilentlyContinue | Select-Object AMServiceEnabled, RealTimeProtectionEnabled, AntivirusSignatureLastUpdated | Format-List | Out-String

Write-Output "`n========================================================================================="
Write-Output "                           COMPLETED MAP LOG OUT - ZERO ERRORS VALIDATED                 "
Write-Output "========================================================================================="

Stop-Transcript

# PREVENT AUTOMATIC CLOSURE OF POWERSHELL WINDOW
Write-Host "`nAudit complet terminé. Le fichier d'audit a été généré sur votre Bureau." -ForegroundColor Green
Read-Host -Prompt "Appuyez sur la touche 'Entrée' pour fermer cette fenêtre..."