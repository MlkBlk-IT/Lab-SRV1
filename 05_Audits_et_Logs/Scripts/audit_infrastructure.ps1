#Requires -Version 7.0
#Requires -RunAsAdministrator
#Requires -Modules CimCmdlets, NetSecurity, SmbShare, BitLocker, Defender

<#
.SYNOPSIS
    Audit Système — PHASE 1 : Infrastructure & Security
.DESCRIPTION
    Couvre : Hardware, BIOS/UEFI, CPU, RAM, GPU, Storage, PnP, Security
    (SecureBoot, TPM, BitLocker, UAC, Defender, Firewall, Certificates,
    USB Forensics, Network, Sockets, SMB).
    Génère : Audit_Phase1_Infrastructure.txt sur le Bureau.
.NOTES
    Version : 1.0.0-MILITARY-PHASE1
    Temps estimé : 30-90 secondes
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'Continue'

$ReportPath = Join-Path $env:USERPROFILE 'Desktop\Audit_Phase1_Infrastructure.txt'
$sb         = [System.Text.StringBuilder]::new()
$errLog     = [System.Text.StringBuilder]::new()
$sectionTimes = [System.Collections.Generic.List[PSCustomObject]]::new()
$scriptStart  = Get-Date

# ─── FONCTIONS ─────────────────────────────────────────────────────────────────

function Invoke-AuditSection {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Number, [Parameter(Mandatory)][scriptblock]$Code)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Progress -Activity 'Audit Phase 1 — Infrastructure & Security' -Status "$Number — $Name" -PercentComplete -1
    try {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('─' * 80)
        [void]$sb.AppendLine("## [$Number] $Name")
        [void]$sb.AppendLine('─' * 80)
        & $Code
        $status = 'OK'
    }
    catch {
        $status = "ERREUR : $($_.Exception.Message)"
        [void]$errLog.AppendLine("[$Number — $Name] $($_.Exception.GetType().Name) : $($_.Exception.Message)")
    }
    finally {
        $sw.Stop()
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine("[STATUS] $status | Durée : $($sw.Elapsed.TotalSeconds.ToString('F2'))s")
        [void]$sectionTimes.Add([PSCustomObject]@{ Section=$Name; Number=$Number; Duration=$sw.Elapsed; Status=$status })
    }
}

function Fmt-Table  { param([Parameter(ValueFromPipeline)]$obj) process { $obj | Format-Table -AutoSize | Out-String -Width 4096 } }
function Fmt-List   { param([Parameter(ValueFromPipeline)]$obj) process { $obj | Format-List   | Out-String -Width 4096 } }

function Get-ProcOwner {
    param([int]$Pid)
    try {
        $p = Get-CimInstance Win32_Process -Filter "ProcessId=$Pid" -EA SilentlyContinue
        if ($p) { $o = Invoke-CimMethod -InputObject $p -MethodName GetOwner -EA SilentlyContinue; if ($o.Domain -and $o.User) { return "$($o.Domain)\$($o.User)" } }
    } catch {}
    return 'N/A'
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ─── HEADER ────────────────────────────────────────────────────────────────────

[void]$sb.AppendLine('╔' + ('═'*78) + '╗')
[void]$sb.AppendLine('║' + (' '*10) + 'AUDIT PHASE 1 — INFRASTRUCTURE & SECURITY' + (' '*11) + '║')
[void]$sb.AppendLine('╠' + ('═'*78) + '╣')
[void]$sb.AppendLine('║  PowerShell 7.x | Military Grade | Phase 1/2' + (' '*35) + '║')
[void]$sb.AppendLine('╚' + ('═'*78) + '╝')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("Timestamp : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$sb.AppendLine("Machine   : $env:COMPUTERNAME | User: $env:USERNAME | Admin: $(if($isAdmin){'✓'}else{'✗'})")
[void]$sb.AppendLine("PSVersion : $($PSVersionTable.PSVersion)")
[void]$sb.AppendLine('')


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 01 — SYSTEM OVERVIEW
# ═══════════════════════════════════════════════════════════════════════════════

Invoke-AuditSection -Name 'SYSTEM OVERVIEW' -Number '01' -Code {
    $os   = Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue
    $cs   = Get-CimInstance Win32_ComputerSystem -EA SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -EA SilentlyContinue
    $uptime = New-TimeSpan -Start ([Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime)) -End (Get-Date)

    [void]$sb.AppendLine("| Propriété          | Valeur")
    [void]$sb.AppendLine("|--------------------|-------------------------------------------")
    [void]$sb.AppendLine("| OS                 | $($os.Caption)")
    [void]$sb.AppendLine("| Version            | $($os.Version) (Build $($os.BuildNumber))")
    [void]$sb.AppendLine("| Architecture       | $($os.OSArchitecture)")
    [void]$sb.AppendLine("| Install Date       | $([Management.ManagementDateTimeConverter]::ToDateTime($os.InstallDate))")
    [void]$sb.AppendLine("| Last Boot          | $([Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime))")
    [void]$sb.AppendLine("| Uptime             | $($uptime.Days)j $($uptime.Hours)h $($uptime.Minutes)m")
    [void]$sb.AppendLine("| Manufacturer       | $($cs.Manufacturer)")
    [void]$sb.AppendLine("| Model              | $($cs.Model)")
    [void]$sb.AppendLine("| Hostname           | $($cs.Name)")
    [void]$sb.AppendLine("| Domain             | $($cs.Domain)")
    [void]$sb.AppendLine("| PartOfDomain       | $($cs.PartOfDomain)")
    [void]$sb.AppendLine("| Total RAM (GB)     | $([math]::Round($cs.TotalPhysicalMemory / 1GB, 2))")
    [void]$sb.AppendLine("| BIOS Version       | $($bios.SMBIOSBIOSVersion)")
    [void]$sb.AppendLine("| BIOS Date          | $([Management.ManagementDateTimeConverter]::ToDateTime($bios.ReleaseDate))")
    [void]$sb.AppendLine("| Serial Number      | $($bios.SerialNumber)")
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 02 — HARDWARE: MOTHERBOARD & BIOS
# ═══════════════════════════════════════════════════════════════════════════════

Invoke-AuditSection -Name 'HARDWARE — MOTHERBOARD & BIOS' -Number '02' -Code {
    $board = Get-CimInstance Win32_BaseBoard -EA SilentlyContinue
    $bios  = Get-CimInstance Win32_BIOS -EA SilentlyContinue

    [void]$sb.AppendLine("### Carte Mère")
    $board | Select-Object Manufacturer, Product, SerialNumber, Version, Tag | Fmt-List | ForEach-Object { [void]$sb.AppendLine($_) }

    [void]$sb.AppendLine("### BIOS / UEFI")
    $bios | Select-Object Manufacturer, Name, Version, @{N='ReleaseDate';E={[Management.ManagementDateTimeConverter]::ToDateTime($_.ReleaseDate)}}, SMBIOSBIOSVersion, SerialNumber | Fmt-List | ForEach-Object { [void]$sb.AppendLine($_) }

    [void]$sb.AppendLine("### Secure Boot")
    try {
        $sboot = Confirm-SecureBootUEFI -EA Stop
        [void]$sb.AppendLine("Secure Boot : $(if ($sboot) { 'ACTIVÉ ✓' } else { 'DÉSACTIVÉ ✗' })")
    } catch { [void]$sb.AppendLine("Secure Boot : INDISPONIBLE (Legacy BIOS)") }

    [void]$sb.AppendLine("### TPM 2.0")
    try {
        $tpm = Get-CimInstance -Namespace 'root\CIMV2\Security\MicrosoftTpm' -ClassName Win32_Tpm -EA SilentlyContinue
        if ($tpm) {
            [void]$sb.AppendLine("Activé     : $($tpm.IsActivated_InitialValue)")
            [void]$sb.AppendLine("Possédé    : $($tpm.IsOwned_InitialValue)")
            [void]$sb.AppendLine("Version    : $($tpm.SpecVersion)")
            [void]$sb.AppendLine("Manufacturer: $($tpm.ManufacturerIdTxt)")
        } else { [void]$sb.AppendLine("TPM : NON DÉTECTÉ") }
    } catch { [void]$sb.AppendLine("TPM : ERREUR D'ACCÈS") }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 03 — HARDWARE: CPU & POWER
# ═══════════════════════════════════════════════════════════════════════════════

Invoke-AuditSection -Name 'HARDWARE — CPU & POWER' -Number '03' -Code {
    $cpu = Get-CimInstance Win32_Processor -EA SilentlyContinue

    [void]$sb.AppendLine("### Processeur(s)")
    foreach ($c in $cpu) {
        [void]$sb.AppendLine("---")
        [void]$sb.AppendLine("Nom              : $($c.Name)")
        [void]$sb.AppendLine("DeviceID         : $($c.DeviceID)")
        [void]$sb.AppendLine("ProcessorId      : $($c.ProcessorId)")
        [void]$sb.AppendLine("Cœurs physiques  : $($c.NumberOfCores)")
        [void]$sb.AppendLine("Logiques         : $($c.NumberOfLogicalProcessors)")
        [void]$sb.AppendLine("Fréquence max    : $($c.MaxClockSpeed) MHz")
        [void]$sb.AppendLine("Fabricant        : $($c.Manufacturer)")
        [void]$sb.AppendLine("Socket           : $($c.SocketDesignation)")
        [void]$sb.AppendLine("Architecture     : $($c.Architecture)")
        [void]$sb.AppendLine("Révision         : $($c.Revision)")
        [void]$sb.AppendLine("L2 Cache         : $([math]::Round($c.L2CacheSize / 1024, 2)) MB")
        [void]$sb.AppendLine("L3 Cache         : $([math]::Round($c.L3CacheSize / 1024, 2)) MB")
        [void]$sb.AppendLine("Virtualisation   : $($c.VirtualizationFirmwareEnabled)")
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Fréquence Temps Réel")
    try {
        $cpuFreq = (Get-Counter "\Processor Information(_Total)\Processor Frequency" -EA Stop).CounterSamples.CookedValue
        [void]$sb.AppendLine("Fréquence actuelle : $([math]::Round($cpuFreq, 2)) MHz")
    } catch { [void]$sb.AppendLine("Compteur de fréquence indisponible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Power Scheme")
    try {
        [void]$sb.AppendLine((powercfg /getactivescheme 2>$null))
        [void]$sb.AppendLine("### Power Schemes Disponibles")
        [void]$sb.AppendLine((powercfg /list 2>$null))
    } catch { [void]$sb.AppendLine("powercfg indisponible.") }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 04 — HARDWARE: RAM (CORRIGÉ — ConfiguredClockSpeed = MHz)
# ═══════════════════════════════════════════════════════════════════════════════

Invoke-AuditSection -Name 'HARDWARE — RAM' -Number '04' -Code {
    $mem = Get-CimInstance Win32_PhysicalMemory -EA SilentlyContinue
    $total = 0

    [void]$sb.AppendLine("### Modules Physiques")
    foreach ($m in $mem) {
        $total += [int64]$m.Capacity
        $ff = switch ($m.FormFactor) { 8 {'DIMM'} 12 {'SODIMM'} 21 {'BGA'} default {"FF_$($m.FormFactor)"} }
        [void]$sb.AppendLine("---")
        [void]$sb.AppendLine("Banque           : $($m.BankLabel)")
        [void]$sb.AppendLine("Capacité         : $([math]::Round($m.Capacity / 1GB, 2)) GB")
        [void]$sb.AppendLine("Fréquence (MHz)  : $($m.ConfiguredClockSpeed)  ← CORRIGÉ (Speed=$($m.Speed) ns est la latence)")
        [void]$sb.AppendLine("Fabricant        : $($m.Manufacturer)")
        [void]$sb.AppendLine("S/N              : $($m.SerialNumber)")
        [void]$sb.AppendLine("Part Number      : $($m.PartNumber)")
        [void]$sb.AppendLine("Form Factor      : $ff")
        [void]$sb.AppendLine("Data Width       : $($m.DataWidth) bits")
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Résumé : RAM totale $([math]::Round($total / 1GB, 2)) GB | Slots: $($mem.Count)")

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Pagefile")
    $pf = Get-CimInstance Win32_PageFileSetting -EA SilentlyContinue
    if ($pf) { $pf | Select-Object Name, InitialSize, MaximumSize | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) } }
    else { [void]$sb.AppendLine("Pagefile géré automatiquement.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Memory Management (Registre)")
    try {
        $mm = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -EA SilentlyContinue
        $mm | Select-Object PagingFiles, ExistingPageFiles, ClearPageFileAtShutdown, LargeSystemCache | Fmt-List | ForEach-Object { [void]$sb.AppendLine($_) }
    } catch { [void]$sb.AppendLine("Registre inaccessible.") }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 05 — HARDWARE: GPU & DISPLAYS
# ═══════════════════════════════════════════════════════════════════════════════

Invoke-AuditSection -Name 'HARDWARE — GPU & DISPLAYS' -Number '05' -Code {
    [void]$sb.AppendLine("### Contrôleurs Vidéo")
    $gpu = Get-CimInstance Win32_VideoController -EA SilentlyContinue
    foreach ($g in $gpu) {
        [void]$sb.AppendLine("---")
        [void]$sb.AppendLine("Nom              : $($g.Name)")
        [void]$sb.AppendLine("Fabricant        : $($g.AdapterCompatibility)")
        [void]$sb.AppendLine("RAM vidéo        : $([math]::Round($g.AdapterRAM / 1MB, 2)) MB")
        [void]$sb.AppendLine("Résolution       : $($g.CurrentHorizontalResolution)x$($g.CurrentVerticalResolution) @ $($g.CurrentRefreshRate) Hz")
        [void]$sb.AppendLine("Bits/pixel       : $($g.CurrentBitsPerPixel)")
        [void]$sb.AppendLine("Pilote           : $($g.DriverVersion)")
        [void]$sb.AppendLine("Date pilote      : $($g.DriverDate)")
        [void]$sb.AppendLine("VideoProcessor   : $($g.VideoProcessor)")
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Moniteurs Physiques (WMI root\wmi)")
    try {
        $mon = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBasicDisplayParams -EA SilentlyContinue
        $mon | Select-Object InstanceName, Active, DisplayType, SupportedDisplayFeatures | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) }
    } catch { [void]$sb.AppendLine("WmiMonitorBasicDisplayParams indisponible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Moniteurs Desktop (Legacy — souvent 0x0 sur Win10/11)")
    try {
        $dm = Get-CimInstance Win32_DesktopMonitor -EA SilentlyContinue
        $dm | Select-Object Name, Description, ScreenWidth, ScreenHeight | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) }
    } catch { [void]$sb.AppendLine("Win32_DesktopMonitor indisponible.") }
}


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 06 — HARDWARE: STORAGE & HEALTH
# ═══════════════════════════════════════════════════════════════════════════════

Invoke-AuditSection -Name 'HARDWARE — STORAGE & HEALTH' -Number '06' -Code {
    [void]$sb.AppendLine("### Disques Physiques")
    $disks = Get-CimInstance Win32_DiskDrive -EA SilentlyContinue
    foreach ($d in $disks) {
        [void]$sb.AppendLine("---")
        [void]$sb.AppendLine("DeviceID    : $($d.DeviceID)")
        [void]$sb.AppendLine("Modèle      : $($d.Model)")
        [void]$sb.AppendLine("Interface   : $($d.InterfaceType)")
        [void]$sb.AppendLine("Média       : $($d.MediaType)")
        [void]$sb.AppendLine("Taille      : $([math]::Round($d.Size / 1GB, 2)) GB")
        [void]$sb.AppendLine("Secteurs    : $($d.TotalSectors)")
        [void]$sb.AppendLine("S/N         : $($d.SerialNumber)")
        [void]$sb.AppendLine("Firmware    : $($d.FirmwareRevision)")
        [void]$sb.AppendLine("Partitions  : $($d.Partitions)")
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Volumes Logiques")
    $vols = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -EA SilentlyContinue
    foreach ($v in $vols) {
        $pct = if ($v.Size -gt 0) { [math]::Round(($v.FreeSpace / $v.Size) * 100, 1) } else { 0 }
        $alert = if ($pct -lt 10) { ' ⚠️ ALERTE FAIBLE ESPACE' } else { '' }
        [void]$sb.AppendLine("---")
        [void]$sb.AppendLine("Lecteur     : $($v.DeviceID) | Label: $($v.VolumeName)")
        [void]$sb.AppendLine("FS          : $($v.FileSystem)")
        [void]$sb.AppendLine("Taille      : $([math]::Round($v.Size / 1GB, 2)) GB")
        [void]$sb.AppendLine("Libre       : $([math]::Round($v.FreeSpace / 1GB, 2)) GB ($pct%)$alert")
        [void]$sb.AppendLine("S/N Volume  : $($v.VolumeSerialNumber)")
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### PhysicalDisk & SMART (Storage Module)")
    try {
        $phys = Get-PhysicalDisk -EA SilentlyContinue
        foreach ($p in $phys) {
            [void]$sb.AppendLine("---")
            [void]$sb.AppendLine("Name        : $($p.FriendlyName)")
            [void]$sb.AppendLine("DeviceId    : $($p.DeviceId) | Media: $($p.MediaType) | Bus: $($p.BusType)")
            [void]$sb.AppendLine("Size        : $([math]::Round($p.Size / 1GB, 2)) GB")
            [void]$sb.AppendLine("Health      : $($p.HealthStatus) | OpStatus: $($p.OperationalStatus)")
            [void]$sb.AppendLine("S/N         : $($p.SerialNumber) | FW: $($p.FirmwareVersion)")
            [void]$sb.AppendLine("Boot/System : $($p.IsBoot) / $($p.IsSystem)")
            try {
                $rel = $p | Get-StorageReliabilityCounter -EA SilentlyContinue
                if ($rel) {
                    [void]$sb.AppendLine("  → Température : $($rel.Temperature)°C | Heures ON: $($rel.PowerOnHours) | Start/Stop: $($rel.StartStopCycleCount)")
                    [void]$sb.AppendLine("  → ReadErrors  : $($rel.ReadErrorsTotal) | WriteErrors: $($rel.WriteErrorsTotal)")
                }
            } catch { [void]$sb.AppendLine("  → SMART indisponible.") }
        }
    } catch { [void]$sb.AppendLine("Module Storage indisponible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### NVMe TRIM")
    try {
        $trim = fsutil behavior query DisableDeleteNotify 2>$null
        [void]$sb.AppendLine($trim)
        if ($trim -match 'DisableDeleteNotify = 0') { [void]$sb.AppendLine("→ TRIM ACTIVÉ ✓") }
        elseif ($trim -match 'DisableDeleteNotify = 1') { [void]$sb.AppendLine("→ TRIM DÉSACTIVÉ ✗") }
    } catch { [void]$sb.AppendLine("fsutil indisponible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### File System Minifilters")
    try { [void]$sb.AppendLine((fltmc filters 2>$null)) } catch { [void]$sb.AppendLine("fltmc indisponible.") }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 07 — HARDWARE: PnP DEVICES
# ═══════════════════════════════════════════════════════════════════════════════

Invoke-AuditSection -Name 'HARDWARE — PnP DEVICES' -Number '07' -Code {
    [void]$sb.AppendLine("### Périphériques en statut anormal")
    $bad = Get-CimInstance Win32_PnPEntity -EA SilentlyContinue | Where-Object { $_.Status -notin @('OK','Unknown',$null) }
    if ($bad) { $bad | Select-Object Name, Description, PNPDeviceID, Status | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) } }
    else { [void]$sb.AppendLine("Aucun périphérique anormal.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Périphériques classe critique")
    $crit = @('Display','Net','Storage','USB','HIDClass','Keyboard','Mouse','Monitor','Media','Image')
    Get-CimInstance Win32_PnPEntity -EA SilentlyContinue | Where-Object { $_.PNPClass -in $crit } |
        Select-Object Name, PNPClass, Manufacturer, Status, PNPDeviceID | Sort-Object PNPClass, Name | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Pilotes Signés")
    Get-CimInstance Win32_PnPSignedDriver -EA SilentlyContinue | Where-Object { $_.DeviceName } |
        Select-Object DeviceName, DriverVersion, DriverProviderName, @{N='DriverDate';E={$_.DriverDate}}, IsSigned, Signer | Sort-Object DeviceName | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 08 — SECURITY: BOOT, ENCRYPTION & UAC
# ═══════════════════════════════════════════════════════════════════════════════

Invoke-AuditSection -Name 'SECURITY — BOOT, ENCRYPTION & UAC' -Number '08' -Code {
    [void]$sb.AppendLine("### Secure Boot")
    try { $sboot = Confirm-SecureBootUEFI -EA Stop; [void]$sb.AppendLine("État : $(if($sboot){'ACTIVÉ ✓'}else{'DÉSACTIVÉ ✗'})") } catch { [void]$sb.AppendLine("INDISPONIBLE (Legacy)") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### TPM 2.0")
    try {
        $tpm = Get-CimInstance -Namespace 'root\CIMV2\Security\MicrosoftTpm' -ClassName Win32_Tpm -EA SilentlyContinue
        if ($tpm) { $tpm | Select-Object IsEnabled_InitialValue, IsActivated_InitialValue, IsOwned_InitialValue, SpecVersion, ManufacturerIdTxt | Fmt-List | ForEach-Object { [void]$sb.AppendLine($_) } }
        else { [void]$sb.AppendLine("TPM non détecté.") }
    } catch { [void]$sb.AppendLine("Accès TPM refusé.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### BitLocker")
    try {
        Import-Module BitLocker -EA SilentlyContinue
        $bl = Get-BitLockerVolume -EA SilentlyContinue
        if ($bl) { $bl | Select-Object MountPoint, VolumeStatus, EncryptionPercentage, EncryptionMethod, ProtectionStatus, LockStatus | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) } }
        else { [void]$sb.AppendLine("Aucun volume BitLocker.") }
    } catch { [void]$sb.AppendLine("BitLocker indisponible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### UAC (User Account Control)")
    try {
        $uac = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -EA SilentlyContinue
        [void]$sb.AppendLine("EnableLUA                  : $($uac.EnableLUA) $(if($uac.EnableLUA-eq1){'✓'}else{'✗'})")
        [void]$sb.AppendLine("ConsentPromptBehaviorAdmin   : $($uac.ConsentPromptBehaviorAdmin) (0=auto,1=secure,2=prompt,3=creds,4=consent,5=consent-nonadmin)")
        [void]$sb.AppendLine("ConsentPromptBehaviorUser    : $($uac.ConsentPromptBehaviorUser)")
        [void]$sb.AppendLine("PromptOnSecureDesktop        : $($uac.PromptOnSecureDesktop) $(if($uac.PromptOnSecureDesktop-eq1){'✓ Secure Desktop'}else{'✗'})")
        [void]$sb.AppendLine("EnableVirtualization         : $($uac.EnableVirtualization)")
        [void]$sb.AppendLine("EnableInstallerDetection     : $($uac.EnableInstallerDetection)")
    } catch { [void]$sb.AppendLine("Registre UAC inaccessible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Derniers Hotfixes")
    try {
        Get-HotFix -EA SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 20 |
            Select-Object HotFixID, InstalledOn, Description, InstalledBy | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) }
    } catch { [void]$sb.AppendLine("Get-HotFix indisponible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Points de Restauration")
    try {
        $rp = Get-ComputerRestorePoint -EA SilentlyContinue | Select-Object -Last 10
        if ($rp) { $rp | Select-Object Description, SequenceNumber, @{N='Date';E={$_.ConvertToDateTime($_.CreationTime)}} | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) } }
        else { [void]$sb.AppendLine("Aucun point de restauration.") }
    } catch { [void]$sb.AppendLine("Restauration système indisponible.") }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 09 — SECURITY: WINDOWS DEFENDER + EXCLUSIONS
# ═══════════════════════════════════════════════════════════════════════════════

Invoke-AuditSection -Name 'SECURITY — WINDOWS DEFENDER' -Number '09' -Code {
    [void]$sb.AppendLine("### État Général")
    try {
        $mp = Get-MpComputerStatus -EA SilentlyContinue
        if ($mp) {
            [void]$sb.AppendLine("Service AV activé        : $($mp.AMServiceEnabled)")
            [void]$sb.AppendLine("Protection temps réel    : $($mp.RealTimeProtectionEnabled)")
            [void]$sb.AppendLine("Antispyware              : $($mp.AntispywareEnabled)")
            [void]$sb.AppendLine("BehaviorMonitor          : $($mp.BehaviorMonitorEnabled)")
            [void]$sb.AppendLine("OnAccessProtection       : $($mp.OnAccessProtectionEnabled)")
            [void]$sb.AppendLine("IoavProtection           : $($mp.IoavProtectionEnabled)")
            [void]$sb.AppendLine("AV Signature             : $($mp.AntivirusSignatureLastUpdated)")
            [void]$sb.AppendLine("AS Signature             : $($mp.AntispywareSignatureLastUpdated)")
            [void]$sb.AppendLine("NIS Signature            : $($mp.NISSignatureLastUpdated)")
            [void]$sb.AppendLine("Engine                   : $($mp.AMEngineVersion)")
            [void]$sb.AppendLine("AV Version               : $($mp.AntivirusSignatureVersion)")
            [void]$sb.AppendLine("QuickScanAge (jours)     : $($mp.QuickScanAge)")
            [void]$sb.AppendLine("FullScanAge (jours)      : $($mp.FullScanAge)")
            [void]$sb.AppendLine("LastQuickScan            : $($mp.LastQuickScan)")
            [void]$sb.AppendLine("LastFullScan             : $($mp.LastFullScan)")
            [void]$sb.AppendLine("TamperProtection         : $($mp.IsTamperProtected)")
            [void]$sb.AppendLine("CloudBlockLevel          : $($mp.CloudBlockLevel)")
        } else { [void]$sb.AppendLine("Get-MpComputerStatus retourné null.") }
    } catch { [void]$sb.AppendLine("Get-MpComputerStatus indisponible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### EXCLUSIONS DEFENDER (CRITIQUE)")
    try {
        $mpPref = Get-MpPreference -EA SilentlyContinue
        if ($mpPref) {
            [void]$sb.AppendLine("--- Exclusions de chemin ---")
            if ($mpPref.ExclusionPath) { foreach ($e in $mpPref.ExclusionPath) { [void]$sb.AppendLine("  → $e") } } else { [void]$sb.AppendLine("  Aucune") }
            [void]$sb.AppendLine("--- Exclusions d'extension ---")
            if ($mpPref.ExclusionExtension) { foreach ($e in $mpPref.ExclusionExtension) { [void]$sb.AppendLine("  → $e") } } else { [void]$sb.AppendLine("  Aucune") }
            [void]$sb.AppendLine("--- Exclusions de processus ---")
            if ($mpPref.ExclusionProcess) { foreach ($e in $mpPref.ExclusionProcess) { [void]$sb.AppendLine("  → $e") } } else { [void]$sb.AppendLine("  Aucune") }
            [void]$sb.AppendLine("--- Exclusions d'IP ---")
            if ($mpPref.ExclusionIpAddress) { foreach ($e in $mpPref.ExclusionIpAddress) { [void]$sb.AppendLine("  → $e") } } else { [void]$sb.AppendLine("  Aucune") }
        } else { [void]$sb.AppendLine("Get-MpPreference retourné null.") }
    } catch { [void]$sb.AppendLine("Get-MpPreference indisponible.") }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 10 — SECURITY: FIREWALL (TOUTES LES RÈGLES)
# ═══════════════════════════════════════════════════════════════════════════════

Invoke-AuditSection -Name 'SECURITY — FIREWALL (RÈGLES COMPLÈTES)' -Number '10' -Code {
    [void]$sb.AppendLine("### Profils Firewall")
    try {
        Get-NetFirewallProfile -EA SilentlyContinue | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction, NotifyOnListen | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) }
    } catch { [void]$sb.AppendLine("Get-NetFirewallProfile indisponible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### TOUTES LES RÈGLES FIREWALL")
    try {
        $rules = Get-NetFirewallRule -EA SilentlyContinue
        [void]$sb.AppendLine("Nombre total de règles : $($rules.Count)")

        $portF = Get-NetFirewallPortFilter    | Group-Object InstanceID -AsHashTable
        $addrF = Get-NetFirewallAddressFilter | Group-Object InstanceID -AsHashTable
        $appF  = Get-NetFirewallApplicationFilter | Group-Object InstanceID -AsHashTable
        $svcF  = Get-NetFirewallServiceFilter   | Group-Object InstanceID -AsHashTable

        $i = 0
        foreach ($r in $rules) {
            $i++
            $pf = if ($portF[$r.InstanceID]) { $portF[$r.InstanceID][0] } else { $null }
            $af = if ($addrF[$r.InstanceID]) { $addrF[$r.InstanceID][0] } else { $null }
            $ap = if ($appF[$r.InstanceID])  { $appF[$r.InstanceID][0] }  else { $null }
            $sf = if ($svcF[$r.InstanceID])  { $svcF[$r.InstanceID][0] }  else { $null }

            [void]$sb.AppendLine("---")
            [void]$sb.AppendLine("Règle #$i | $($r.DisplayName)")
            [void]$sb.AppendLine("  Direction : $($r.Direction) | Action: $($r.Action) | Enabled: $($r.Enabled) | Profile: $($r.Profile)")
            [void]$sb.AppendLine("  Protocole : $(if($pf){$pf.Protocol}else{'Any'}) | LocalPort: $(if($pf){$pf.LocalPort}else{'Any'}) | RemotePort: $(if($pf){$pf.RemotePort}else{'Any'})")
            [void]$sb.AppendLine("  LocalAddr : $(if($af){$af.LocalAddress}else{'Any'}) | RemoteAddr: $(if($af){$af.RemoteAddress}else{'Any'})")
            [void]$sb.AppendLine("  App       : $(if($ap){$ap.Program}else{'Any'}) | Service: $(if($sf){$sf.Service}else{'Any'})")
        }
    } catch { [void]$sb.AppendLine("Get-NetFirewallRule indisponible.") }
}


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 11 — SECURITY: CERTIFICATES & USB FORENSICS
# ═══════════════════════════════════════════════════════════════════════════════

Invoke-AuditSection -Name 'SECURITY — CERTIFICATES & USB FORENSICS' -Number '11' -Code {
    [void]$sb.AppendLine("### Certificats Racine Tiers (Non-Microsoft)")
    try {
        $certs = Get-ChildItem Cert:\LocalMachine\Root -EA SilentlyContinue | Where-Object { $_.Issuer -notmatch 'Microsoft|Windows|CN=Microsoft' }
        if ($certs) { $certs | Select-Object Subject, Issuer, NotBefore, NotAfter, Thumbprint | Sort-Object Subject | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) } }
        else { [void]$sb.AppendLine("Aucun certificat racine tiers.") }
    } catch { [void]$sb.AppendLine("Accès store refusé.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Historique USB Storage (USBSTOR)")
    try {
        $usbPaths = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR" -EA SilentlyContinue
        if ($usbPaths) {
            foreach ($up in $usbPaths) {
                foreach ($dev in (Get-ChildItem $up.PSPath -EA SilentlyContinue)) {
                    $pr = Get-ItemProperty $dev.PSPath -EA SilentlyContinue
                    [void]$sb.AppendLine("---")
                    [void]$sb.AppendLine("Clé          : $($dev.PSChildName)")
                    [void]$sb.AppendLine("FriendlyName : $($pr.FriendlyName)")
                    [void]$sb.AppendLine("DeviceDesc   : $($pr.DeviceDesc)")
                    [void]$sb.AppendLine("Mfg          : $($pr.Mfg)")
                }
            }
        } else { [void]$sb.AppendLine("Aucun historique USBSTOR.") }
    } catch { [void]$sb.AppendLine("Accès USBSTOR refusé.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### USB Actuellement Connectés")
    try { Get-CimInstance Win32_USBHub -EA SilentlyContinue | Select-Object DeviceID, Description, Name, Status | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) } }
    catch { [void]$sb.AppendLine("Win32_USBHub indisponible.") }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 12 — NETWORK: ADAPTERS, DNS, PROXY & ROUTES
# ═══════════════════════════════════════════════════════════════════════════════

Invoke-AuditSection -Name 'NETWORK — ADAPTERS, DNS, PROXY & ROUTES' -Number '12' -Code {
    [void]$sb.AppendLine("### Adaptateurs Réseau Physiques")
    try { Get-NetAdapter -Physical -EA SilentlyContinue | Select-Object Name, InterfaceDescription, MacAddress, Status, LinkSpeed | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) } }
    catch { [void]$sb.AppendLine("Get-NetAdapter indisponible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Configuration IP (adaptateurs actifs)")
    try {
        $cfg = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -EA SilentlyContinue
        foreach ($a in $cfg) {
            [void]$sb.AppendLine("---")
            [void]$sb.AppendLine("Description  : $($a.Description)")
            [void]$sb.AppendLine("MAC          : $($a.MACAddress)")
            [void]$sb.AppendLine("IP           : $($a.IPAddress -join ', ')")
            [void]$sb.AppendLine("Subnet       : $($a.IPSubnet -join ', ')")
            [void]$sb.AppendLine("Gateway      : $($a.DefaultIPGateway -join ', ')")
            [void]$sb.AppendLine("DNS          : $($a.DNSServerSearchOrder -join ', ')")
            [void]$sb.AppendLine("DHCP         : $($a.DHCPEnabled) | Server: $($a.DHCPServer)")
            [void]$sb.AppendLine("WINS         : $($a.WINSPrimaryServer) / $($a.WINSSecondaryServer)")
            [void]$sb.AppendLine("Domain DNS   : $($a.DNSDomain)")
        }
    } catch { [void]$sb.AppendLine("Win32_NetworkAdapterConfiguration indisponible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### DNS Client (IPv4)")
    try { Get-DnsClientServerAddress -AddressFamily IPv4 -EA SilentlyContinue | Select-Object InterfaceAlias, ServerAddresses | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) } }
    catch { [void]$sb.AppendLine("Get-DnsClientServerAddress indisponible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Proxy Système")
    try {
        $px = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -EA SilentlyContinue
        [void]$sb.AppendLine("ProxyEnable   : $($px.ProxyEnable)")
        [void]$sb.AppendLine("ProxyServer   : $($px.ProxyServer)")
        [void]$sb.AppendLine("ProxyOverride : $($px.ProxyOverride)")
        [void]$sb.AppendLine("AutoConfigURL : $($px.AutoConfigURL)")
    } catch { [void]$sb.AppendLine("Registre proxy inaccessible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Table de Routage")
    try {
        Get-NetRoute -EA SilentlyContinue | Where-Object { $_.DestinationPrefix -notmatch '^224\.|^239\.|^ff00::' } |
            Select-Object DestinationPrefix, NextHop, InterfaceAlias, RouteMetric, TypeOfRoute | Sort-Object RouteMetric | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) }
    } catch { [void]$sb.AppendLine("Get-NetRoute indisponible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Fichier HOSTS")
    try {
        $hp = "$env:SystemRoot\System32\drivers\etc\hosts"
        if (Test-Path $hp) {
            $lines = Get-Content $hp -EA SilentlyContinue | Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne '' }
            [void]$sb.AppendLine("Entrées actives : $($lines.Count)")
            foreach ($l in $lines) { [void]$sb.AppendLine("  → $l") }
        } else { [void]$sb.AppendLine("Fichier HOSTS introuvable.") }
    } catch { [void]$sb.AppendLine("Erreur lecture HOSTS.") }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 13 — NETWORK: SOCKETS & SMB SHARES
# ═══════════════════════════════════════════════════════════════════════════════

Invoke-AuditSection -Name 'NETWORK — SOCKETS & SMB SHARES' -Number '13' -Code {
    [void]$sb.AppendLine("### Connexions TCP (Listen + Established)")
    try {
        $tcp = Get-NetTCPConnection -State Listen, Established -EA SilentlyContinue
        $tcp | ForEach-Object {
            $pn = 'N/A'
            try { $pn = (Get-Process -Id $_.OwningProcess -EA SilentlyContinue).Name } catch {}
            [PSCustomObject]@{ LocalAddress=$_.LocalAddress; LocalPort=$_.LocalPort; RemoteAddress=$_.RemoteAddress; RemotePort=$_.RemotePort; State=$_.State; PID=$_.OwningProcess; ProcessName=$pn }
        } | Sort-Object LocalPort | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) }
    } catch { [void]$sb.AppendLine("Get-NetTCPConnection indisponible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Connexions UDP")
    try {
        $udp = Get-NetUDPEndpoint -EA SilentlyContinue
        $udp | ForEach-Object {
            $pn = 'N/A'
            try { $pn = (Get-Process -Id $_.OwningProcess -EA SilentlyContinue).Name } catch {}
            [PSCustomObject]@{ LocalAddress=$_.LocalAddress; LocalPort=$_.LocalPort; PID=$_.OwningProcess; ProcessName=$pn }
        } | Sort-Object LocalPort | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) }
    } catch { [void]$sb.AppendLine("Get-NetUDPEndpoint indisponible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Partages SMB Locaux")
    try {
        $shares = Get-SmbShare -EA SilentlyContinue
        foreach ($s in $shares) {
            [void]$sb.AppendLine("---")
            [void]$sb.AppendLine("Nom : $($s.Name) | Path: $($s.Path) | Type: $($s.ShareType) | Users: $($s.CurrentUsers)")
            try {
                Get-SmbShareAccess -Name $s.Name -EA SilentlyContinue | ForEach-Object {
                    [void]$sb.AppendLine("  → $($_.AccountName) : $($_.AccessRight) ($($_.AccessControlType))")
                }
            } catch { [void]$sb.AppendLine("  → Permissions indisponibles") }
        }
    } catch { [void]$sb.AppendLine("Get-SmbShare indisponible.") }
}


# ═══════════════════════════════════════════════════════════════════════════════
# FINALISATION PHASE 1
# ═══════════════════════════════════════════════════════════════════════════════

$scriptEnd = Get-Date
$total = $scriptEnd - $scriptStart

[void]$sb.AppendLine('')
[void]$sb.AppendLine('╔' + ('═'*78) + '╗')
[void]$sb.AppendLine('║' + (' '*24) + 'RAPPORT PHASE 1' + (' '*39) + '║')
[void]$sb.AppendLine('╠' + ('═'*78) + '╣')

[void]$sb.AppendLine('')
[void]$sb.AppendLine("### RÉSUMÉ DES ERREURS")
if ($errLog.Length -gt 0) { [void]$sb.AppendLine($errLog.ToString()) }
else { [void]$sb.AppendLine("Aucune erreur détectée. ✓") }

[void]$sb.AppendLine('')
[void]$sb.AppendLine("### TIMING PAR SECTION")
$sectionTimes | Select-Object Number, Section, @{N='Durée_s';E={$_.Duration.TotalSeconds.ToString('F2')}}, Status | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) }

[void]$sb.AppendLine('')
[void]$sb.AppendLine("### MÉTRIQUES GLOBALES")
[void]$sb.AppendLine("Durée totale    : $($total.TotalSeconds.ToString('F2')) secondes")
[void]$sb.AppendLine("Sections        : $($sectionTimes.Count)")
[void]$sb.AppendLine("OK              : $(($sectionTimes | Where-Object Status -eq 'OK').Count)")
[void]$sb.AppendLine("ERREURS         : $(($sectionTimes | Where-Object Status -like 'ERREUR*').Count)")

$report = $sb.ToString()
$sha256 = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($report))).Replace('-','')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("Hash SHA-256 : $sha256")
[void]$sb.AppendLine('╚' + ('═'*78) + '╝')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== FIN PHASE 1 ===')

Write-Progress -Activity 'Audit Phase 1' -Status 'Écriture du rapport...' -PercentComplete -1
try {
    Set-Content -Path $ReportPath -Value $sb.ToString() -Encoding UTF8 -Force
    Write-Host "`n╔══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║           PHASE 1 TERMINÉE — INFRASTRUCTURE & SECURITY                     ║" -ForegroundColor Green
    Write-Host "╠══════════════════════════════════════════════════════════════════════════════╣" -ForegroundColor Green
    Write-Host "║  Rapport  : $ReportPath" -ForegroundColor Green
    Write-Host "║  Durée    : $($total.TotalSeconds.ToString('F2'))s | Sections OK: $(($sectionTimes | Where-Object Status -eq 'OK').Count)/$(($sectionTimes.Count))" -ForegroundColor Green
    Write-Host "║  SHA-256  : $sha256" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
} catch {
    Write-Host "`n╔══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║                     ERREUR D'ÉCRITURE                                        ║" -ForegroundColor Red
    Write-Host "╚══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

Write-Host "`nAppuyez sur Entrée pour fermer..." -ForegroundColor Yellow
[void][System.Console]::ReadLine()
