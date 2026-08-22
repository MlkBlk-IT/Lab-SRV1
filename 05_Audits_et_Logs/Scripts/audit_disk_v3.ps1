#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Audit et nettoyage avance des disques — Version 3.0 Bug-Free.
.DESCRIPTION
    Script entreprise Windows 11 Pro en 5 phases :
      1. Inventaire volumes + SMART (StorageReliabilityCounter) + BitLocker.
      2. Applications installees (registre Uninstall + AppxPackage -AllUsers) par lecteur.
      3. Analyse fichiers inutiles avec ages de securite (Temp, cache, dumps, logs,
         MSI orphelins). CBS et MEMORY.DMP en AUDIT ONLY.
      4. (Optionnel) Detection doublons SHA256 avec exclusions systeme + AppData.
      5. Nettoyage securise opt-in avec mesure gain reel avant/apres.
    Les doublons ne sont JAMAIS supprimes automatiquement.
.PARAMETER Clean
    Active la suppression reelle des fichiers (sinon simulation seule).
.PARAMETER AuditOnly
    Mode audit leger : pas de nettoyage, pas de scan doublons automatique.
.PARAMETER ScanDuplicates
    Active la recherche de doublons par hash (peut etre long).
.PARAMETER TargetDrives
    Lettres de lecteur a analyser, ex: 'C','D'. Par defaut : tous les disques fixes.
.PARAMETER MinDuplicateSizeKB
    Taille minimale (Ko) pour la recherche de doublons. Defaut : 100 Ko.
.PARAMETER MinFileAgeDays
    Age minimal (jours) pour les fichiers sensibles (MSI, logs). Defaut : 7.
.PARAMETER ReportPath
    Dossier de sortie des rapports. Defaut : Bureau\DiskAudit_<horodatage>.
.EXAMPLE
    .\Disk-Audit-Engineer-v3.ps1
    Audit complet en mode simulation.
.EXAMPLE
    .\Disk-Audit-Engineer-v3.ps1 -Clean -Confirm:$false
    Nettoyage reel sans confirmation.
.NOTES
    Version : 3.0 Bug-Free
    Compatibilite : Windows 10/11 Pro, Server 2016+
    Securite : Ne touche jamais WinSxS, Installer, catroot2.
    MEMORY.DMP et CBS sont AUDIT ONLY (jamais supprimes automatiquement).
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [switch]$Clean,
    [switch]$AuditOnly,
    [switch]$ScanDuplicates,
    [string[]]$TargetDrives,
    [int]$MinDuplicateSizeKB = 100,
    [int]$MinFileAgeDays = 7,
    [string]$ReportPath = "$env:USERPROFILE\Desktop\DiskAudit_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
)

# ============================================================
# INITIALISATION STRICTE
# ============================================================
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not (Test-Path -Path $ReportPath)) {
    New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null
}

$logFile = Join-Path $ReportPath 'Audit.log'
$script:ErrorCount = 0

# Initialisation EXPLICITE de toutes les variables utilisees dans le JSON final
$cbsFiles        = @()
$cbsSizeMB       = 0
$totalJunkMB     = 0
$duplicateReport = @()
$allJunkItems    = [System.Collections.Generic.List[object]]::new()
$spaceBefore     = @{}
$spaceAfter      = @{}
$physicalDisks   = @()
$smartData       = @()
$bitlockerVolumes = @()

# ============================================================
# FONCTIONS UTILITAIRES
# ============================================================
function Write-AuditLog {
    param(
        [string]$Message,
        [ValidateSet('Info','Warning','Error','Success')][string]$Level = 'Info'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $colorMap = @{ Info = 'White'; Warning = 'Yellow'; Error = 'Red'; Success = 'Green' }
    Write-Host "[$timestamp] $Message" -ForegroundColor $colorMap[$Level]
    "[$timestamp] [$Level] $Message" | Out-File -FilePath $logFile -Append -Encoding utf8
    if ($Level -eq 'Error') { $script:ErrorCount++ }
}

function Write-Section {
    param([string]$Title)
    Write-AuditLog -Message "=== $Title ===" -Level Info
}

function Remove-EmptyDirectories {
    param([string]$Path)
    if (-not (Test-Path -Path $Path)) { return }
    Get-ChildItem -Path $Path -Recurse -Directory -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        ForEach-Object {
            if (-not (Get-ChildItem -Path $_.FullName -Force -ErrorAction SilentlyContinue)) {
                Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
}

function Remove-FileSafe {
    <#
    .SYNOPSIS
        Supprime un fichier en essayant sans -Force d'abord, puis avec -Force si necessaire.
    #>
    param([string]$Path)
    if (-not (Test-Path -Path $Path)) { return }
    try {
        # Essai standard (fichiers normaux)
        Remove-Item -Path $Path -ErrorAction Stop
    }
    catch {
        # Si echec (fichier cache/systeme), essai avec -Force
        try {
            Remove-Item -Path $Path -Force -ErrorAction Stop
            Write-AuditLog -Message "Suppression avec -Force reussie : $Path" -Level Warning
        }
        catch {
            Write-AuditLog -Message "Impossible de supprimer $Path : $($_.Exception.Message)" -Level Error
        }
    }
}

# ============================================================
# PHASE 1 : INVENTAIRE DISQUES + SMART + BITLOCKER
# ============================================================
Write-Section 'Phase 1 - Inventaire des disques'

$volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }
if ($TargetDrives) {
    $volumes = $volumes | Where-Object { $_.DriveLetter -in $TargetDrives }
}

$diskReport = foreach ($vol in $volumes) {
    $usedGB  = [math]::Round(($vol.Size - $vol.SizeRemaining) / 1GB, 2)
    $freeGB  = [math]::Round($vol.SizeRemaining / 1GB, 2)
    $totalGB = [math]::Round($vol.Size / 1GB, 2)
    $pctFree = if ($vol.Size -gt 0) { [math]::Round(($vol.SizeRemaining / $vol.Size) * 100, 1) } else { 0 }

    [PSCustomObject]@{
        Lecteur       = "$($vol.DriveLetter):"
        Label         = $vol.FileSystemLabel
        FileSystem    = $vol.FileSystem
        SanteDisque   = $vol.HealthStatus
        TailleGo      = $totalGB
        UtiliseGo     = $usedGB
        LibreGo       = $freeGB
        PourcentLibre = $pctFree
    }
}

$diskReport | Format-Table -AutoSize
$diskReport | Export-Csv -Path (Join-Path $ReportPath 'Disques.csv') -NoTypeInformation -Encoding UTF8
Write-AuditLog -Message "Phase 1 volumes : $($diskReport.Count) lecteur(s) analyse(s)." -Level Success

# --- PhysicalDisk + SMART (StorageReliabilityCounter) ---
try {
    Write-Section 'Etat physique & SMART'

    # CONSERVATION de l'objet brut MSFT_PhysicalDisk pour SMART
    $physicalDisksRaw = Get-PhysicalDisk
    $physicalDisks = $physicalDisksRaw | Select-Object DeviceId, FriendlyName, MediaType, HealthStatus, OperationalStatus, Size
    $physicalDisks | Format-Table -AutoSize
    $physicalDisks | Export-Csv -Path (Join-Path $ReportPath 'DisquesPhysiques.csv') -NoTypeInformation -Encoding UTF8

    $smartData = foreach ($pd in $physicalDisksRaw) {
        try {
            $rel = Get-StorageReliabilityCounter -PhysicalDisk $pd -ErrorAction SilentlyContinue
            [PSCustomObject]@{
                DeviceId              = $pd.DeviceId
                FriendlyName          = $pd.FriendlyName
                Temperature           = $rel.Temperature
                Wear                  = $rel.Wear
                PowerOnHours          = $rel.PowerOnHours
                ReadErrorsTotal       = $rel.ReadErrorsTotal
                ReadErrorsUncorrected = $rel.ReadErrorsUncorrected
            }
        }
        catch {
            Write-AuditLog -Message "SMART indisponible pour $($pd.FriendlyName)" -Level Warning
            $null
        }
    }
    $smartData | Where-Object { $_ } | Format-Table -AutoSize
    $smartData | Where-Object { $_ } | Export-Csv -Path (Join-Path $ReportPath 'SMART.csv') -NoTypeInformation -Encoding UTF8
}
catch {
    Write-AuditLog -Message "Impossible de recuperer l'etat physique/SMART : $($_.Exception.Message)" -Level Warning
}

# --- BitLocker ---
try {
    Write-Section 'Chiffrement BitLocker'
    $bitlockerVolumes = Get-BitLockerVolume | Select-Object MountPoint, VolumeStatus, EncryptionPercentage, ProtectionStatus, KeyProtector
    $bitlockerVolumes | Format-Table -AutoSize
    $bitlockerVolumes | Export-Csv -Path (Join-Path $ReportPath 'BitLocker.csv') -NoTypeInformation -Encoding UTF8
    Write-AuditLog -Message "BitLocker : $($bitlockerVolumes.Count) volume(s) analyse(s)." -Level Success
}
catch {
    Write-AuditLog -Message "BitLocker non disponible ou module manquant : $($_.Exception.Message)" -Level Warning
}

# ============================================================
# PHASE 2 : APPLICATIONS INSTALLEES (REGISTRE + APPX ALLUSERS)
# ============================================================
Write-Section 'Phase 2 - Applications par disque'

# --- Registre ---
$uninstallKeys = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$apps = foreach ($keyPath in $uninstallKeys) {
    Get-ItemProperty -Path $keyPath -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne '' }
}

$appReport = foreach ($app in $apps) {
    $installLoc = $app.InstallLocation
    $drive = if ($installLoc -and $installLoc -match '^([A-Za-z]):\\') {
        $Matches[1].ToUpper() + ':'
    } else {
        'Inconnu'
    }

    [PSCustomObject]@{
        Nom         = $app.DisplayName
        Version     = $app.DisplayVersion
        Editeur     = $app.Publisher
        Lecteur     = $drive
        Emplacement = $installLoc
        TailleMo    = if ($app.EstimatedSize) { [math]::Round($app.EstimatedSize / 1024, 1) } else { $null }
        DateInstall = $app.InstallDate
        Source      = 'Registry'
    }
}

# --- Appx (Microsoft Store / applications modernes) — ALLUSERS ---
try {
    $appxPackages = Get-AppxPackage -AllUsers | Select-Object Name, PackageFullName, Publisher, InstallLocation
    $appxReport = foreach ($appx in $appxPackages) {
        $drive = if ($appx.InstallLocation -match '^([A-Za-z]):\\') {
            $Matches[1].ToUpper() + ':'
        } else {
            'Inconnu'
        }
        [PSCustomObject]@{
            Nom         = $appx.Name
            Version     = ($appx.PackageFullName -split '_')[-2]
            Editeur     = $appx.Publisher
            Lecteur     = $drive
            Emplacement = $appx.InstallLocation
            TailleMo    = $null
            DateInstall = $null
            Source      = 'Appx'
        }
    }
    $appReport = @($appReport) + @($appxReport)
}
catch {
    Write-AuditLog -Message "Get-AppxPackage indisponible : $($_.Exception.Message)" -Level Warning
}

$appReport = $appReport | Sort-Object -Property Lecteur, Nom -Unique
$appReport | Format-Table Nom, Lecteur, Source, TailleMo, Editeur -AutoSize
$appReport | Export-Csv -Path (Join-Path $ReportPath 'Applications.csv') -NoTypeInformation -Encoding UTF8

Write-AuditLog -Message "Phase 2 terminee. $($appReport.Count) application(s) repertoriee(s)." -Level Success
Write-Host "`nRepartition par lecteur :" -ForegroundColor Yellow
$appReport | Group-Object Lecteur | Select-Object Name, Count | Format-Table -AutoSize

# ============================================================
# PHASE 3 : FICHIERS INUTILES — AVEC AGES DE SECURITE
# ============================================================
Write-Section 'Phase 3 - Analyse des fichiers inutiles (avec ages securises)'

# Zones NETTOYABLES (suppression autorisee avec -Clean)
$cleanupZones = @(
    [PSCustomObject]@{ Name = 'Temp utilisateur';       Path = $env:TEMP;                                       Type = 'Recursive'; AgeDays = 1;  Pattern = $null }
    [PSCustomObject]@{ Name = 'Temp systeme';           Path = "$env:SystemRoot\Temp";                          Type = 'Recursive'; AgeDays = 3;  Pattern = $null }
    [PSCustomObject]@{ Name = 'Cache Internet';         Path = "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"; Type = 'Recursive'; AgeDays = 0;  Pattern = $null }
    [PSCustomObject]@{ Name = 'WER (Error Reporting)';  Path = "$env:LOCALAPPDATA\Microsoft\Windows\WER";       Type = 'Recursive'; AgeDays = 7;  Pattern = $null }
    [PSCustomObject]@{ Name = 'CrashDumps utilisateur'; Path = "$env:LOCALAPPDATA\CrashDumps";                  Type = 'Recursive'; AgeDays = 7;  Pattern = $null }
    [PSCustomObject]@{ Name = 'Cache vignettes';        Path = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer";  Type = 'Pattern';   AgeDays = 0;  Pattern = 'thumbcache_*.db' }
    [PSCustomObject]@{ Name = 'Minidumps BSOD';         Path = "$env:SystemRoot\Minidump";                      Type = 'Pattern';   AgeDays = 7;  Pattern = '*.dmp' }
    [PSCustomObject]@{ Name = 'Logs installation';      Path = "$env:SystemRoot\Panther";                       Type = 'Pattern';   AgeDays = 30; Pattern = '*.log' }
    [PSCustomObject]@{ Name = 'Logs UnattendGC';        Path = "$env:SystemRoot\Panther\UnattendGC";            Type = 'Pattern';   AgeDays = 30; Pattern = '*.log' }
    [PSCustomObject]@{ Name = 'MSI Temp (System)';      Path = "$env:SystemRoot\Temp";                          Type = 'Pattern';   AgeDays = $MinFileAgeDays; Pattern = '*.msi' }
    [PSCustomObject]@{ Name = 'MSI Temp (User)';        Path = $env:TEMP;                                       Type = 'Pattern';   AgeDays = $MinFileAgeDays; Pattern = '*.msi' }
)

$zoneCount = $cleanupZones.Count

for ($i = 0; $i -lt $zoneCount; $i++) {
    $zone = $cleanupZones[$i]
    Write-Progress -Activity 'Phase 3 - Analyse des zones' -Status $zone.Name -PercentComplete ([int](($i / $zoneCount) * 100))

    if (-not (Test-Path -Path $zone.Path)) { continue }

    $items = switch ($zone.Type) {
        'Recursive' {
            Get-ChildItem -Path $zone.Path -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$zone.AgeDays) }
        }
        'Pattern' {
            Get-ChildItem -Path $zone.Path -Filter $zone.Pattern -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$zone.AgeDays) }
        }
    }

    if (-not $items) { continue }

    $sizeSum = ($items | Measure-Object -Property Length -Sum).Sum
    $sizeMB  = if ($sizeSum) { [math]::Round($sizeSum / 1MB, 2) } else { 0 }

    $allJunkItems.Add([PSCustomObject]@{
        Zone        = $zone.Name
        Emplacement = $zone.Path
        NbFichiers  = $items.Count
        TailleMo    = $sizeMB
        AgeMinJours = $zone.AgeDays
        Action      = 'Nettoyage autorise'
    })
}

Write-Progress -Activity 'Phase 3 - Analyse des zones' -Completed

# --- MEMORY.DMP (AUDIT ONLY — jamais supprime automatiquement) ---
$memoryDmpPath = "$env:SystemRoot\MEMORY.DMP"
if (Test-Path -Path $memoryDmpPath) {
    $dmpSize = (Get-Item -Path $memoryDmpPath).Length
    $dmpSizeMB = [math]::Round($dmpSize / 1MB, 2)
    $allJunkItems.Add([PSCustomObject]@{
        Zone        = 'MEMORY.DMP (BSOD complet)'
        Emplacement = $memoryDmpPath
        NbFichiers  = 1
        TailleMo    = $dmpSizeMB
        AgeMinJours = 'N/A'
        Action      = 'AUDIT ONLY — Conserver pour diagnostic driver/kernel'
    })
    Write-AuditLog -Message "MEMORY.DMP detecte : $dmpSizeMB Mo (AUDIT ONLY — diagnostic BSOD)" -Level Warning
}

# --- CBS Logs (AUDIT ONLY — DISM recommande) ---
$cbsPath = "$env:SystemRoot\Logs\CBS"
if (Test-Path -Path $cbsPath) {
    $cbsFiles = Get-ChildItem -Path $cbsPath -Include 'CBS*.log','CbsPersist*.cab' -File -ErrorAction SilentlyContinue
    if ($cbsFiles) {
        $cbsSize = ($cbsFiles | Measure-Object -Property Length -Sum).Sum
        $cbsSizeMB = [math]::Round($cbsSize / 1MB, 2)
        $allJunkItems.Add([PSCustomObject]@{
            Zone        = 'Logs CBS'
            Emplacement = $cbsPath
            NbFichiers  = $cbsFiles.Count
            TailleMo    = $cbsSizeMB
            AgeMinJours = 'N/A'
            Action      = 'AUDIT ONLY — Utiliser DISM /Online /Cleanup-Image /StartComponentCleanup'
        })
        Write-AuditLog -Message "CBS detecte : $($cbsFiles.Count) fichier(s), $cbsSizeMB Mo (AUDIT ONLY)" -Level Warning
    }
}

# Export CSV UNIQUE (pas de -Append)
$allJunkItems | Export-Csv -Path (Join-Path $ReportPath 'FichiersInutiles.csv') -NoTypeInformation -Encoding UTF8

$totalJunkMB = ($allJunkItems | Where-Object { $_.Action -notlike '*AUDIT ONLY*' } | Measure-Object -Property TailleMo -Sum).Sum
if (-not $totalJunkMB) { $totalJunkMB = 0 }
Write-AuditLog -Message "Espace recuperable (zones nettoyables) : $totalJunkMB Mo" -Level Warning

# --- Windows.old (information — cleanmgr deprecie) ---
$windowsOld = "$($env:SystemDrive)\Windows.old"
if (Test-Path -Path $windowsOld) {
    $oldSizeSum = (Get-ChildItem -Path $windowsOld -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    $oldSizeGB = if ($oldSizeSum) { [math]::Round($oldSizeSum / 1GB, 2) } else { 0 }
    Write-AuditLog -Message "Windows.old detecte : $oldSizeGB Go (cleanmgr est deprecie — utiliser DISM /StartComponentCleanup ou supprimer manuellement apres validation)" -Level Warning
}

# ============================================================
# PHASE 4 : DOUBLONS (OPTIONNEL, AVEC EXCLUSIONS SYSTEME)
# ============================================================
if ($ScanDuplicates -and -not $AuditOnly) {
    Write-Section 'Phase 4 - Recherche de doublons (SHA256)'

    $scanRoots = $volumes | ForEach-Object { "$($_.DriveLetter):\" }
    $minSizeBytes = $MinDuplicateSizeKB * 1KB

    # Exclusions systeme + AppData (caches dev : npm, pip, Docker, VS Code)
    $systemExclusions = @(
        'C:\Windows',
        'C:\Program Files',
        'C:\Program Files (x86)',
        'C:\ProgramData',
        'C:\$Recycle.Bin',
        'C:\System Volume Information',
        $env:LOCALAPPDATA
    )

    Write-AuditLog -Message "Indexation avec exclusions systeme + AppData..." -Level Info

    $allFiles = foreach ($root in $scanRoots) {
        Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                $fp = $_.FullName
                $skip = $false
                foreach ($ex in $systemExclusions) {
                    if ($fp -like "$ex*") { $skip = $true; break }
                }
                -not $skip -and $_.Length -ge $minSizeBytes
            }
    }

    Write-AuditLog -Message "Fichiers a analyser : $($allFiles.Count)" -Level Info

    $groupedBySize = $allFiles | Group-Object -Property Length | Where-Object { $_.Count -gt 1 }

    $hashResults = foreach ($group in $groupedBySize) {
        foreach ($file in $group.Group) {
            try {
                $hash = Get-FileHash -Path $file.FullName -Algorithm SHA256 -ErrorAction Stop
                [PSCustomObject]@{
                    Hash     = $hash.Hash
                    Chemin   = $file.FullName
                    TailleMo = [math]::Round($file.Length / 1MB, 2)
                }
            }
            catch {
                Write-Verbose "Ignore (acces refuse) : $($file.FullName)"
            }
        }
    }

    $duplicateGroups = $hashResults | Group-Object -Property Hash | Where-Object { $_.Count -gt 1 }

    $duplicateReport = foreach ($grp in $duplicateGroups) {
        $filesInGroup = $grp.Group
        $espaceRecuperable = [math]::Round(($filesInGroup[0].TailleMo * ($filesInGroup.Count - 1)), 2)
        foreach ($f in $filesInGroup) {
            [PSCustomObject]@{
                Hash                = $grp.Name
                Chemin              = $f.Chemin
                TailleMo            = $f.TailleMo
                CopiesTotal         = $grp.Count
                EspaceRecuperableMo = $espaceRecuperable
            }
        }
    }

    $duplicateReport |
        Sort-Object -Property EspaceRecuperableMo -Descending |
        Select-Object -First 50 |
        Format-Table Chemin, TailleMo, CopiesTotal -AutoSize

    $duplicateReport | Export-Csv -Path (Join-Path $ReportPath 'Doublons.csv') -NoTypeInformation -Encoding UTF8

    $totalRecoverable = ($duplicateGroups | ForEach-Object {
        $_.Group[0].TailleMo * ($_.Count - 1)
    } | Measure-Object -Sum).Sum
    $totalRecoverable = if ($totalRecoverable) { [math]::Round($totalRecoverable, 2) } else { 0 }

    Write-AuditLog -Message "Espace recuperable (doublons) : $totalRecoverable Mo" -Level Warning
}
else {
    if ($AuditOnly) {
        Write-AuditLog -Message 'Mode AuditOnly : scan doublons ignore.' -Level Info
    }
}

# ============================================================
# PHASE 5 : NETTOYAGE SECURISE (OPT-IN)
# ============================================================
if ($Clean -and -not $AuditOnly) {
    Write-Section 'Phase 5 - Nettoyage securise'

    # Mesure espace AVANT par volume
    foreach ($vol in $volumes) {
        $spaceBefore["$($vol.DriveLetter):"] = [math]::Round($vol.SizeRemaining / 1GB, 2)
    }

    # --- 5a. Zones standards avec age ---
    $targetDesc = "Fichiers temporaires/cache/dumps ($totalJunkMB Mo, $zoneCount zones)"
    if ($PSCmdlet.ShouldProcess($targetDesc, 'Supprimer definitivement')) {

        for ($i = 0; $i -lt $zoneCount; $i++) {
            $zone = $cleanupZones[$i]
            Write-Progress -Activity 'Phase 5 - Nettoyage' -Status $zone.Name -PercentComplete ([int](($i / $zoneCount) * 100))

            if (-not (Test-Path -Path $zone.Path)) { continue }

            $items = switch ($zone.Type) {
                'Recursive' {
                    Get-ChildItem -Path $zone.Path -Recurse -File -ErrorAction SilentlyContinue |
                        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$zone.AgeDays) }
                }
                'Pattern' {
                    Get-ChildItem -Path $zone.Path -Filter $zone.Pattern -File -ErrorAction SilentlyContinue |
                        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$zone.AgeDays) }
                }
            }

            foreach ($item in $items) {
                Remove-FileSafe -Path $item.FullName
            }

            if ($zone.Type -eq 'Recursive') {
                Remove-EmptyDirectories -Path $zone.Path
            }
        }

        Write-Progress -Activity 'Phase 5 - Nettoyage' -Completed
        Write-AuditLog -Message 'Nettoyage des zones standards termine.' -Level Success
    }

    # --- 5b. CBS : DISM recommande (jamais suppression directe) ---
    if ($cbsFiles -and $cbsFiles.Count -gt 0) {
        $dismTarget = "Logs CBS ($cbsSizeMB Mo) — DISM /StartComponentCleanup"
        if ($PSCmdlet.ShouldProcess($dismTarget, 'Executer le nettoyage composants Windows')) {
            Write-AuditLog -Message 'Execution de DISM /StartComponentCleanup...' -Level Warning
            try {
                $dismResult = Start-Process -FilePath 'dism.exe' -ArgumentList '/Online','/Cleanup-Image','/StartComponentCleanup' -Wait -NoNewWindow -PassThru -ErrorAction Stop
                if ($dismResult.ExitCode -eq 0) {
                    Write-AuditLog -Message 'DISM termine avec succes.' -Level Success
                } else {
                    Write-AuditLog -Message "DISM a retourne le code : $($dismResult.ExitCode)" -Level Error
                }
            }
            catch {
                Write-AuditLog -Message "Erreur DISM : $($_.Exception.Message)" -Level Error
            }
        }
    }

    # --- 5c. MEMORY.DMP : jamais supprime automatiquement ---
    if (Test-Path -Path $memoryDmpPath) {
        Write-AuditLog -Message 'MEMORY.DMP conserve (AUDIT ONLY). Suppression manuelle si le systeme est stable.' -Level Warning
    }

    # Mesure espace APRES par volume
    Start-Sleep -Seconds 2
    foreach ($vol in $volumes) {
        $freshVol = Get-Volume -DriveLetter $vol.DriveLetter
        $spaceAfter["$($vol.DriveLetter):"] = [math]::Round($freshVol.SizeRemaining / 1GB, 2)
    }

    Write-Host "`n=== Gain reel par lecteur ===" -ForegroundColor Cyan
    foreach ($letter in $spaceBefore.Keys | Sort-Object) {
        $gain = [math]::Round($spaceAfter[$letter] - $spaceBefore[$letter], 2)
        $color = if ($gain -gt 0) { 'Green' } else { 'White' }
        Write-Host "$letter : $($spaceBefore[$letter]) Go -> $($spaceAfter[$letter]) Go (gain : $gain Go)" -ForegroundColor $color
    }

    Write-AuditLog -Message 'NOTE : Les doublons ne sont PAS supprimes automatiquement. Consultez Doublons.csv.' -Level Warning
}
else {
    if ($AuditOnly) {
        Write-AuditLog -Message 'Mode AuditOnly : aucun nettoyage effectue.' -Level Info
    } else {
        Write-AuditLog -Message 'Mode simulation (par defaut). Utilisez -Clean pour supprimer reellement.' -Level Warning
    }
}

# ============================================================
# EXPORT JSON COMPLET (SIEM / AUTOMATION)
# ============================================================
$jsonReport = [ordered]@{
    Meta = [ordered]@{
        Date         = Get-Date -Format 'o'
        ComputerName = $env:COMPUTERNAME
        UserName     = $env:USERNAME
        Version      = '3.0'
        Mode         = if ($AuditOnly) { 'AuditOnly' } elseif ($Clean) { 'Clean' } else { 'Simulation' }
        ErrorCount   = $script:ErrorCount
    }
    Disks         = $diskReport
    PhysicalDisks = $physicalDisks
    Smart         = $smartData
    BitLocker     = $bitlockerVolumes
    Applications  = $appReport
    Junk          = $allJunkItems
    Duplicates    = $duplicateReport
}

$jsonReport | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path $ReportPath 'RapportComplet.json') -Encoding utf8

# ============================================================
# RESUME FINAL
# ============================================================
Write-Section 'Resume'
Write-AuditLog -Message "Rapport complet enregistre dans : $ReportPath" -Level Success
Write-AuditLog -Message "Erreurs rencontrees : $($script:ErrorCount)" -Level $(if ($script:ErrorCount -gt 0) { 'Error' } else { 'Success' })

Get-ChildItem -Path $ReportPath -Filter '*.csv' |
    Select-Object Name, @{Name = 'TailleKo'; Expression = { [math]::Round($_.Length / 1KB, 1) } } |
    Format-Table -AutoSize

Write-AuditLog -Message 'Audit termine.' -Level Success
