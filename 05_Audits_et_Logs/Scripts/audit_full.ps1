<#
Audit complet du système - PowerShell 7.x
- CPU, GPU, RAM, disques, affichages, périphériques, pilotes
- Programmes (Registre, Winget, Chocolatey, Scoop, Microsoft Store)
- Chemins d’installation (quand dispo)
- Dossiers C:\ et D:\ (liste simple)
- Fichiers temporaires (stats)
Rapport texte sur le Bureau, le script reste ouvert à la fin.
#>

$ErrorActionPreference = 'Stop'

# Chemin du fichier de sortie sur le Bureau
$desktopPath = [Environment]::GetFolderPath('Desktop')
$reportPath  = Join-Path $desktopPath 'Audit_Systeme_Complet.txt'

# Buffer de rapport
$report = [System.Collections.Generic.List[string]]::new()

function Add-Section {
    param([string]$Title)
    $report.Add('')
    $report.Add(('=' * 80))
    $report.Add($Title)
    $report.Add(('=' * 80))
}

function Add-Line {
    param([string]$Text)
    $report.Add($Text)
}

# --- OS et système ---
Add-Section 'INFORMATIONS OS ET SYSTEME'
try {
    $os   = Get-CimInstance -ClassName Win32_OperatingSystem
    $cs   = Get-CimInstance -ClassName Win32_ComputerSystem
    $bios = Get-CimInstance -ClassName Win32_BIOS

    Add-Line "Nom OS           : $($os.Caption)"
    Add-Line "Version OS       : $($os.Version)"
    Add-Line "Architecture     : $($os.OSArchitecture)"
    Add-Line "Installé le      : $([Management.ManagementDateTimeConverter]::ToDateTime($os.InstallDate))"
    Add-Line "Dernier démarrage: $([Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime))"
    Add-Line "Fabricant PC     : $($cs.Manufacturer)"
    Add-Line "Modèle PC        : $($cs.Model)"
    Add-Line "Nom de l'hôte    : $($cs.Name)"
    Add-Line "Nombre de CPU    : $($cs.NumberOfProcessors)"
    Add-Line "Logiques         : $($cs.NumberOfLogicalProcessors)"
    Add-Line "BIOS Version     : $($bios.SMBIOSBIOSVersion)"
    Add-Line "BIOS Date        : $($bios.ReleaseDate)"
}
catch {
    Add-Line "Erreur OS/Système : $($_.Exception.Message)"
}

# --- CPU ---
Add-Section 'CPU'
try {
    $cpu = Get-CimInstance -ClassName Win32_Processor
    foreach ($c in $cpu) {
        Add-Line "Nom              : $($c.Name)"
        Add-Line "Identifiant      : $($c.ProcessorId)"
        Add-Line "Cœurs            : $($c.NumberOfCores)"
        Add-Line "Logiques         : $($c.NumberOfLogicalProcessors)"
        Add-Line "Fréquence (MHz)  : $($c.MaxClockSpeed)"
        Add-Line "Fabricant        : $($c.Manufacturer)"
        Add-Line "Socket           : $($c.SocketDesignation)"
        Add-Line ""
    }
}
catch {
    Add-Line "Erreur CPU : $($_.Exception.Message)"
}

# --- GPU / Contrôleurs vidéo ---
Add-Section 'GPU / CONTROLEURS VIDEO'
try {
    $gpus = Get-CimInstance -ClassName Win32_VideoController
    foreach ($gpu in $gpus) {
        Add-Line "Nom              : $($gpu.Name)"
        Add-Line "Description      : $($gpu.Description)"
        Add-Line "Fabricant        : $($gpu.AdapterCompatibility)"
        Add-Line "RAM vidéo (bytes): $($gpu.AdapterRAM)"
        Add-Line "Résolution courante : $($gpu.CurrentHorizontalResolution)x$($gpu.CurrentVerticalResolution)"
        Add-Line "Pilote version   : $($gpu.DriverVersion)"
        Add-Line ""
    }
}
catch {
    Add-Line "Erreur GPU : $($_.Exception.Message)"
}

# --- RAM ---
Add-Section 'RAM / MEMOIRE PHYSIQUE'
try {
    $memModules = Get-CimInstance -ClassName Win32_PhysicalMemory
    $totalRamBytes = 0
    foreach ($m in $memModules) {
        $totalRamBytes += [int64]$m.Capacity
        Add-Line "Banque           : $($m.BankLabel)"
        Add-Line ("Capacité (GB)    : {0:N2}" -f ($m.Capacity / 1GB))
        Add-Line "Vitesse (MHz)    : $($m.Speed)"
        Add-Line "Fabricant        : $($m.Manufacturer)"
        Add-Line "Numéro série     : $($m.SerialNumber)"
        Add-Line ""
    }
    Add-Line ("RAM totale (GB)  : {0:N2}" -f ($totalRamBytes / 1GB))
}
catch {
    Add-Line "Erreur RAM : $($_.Exception.Message)"
}

# --- Disques physiques et volumes ---
Add-Section 'DISQUES PHYSIQUES ET VOLUMES'
try {
    $disks = Get-CimInstance -ClassName Win32_DiskDrive
    foreach ($d in $disks) {
        Add-Line "Disque           : $($d.DeviceID)"
        Add-Line "Modèle           : $($d.Model)"
        Add-Line "Interface        : $($d.InterfaceType)"
        Add-Line ("Taille (GB)      : {0:N2}" -f ($d.Size / 1GB))
        Add-Line "Numéro série     : $($d.SerialNumber)"
        Add-Line ""
    }

    $volumes = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3"
    foreach ($v in $volumes) {
        Add-Line "Lecteur          : $($v.DeviceID)"
        Add-Line "Label            : $($v.VolumeName)"
        Add-Line "Système de fichiers : $($v.FileSystem)"
        Add-Line ("Taille (GB)      : {0:N2}" -f ($v.Size / 1GB))
        Add-Line ("Libre (GB)       : {0:N2}" -f ($v.FreeSpace / 1GB))
        Add-Line ""
    }
}
catch {
    Add-Line "Erreur disques : $($_.Exception.Message)"
}

# --- Affichages / Moniteurs ---
Add-Section 'AFFICHAGES / MONITEURS'
try {
    $monitors = Get-CimInstance -ClassName Win32_DesktopMonitor
    foreach ($m in $monitors) {
        Add-Line "Nom              : $($m.Name)"
        Add-Line "Description      : $($m.Description)"
        Add-Line "Fabricant        : $($m.Manufacturer)"
        Add-Line "Résolution       : $($m.ScreenWidth)x$($m.ScreenHeight)"
        Add-Line ""
    }
}
catch {
    Add-Line "Erreur moniteurs : $($_.Exception.Message)"
}

# --- Périphériques PnP ---
Add-Section 'PERIPHERIQUES PNP'
try {
    $devices = Get-CimInstance -ClassName Win32_PnPEntity
    foreach ($dev in $devices) {
        Add-Line "Nom              : $($dev.Name)"
        Add-Line "Description      : $($dev.Description)"
        Add-Line "ID PNP           : $($dev.PNPDeviceID)"
        Add-Line "Statut           : $($dev.Status)"
        Add-Line ""
    }
}
catch {
    Add-Line "Erreur périphériques PnP : $($_.Exception.Message)"
}

# --- Pilotes signés ---
Add-Section 'PILOTES SIGNES'
try {
    $drivers = Get-CimInstance -ClassName Win32_PnPSignedDriver
    foreach ($drv in $drivers) {
        Add-Line "Nom périphérique : $($drv.DeviceName)"
        Add-Line "Fichier pilote   : $($drv.DriverFileName)"
        Add-Line "Version pilote   : $($drv.DriverVersion)"
        Add-Line "Fournisseur      : $($drv.DriverProviderName)"
        Add-Line "Date pilote      : $($drv.DriverDate)"
        Add-Line ""
    }
}
catch {
    Add-Line "Erreur pilotes signés : $($_.Exception.Message)"
}

# --- Programmes installés (Registre) ---
Add-Section 'PROGRAMMES INSTALLÉS (REGISTRE)'
function Get-InstalledAppsFromKey {
    param([string]$RegPath)
    try {
        Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName } |
            Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation
    }
    catch {
        @()
    }
}

try {
    $paths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $apps = foreach ($p in $paths) {
        Get-InstalledAppsFromKey -RegPath $p
    }

    $apps = $apps | Sort-Object DisplayName -Unique

    foreach ($app in $apps) {
        Add-Line "Nom              : $($app.DisplayName)"
        Add-Line "Version          : $($app.DisplayVersion)"
        Add-Line "Éditeur          : $($app.Publisher)"
        Add-Line "Installé le      : $($app.InstallDate)"
        Add-Line "Emplacement      : $($app.InstallLocation)"
        Add-Line ""
    }
}
catch {
    Add-Line "Erreur programmes (Registre) : $($_.Exception.Message)"
}

# --- Applications Microsoft Store ---
Add-Section 'APPLICATIONS MICROSOFT STORE (APPX)'
try {
    $storeApps = Get-AppxPackage -ErrorAction SilentlyContinue
    foreach ($app in $storeApps) {
        Add-Line "Nom              : $($app.Name)"
        Add-Line "FullName         : $($app.PackageFullName)"
        Add-Line "Version          : $($app.Version)"
        Add-Line "Publisher        : $($app.Publisher)"
        Add-Line "Emplacement      : $($app.InstallLocation)"
        Add-Line ""
    }
}
catch {
    Add-Line "Erreur Microsoft Store : $($_.Exception.Message)"
}

# --- Winget ---
Add-Section 'APPLICATIONS INSTALLEES VIA WINGET'
try {
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        $wingetOutput = winget list --accept-source-agreements 2>$null
        Add-Line "Sortie brute winget list :"
        Add-Line $wingetOutput
    }
    else {
        Add-Line "Winget non disponible sur ce système."
    }
}
catch {
    Add-Line "Erreur Winget : $($_.Exception.Message)"
}

# --- Chocolatey ---
Add-Section 'APPLICATIONS INSTALLEES VIA CHOCOLATEY'
try {
    $chocoCmd = Get-Command choco -ErrorAction SilentlyContinue
    if ($chocoCmd) {
        $chocoList = choco list -lo 2>$null
        Add-Line "Sortie brute choco list -lo :"
        Add-Line $chocoList
    }
    else {
        Add-Line "Chocolatey non disponible sur ce système."
    }
}
catch {
    Add-Line "Erreur Chocolatey : $($_.Exception.Message)"
}

# --- Scoop ---
Add-Section 'APPLICATIONS INSTALLEES VIA SCOOP'
try {
    $scoopCmd = Get-Command scoop -ErrorAction SilentlyContinue
    if ($scoopCmd) {
        $scoopList = scoop list 2>$null
        Add-Line "Sortie brute scoop list :"
        Add-Line $scoopList
    }
    else {
        Add-Line "Scoop non disponible sur ce système."
    }
}
catch {
    Add-Line "Erreur Scoop : $($_.Exception.Message)"
}

# --- Modules PowerShell installés ---
Add-Section 'MODULES POWERSHELL INSTALLÉS'
try {
    $modules = Get-InstalledModule -ErrorAction SilentlyContinue
    foreach ($m in $modules) {
        Add-Line "Nom              : $($m.Name)"
        Add-Line "Version          : $($m.Version)"
        Add-Line "Repository       : $($m.Repository)"
        Add-Line ""
    }
}
catch {
    Add-Line "Erreur modules PowerShell : $($_.Exception.Message)"
}

# --- Services ---
Add-Section 'SERVICES WINDOWS'
try {
    $services = Get-Service | Sort-Object Name
    foreach ($s in $services) {
        Add-Line "Nom              : $($s.Name)"
        Add-Line "Affichage        : $($s.DisplayName)"
        Add-Line "Statut           : $($s.Status)"
        Add-Line "Type de démarrage: $($s.StartType)"
        Add-Line ""
    }
}
catch {
    Add-Line "Erreur services : $($_.Exception.Message)"
}

# --- Réseau ---
Add-Section 'CONFIGURATION RESEAU'
try {
    $adapters = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled }
    foreach ($a in $adapters) {
        Add-Line "Description      : $($a.Description)"
        Add-Line "Adresse MAC      : $($a.MACAddress)"
        Add-Line "Adresse(s) IP    : $($a.IPAddress -join ', ')"
        Add-Line "Passerelle       : $($a.DefaultIPGateway -join ', ')"
        Add-Line "DNS              : $($a.DNSServerSearchOrder -join ', ')"
        Add-Line ""
    }
}
catch {
    Add-Line "Erreur réseau : $($_.Exception.Message)"
}

# --- Dossiers C:\ (liste simple) ---
Add-Section 'DOSSIERS SUR C:\ (TOP-LEVEL)'
try {
    if (Test-Path 'C:\') {
        $foldersC = Get-ChildItem -Path 'C:\' -Directory -Force -ErrorAction SilentlyContinue
        foreach ($f in $foldersC) {
            Add-Line "Dossier          : $($f.FullName)"
        }
    }
    else {
        Add-Line "Lecteur C:\ introuvable."
    }
}
catch {
    Add-Line "Erreur dossiers C:\ : $($_.Exception.Message)"
}

# --- Dossiers D:\ (liste simple) ---
Add-Section 'DOSSIERS SUR D:\ (TOP-LEVEL)'
try {
    if (Test-Path 'D:\') {
        $foldersD = Get-ChildItem -Path 'D:\' -Directory -Force -ErrorAction SilentlyContinue
        foreach ($f in $foldersD) {
            Add-Line "Dossier          : $($f.FullName)"
        }
    }
    else {
        Add-Line "Lecteur D:\ introuvable."
    }
}
catch {
    Add-Line "Erreur dossiers D:\ : $($_.Exception.Message)"
}

# --- Fichiers temporaires ---
Add-Section 'FICHIERS TEMPORAIRES'
try {
    $tempPaths = @()
    if ($env:TEMP) { $tempPaths += $env:TEMP }
    if ($env:TMP)  { $tempPaths += $env:TMP }
    if ($env:SystemRoot) {
        $windowsTemp = Join-Path $env:SystemRoot 'Temp'
        $tempPaths += $windowsTemp
    }

    $tempPaths = $tempPaths | Select-Object -Unique

    foreach ($tp in $tempPaths) {
        Add-Line "Dossier TEMP     : $tp"
        if (Test-Path $tp) {
            $tempFiles = Get-ChildItem -Path $tp -Recurse -Force -ErrorAction SilentlyContinue
            $sizeInfo  = $tempFiles | Where-Object { -not $_.PSIsContainer } |
                         Measure-Object -Property Length -Sum
            $sizeGB = if ($sizeInfo.Sum) { [math]::Round($sizeInfo.Sum / 1GB, 4) } else { 0 }
            Add-Line "Nombre d'entrées : $($tempFiles.Count)"
            Add-Line "Taille fichiers (GB): $sizeGB"
        }
        else {
            Add-Line "Chemin TEMP introuvable."
        }
        Add-Line ""
    }
}
catch {
    Add-Line "Erreur fichiers temporaires : $($_.Exception.Message)"
}

# --- Écriture du rapport ---
try {
    Set-Content -Path $reportPath -Value $report -Encoding UTF8
    Write-Host "Audit complet terminé." -ForegroundColor Green
    Write-Host "Rapport enregistré dans : $reportPath" -ForegroundColor Green
}
catch {
    Write-Host "Erreur lors de l'écriture du rapport : $($_.Exception.Message)" -ForegroundColor Red
}

# Le script ne se ferme pas automatiquement
Write-Host "Script terminé. Appuyez sur Entrée pour fermer la fenêtre..." -ForegroundColor Yellow
[void][System.Console]::ReadLine()
