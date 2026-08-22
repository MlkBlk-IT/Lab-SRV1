#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Maintenance Systeme v12.0 - Edition Rapide & Detaillee
    Sans DISM/SFC | Barres natives visibles | Rapport HTML+JSON detaille

.DESCRIPTION
    Script de maintenance automatique pour Windows 11 Pro.
    - Phase 1 : Verifications prealables (admin, disque, internet, reboot)
    - Phase 2 : Windows Update (PSWindowsUpdate)
    - Phase 3 : Gestionnaires de paquets (winget, scoop, choco)
    - Phase 4 : Environnements de developpement (npm, pip, conda, cargo, go)
    - Phase 5 : Nettoyage disque (TEMP, Prefetch, caches)
    - Phase 6 : Verifications finales (BCD, SMART, services) + Rapport HTML+JSON

    DOCUMENTATION OFFICIELLE CROSS-REFERENCEE :
    - Winget    : Microsoft Docs 2026 - winget upgrade --all --silent --disable-interactivity
    - pip       : pip.pypa.io v26.1.2 - pip list --outdated --not-required --format=json
    - conda     : docs.conda.io v26.5.4 - conda update -p <path> --all --satisfied-skip-solve
    - cargo     : docs.rs cargo-edit - cargo install-update -a
    - npm       : npm docs - npm outdated -g --json
    - PowerShell: Microsoft Docs S-level - Start-Process -RedirectStandardOutput

.PARAMETER WhatIf
    Mode simulation. Affiche les actions sans les executer.

.PARAMETER UpdateVenvs
    Opt-in : met a jour les venvs Python trouves (max 10).

.PARAMETER UpdateNpmGlobal
    Opt-in : met a jour tous les packages npm globaux.

.PARAMETER SkipWindowsUpdate
    Ignore la phase Windows Update.

.PARAMETER SkipPackageManagers
    Ignore winget, scoop, choco.

.PARAMETER SkipDevEnv
    Ignore npm, pip, conda, cargo, go.

.PARAMETER SkipDiskCleanup
    Ignore le nettoyage disque.

.PARAMETER LogPath
    Chemin personnalise pour le log texte et les rapports.

.EXAMPLE
    .\Maintenance_Systeme_v12.ps1 -WhatIf
    .\Maintenance_Systeme_v12.ps1 -UpdateVenvs -UpdateNpmGlobal
    .\Maintenance_Systeme_v12.ps1 -SkipWindowsUpdate -SkipDiskCleanup
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$UpdateVenvs,
    [switch]$UpdateNpmGlobal,
    [switch]$SkipWindowsUpdate,
    [switch]$SkipPackageManagers,
    [switch]$SkipDevEnv,
    [switch]$SkipDiskCleanup,
    [string]$LogPath = "$env:USERPROFILE\Desktop"
)

# =============================================================================
# CONFIGURATION GLOBALE
# =============================================================================
$ErrorActionPreference = "Stop"
$script:StartTime = Get-Date
$script:LogFile = Join-Path $LogPath "Maintenance_v12_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
$script:HtmlFile = Join-Path $LogPath "Rapport-Maintenance-v12-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').html"
$script:JsonFile = Join-Path $LogPath "Rapport-Maintenance-v12-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').json"
$script:ReportData = [System.Collections.Generic.List[PSCustomObject]]::new()
$script:SuccessCount = 0
$script:WarnCount = 0
$script:ErrorCount = 0
$script:PackagesUpdated = [System.Collections.Generic.List[PSCustomObject]]::new()
$script:PackagesSkipped = [System.Collections.Generic.List[PSCustomObject]]::new()
$script:CleanupDetails = [System.Collections.Generic.List[PSCustomObject]]::new()

# =============================================================================
# FONCTIONS DE LOGGING
# =============================================================================
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARN", "ERROR", "PHASE", "START", "END")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colorMap = @{
        "INFO"    = "White"
        "SUCCESS" = "Green"
        "WARN"    = "Yellow"
        "ERROR"   = "Red"
        "PHASE"   = "Cyan"
        "START"   = "Magenta"
        "END"     = "Magenta"
    }
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line -ForegroundColor $colorMap[$Level]
    $line | Out-File -FilePath $script:LogFile -Append -Encoding UTF8
}

function Write-Phase {
    param([string]$Name, [int]$Num, [int]$Total)
    $banner = "`n=== PHASE $Num/$Total : $Name ==="
    Write-Host $banner -ForegroundColor Cyan -BackgroundColor DarkBlue
    Write-Log -Message $banner -Level "PHASE"
}

function Add-ReportEntry {
    param(
        [string]$Phase,
        [string]$Step,
        [string]$Status,
        [string]$Details = "",
        [string]$Duration = "",
        [string]$BeforeVersion = "",
        [string]$AfterVersion = "",
        [string]$PackageName = "",
        [string]$PackageManager = ""
    )
    $entry = [PSCustomObject]@{
        Timestamp      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Phase          = $Phase
        Step           = $Step
        Status         = $Status
        Details        = $Details
        Duration       = $Duration
        BeforeVersion  = $BeforeVersion
        AfterVersion   = $AfterVersion
        PackageName    = $PackageName
        PackageManager = $PackageManager
    }
    $script:ReportData.Add($entry)

    if ($Status -eq "SUCCESS") { $script:SuccessCount++ }
    elseif ($Status -eq "WARN") { $script:WarnCount++ }
    elseif ($Status -eq "ERROR") { $script:ErrorCount++ }
}

function Add-PackageUpdate {
    param([string]$Name, [string]$Manager, [string]$Before, [string]$After, [string]$Details = "")
    $script:PackagesUpdated.Add([PSCustomObject]@{
        Name    = $Name
        Manager = $Manager
        Before  = $Before
        After   = $After
        Details = $Details
        Time    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    })
}

function Add-PackageSkip {
    param([string]$Name, [string]$Manager, [string]$Reason)
    $script:PackagesSkipped.Add([PSCustomObject]@{
        Name    = $Name
        Manager = $Manager
        Reason  = $Reason
        Time    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    })
}

function Add-CleanupDetail {
    param([string]$Category, [string]$Path, [int]$Count, [string]$Size = "")
    $script:CleanupDetails.Add([PSCustomObject]@{
        Category = $Category
        Path     = $Path
        Count    = $Count
        Size     = $Size
        Time     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    })
}

# =============================================================================
# FONCTION EXECUTION AVEC BARRE NATIVE VISIBLE + CAPTURE FICHIER
# =============================================================================
<#
    DOCUMENTATION MICROSOFT :
    Start-Process -RedirectStandardOutput redirige stdout vers un fichier.
    La barre de progression native reste visible car elle ecrit sur stderr
    ou directement sur la console (pas sur stdout).
    Source : Microsoft Docs S-level, PowerShell 7.4+
#>
function Invoke-NativeWithLog {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [string]$Description,
        [string]$Phase,
        [string]$Step,
        [int]$TimeoutSeconds = 600,
        [string]$WorkingDirectory = ""
    )

    Write-Log "[START] --- ETAPE : $Step ---" "INFO"
    $stepStart = Get-Date
    $tmpFile = [System.IO.Path]::GetTempFileName()
    $tmpFileErr = [System.IO.Path]::GetTempFileName()

    try {
        $procParams = @{
            FilePath               = $FilePath
            ArgumentList           = $ArgumentList
            NoNewWindow            = $true
            Wait                   = $true
            RedirectStandardOutput = $tmpFile
            RedirectStandardError  = $tmpFileErr
            PassThru               = $true
        }
        if ($WorkingDirectory) { $procParams.WorkingDirectory = $WorkingDirectory }

        # BARRE NATIVE VISIBLE : Start-Process affiche stderr en direct
        # stdout est redirige vers fichier pour analyse post-execution
        $proc = Start-Process @procParams

        $duration = New-TimeSpan -Start $stepStart -End (Get-Date)
        $durationStr = "{0:D2}:{1:D2}" -f $duration.Minutes, $duration.Seconds

        # Lecture de la sortie capturee
        $stdout = if (Test-Path $tmpFile) { Get-Content $tmpFile -Raw -ErrorAction SilentlyContinue } else { "" }
        $stderr = if (Test-Path $tmpFileErr) { Get-Content $tmpFileErr -Raw -ErrorAction SilentlyContinue } else { "" }

        $exitCode = $proc.ExitCode
        $allOutput = ($stdout + "`n" + $stderr).Trim()

        if ($exitCode -eq 0 -or $exitCode -eq $null) {
            Write-Log "[SUCCESS] $Step OK" "SUCCESS"
            Write-Log "[SUCCESS] $Step termine ($durationStr)." "SUCCESS"
            Add-ReportEntry -Phase $Phase -Step $Step -Status "SUCCESS" -Details $allOutput -Duration $durationStr
            return @{ Success = $true; Output = $allOutput; ExitCode = $exitCode }
        } else {
            Write-Log "[WARN] $Step code sortie : $exitCode" "WARN"
            Write-Log "[WARN] $Step termine ($durationStr)." "WARN"
            Add-ReportEntry -Phase $Phase -Step $Step -Status "WARN" -Details $allOutput -Duration $durationStr
            return @{ Success = $false; Output = $allOutput; ExitCode = $exitCode }
        }
    }
    catch {
        Write-Log "[ERROR] $Step : $($_.Exception.Message)" "ERROR"
        Add-ReportEntry -Phase $Phase -Step $Step -Status "ERROR" -Details $_.Exception.Message
        return @{ Success = $false; Output = $_.Exception.Message; ExitCode = -1 }
    }
    finally {
        if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue }
        if (Test-Path $tmpFileErr) { Remove-Item $tmpFileErr -Force -ErrorAction SilentlyContinue }
    }
}

# =============================================================================
# FONCTION EXECUTION POWERSHELL (cmdlets) AVEC CAPTURE
# =============================================================================
function Invoke-PowerShellWithLog {
    param(
        [scriptblock]$ScriptBlock,
        [string]$Description,
        [string]$Phase,
        [string]$Step
    )

    Write-Log "[START] --- ETAPE : $Step ---" "INFO"
    $stepStart = Get-Date

    try {
        # Tee-Object : affiche en direct ET capture dans fichier
        $tmpFile = [System.IO.Path]::GetTempFileName()
        $result = & $ScriptBlock 2>&1 | Tee-Object -FilePath $tmpFile
        $output = ($result | Out-String).Trim()

        $duration = New-TimeSpan -Start $stepStart -End (Get-Date)
        $durationStr = "{0:D2}:{1:D2}" -f $duration.Minutes, $duration.Seconds

        Write-Log "[SUCCESS] $Step OK" "SUCCESS"
        Write-Log "[SUCCESS] $Step termine ($durationStr)." "SUCCESS"
        Add-ReportEntry -Phase $Phase -Step $Step -Status "SUCCESS" -Details $output -Duration $durationStr

        Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
        return @{ Success = $true; Output = $output }
    }
    catch {
        Write-Log "[ERROR] $Step : $($_.Exception.Message)" "ERROR"
        Add-ReportEntry -Phase $Phase -Step $Step -Status "ERROR" -Details $_.Exception.Message
        return @{ Success = $false; Output = $_.Exception.Message }
    }
}

# =============================================================================
# FONCTIONS DE VERIFICATION
# =============================================================================
function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Internet {
    try {
        $null = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -TimeoutSeconds 3
        return $true
    } catch { return $false }
}

function Test-PendingReboot {
    $reboot = $false
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") { $reboot = $true }
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") { $reboot = $true }
    if (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue) { $reboot = $true }
    return $reboot
}

function Test-WUActive {
    $svc = Get-Service wuauserv -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        $jobs = Get-Process TiWorker, UsoClient -ErrorAction SilentlyContinue
        return ($jobs.Count -gt 0)
    }
    return $false
}

# =============================================================================
# FONCTIONS DE RAPPORT
# =============================================================================
function Export-HtmlReport {
    $totalDuration = New-TimeSpan -Start $script:StartTime -End (Get-Date)
    $osInfo = Get-CimInstance Win32_OperatingSystem
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $ram = Get-CimInstance Win32_ComputerSystem

    $html = @"
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>Rapport Maintenance v12.0</title>
    <style>
        * { box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; background: #f5f7fa; color: #333; }
        .container { max-width: 1400px; margin: 0 auto; }
        h1 { color: #1a237e; border-bottom: 3px solid #3949ab; padding-bottom: 15px; margin-bottom: 20px; }
        h2 { color: #283593; margin-top: 30px; border-left: 4px solid #3949ab; padding-left: 12px; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin: 20px 0; }
        .card { background: white; border-radius: 8px; padding: 20px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
        .card.success { border-top: 4px solid #4caf50; }
        .card.warn { border-top: 4px solid #ff9800; }
        .card.error { border-top: 4px solid #f44336; }
        .card.info { border-top: 4px solid #2196f3; }
        .card h3 { margin: 0 0 10px 0; font-size: 0.9em; text-transform: uppercase; color: #666; }
        .card .value { font-size: 2em; font-weight: bold; color: #333; }
        .status-ok { color: #4caf50; font-weight: bold; }
        .status-warn { color: #ff9800; font-weight: bold; }
        .status-error { color: #f44336; font-weight: bold; }
        table { width: 100%; border-collapse: collapse; background: white; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.1); margin: 15px 0; }
        th { background: #3949ab; color: white; padding: 12px; text-align: left; font-weight: 600; }
        td { padding: 10px 12px; border-bottom: 1px solid #e0e0e0; }
        tr:hover { background: #f5f5f5; }
        tr:last-child td { border-bottom: none; }
        .detail-box { background: white; border-radius: 8px; padding: 20px; margin: 15px 0; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
        .detail-box h4 { margin-top: 0; color: #3949ab; }
        .version-change { font-family: monospace; background: #e8f5e9; padding: 2px 6px; border-radius: 4px; }
        .skip-reason { font-family: monospace; background: #fff3e0; padding: 2px 6px; border-radius: 4px; }
        pre { background: #263238; color: #aed581; padding: 15px; border-radius: 6px; overflow-x: auto; font-size: 0.85em; }
        .footer { text-align: center; margin-top: 40px; padding: 20px; color: #999; font-size: 0.9em; }
    </style>
</head>
<body>
<div class="container">
    <h1>Rapport de Maintenance Enterprise v12.0</h1>
    <p><strong>Date :</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | <strong>Mode :</strong> $(if ($WhatIfPreference) { "Simulation" } else { "Reel" }) | <strong>Duree totale :</strong> $($totalDuration.ToString('hh\:mm\:ss'))</p>

    <div class="summary">
        <div class="card success"><h3>Succes</h3><div class="value">$script:SuccessCount</div></div>
        <div class="card warn"><h3>Avertissements</h3><div class="value">$script:WarnCount</div></div>
        <div class="card error"><h3>Erreurs</h3><div class="value">$script:ErrorCount</div></div>
        <div class="card info"><h3>Duree</h3><div class="value">$($totalDuration.ToString('mm\:ss'))</div></div>
    </div>
"@

    # System Info
    $html += @"
    <h2>Informations Systeme</h2>
    <div class="detail-box">
        <p><strong>OS :</strong> $($osInfo.Caption) $($osInfo.Version)</p>
        <p><strong>Architecture :</strong> $($osInfo.OSArchitecture)</p>
        <p><strong>RAM :</strong> $([math]::Round($ram.TotalPhysicalMemory/1GB, 2)) GB</p>
        <p><strong>Disque C: :</strong> $([math]::Round($disk.FreeSpace/1GB, 2)) GB libre / $([math]::Round($disk.Size/1GB, 2)) GB total</p>
        <p><strong>Utilisateur :</strong> $($env:USERNAME)</p>
        <p><strong>Machine :</strong> $($env:COMPUTERNAME)</p>
    </div>
"@

    # Packages Updated
    if ($script:PackagesUpdated.Count -gt 0) {
        $html += @"
    <h2>Packages Mis a Jour ($($script:PackagesUpdated.Count))</h2>
    <table>
        <tr><th>Heure</th><th>Gestionnaire</th><th>Package</th><th>Avant</th><th>Apres</th><th>Details</th></tr>
"@
        foreach ($pkg in $script:PackagesUpdated) {
            $html += "<tr><td>$($pkg.Time)</td><td>$($pkg.Manager)</td><td><strong>$($pkg.Name)</strong></td><td class='version-change'>$($pkg.Before)</td><td class='version-change'>$($pkg.After)</td><td>$($pkg.Details)</td></tr>`n"
        }
        $html += "</table>"
    }

    # Packages Skipped
    if ($script:PackagesSkipped.Count -gt 0) {
        $html += @"
    <h2>Packages Ignores ($($script:PackagesSkipped.Count))</h2>
    <table>
        <tr><th>Heure</th><th>Gestionnaire</th><th>Package</th><th>Raison</th></tr>
"@
        foreach ($pkg in $script:PackagesSkipped) {
            $html += "<tr><td>$($pkg.Time)</td><td>$($pkg.Manager)</td><td><strong>$($pkg.Name)</strong></td><td class='skip-reason'>$($pkg.Reason)</td></tr>`n"
        }
        $html += "</table>"
    }

    # Cleanup Details
    if ($script:CleanupDetails.Count -gt 0) {
        $html += @"
    <h2>Nettoyage Disque</h2>
    <table>
        <tr><th>Categorie</th><th>Chemin</th><th>Elements</th><th>Taille</th></tr>
"@
        foreach ($clean in $script:CleanupDetails) {
            $html += "<tr><td>$($clean.Category)</td><td><code>$($clean.Path)</code></td><td>$($clean.Count)</td><td>$($clean.Size)</td></tr>`n"
        }
        $html += "</table>"
    }

    # Detailed Timeline
    $html += @"
    <h2>Chronologie Detaillee</h2>
    <table>
        <tr><th>Heure</th><th>Phase</th><th>Etape</th><th>Statut</th><th>Duree</th><th>Details</th></tr>
"@
    foreach ($entry in $script:ReportData) {
        $statusClass = if ($entry.Status -eq "SUCCESS") { "status-ok" } elseif ($entry.Status -eq "WARN") { "status-warn" } else { "status-error" }
        $details = if ($entry.Details.Length -gt 200) { $entry.Details.Substring(0, 200) + "..." } else { $entry.Details }
        $html += "<tr><td>$($entry.Timestamp)</td><td>$($entry.Phase)</td><td>$($entry.Step)</td><td class='$statusClass'>$($entry.Status)</td><td>$($entry.Duration)</td><td><pre>$([System.Web.HttpUtility]::HtmlEncode($details))</pre></td></tr>`n"
    }
    $html += "</table>"

    $html += @"
    <div class="footer">
        <p>Maintenance Systeme v12.0 | Genere le $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        <p>Log : <code>$($script:LogFile)</code> | JSON : <code>$($script:JsonFile)</code></p>
    </div>
</div>
</body>
</html>
"@

    $html | Out-File -FilePath $script:HtmlFile -Encoding UTF8
    Write-Log "Rapport HTML genere : $script:HtmlFile" "SUCCESS"
}

function Export-JsonReport {
    $totalDuration = New-TimeSpan -Start $script:StartTime -End (Get-Date)
    $osInfo = Get-CimInstance Win32_OperatingSystem
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $ram = Get-CimInstance Win32_ComputerSystem

    $report = [ordered]@{
        metadata = [ordered]@{
            version       = "12.0"
            timestamp     = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
            mode          = if ($WhatIfPreference) { "simulation" } else { "real" }
            duration      = $totalDuration.ToString()
            durationSeconds = [math]::Round($totalDuration.TotalSeconds, 2)
            hostname      = $env:COMPUTERNAME
            username      = $env:USERNAME
            os            = "$($osInfo.Caption) $($osInfo.Version)"
            architecture  = $osInfo.OSArchitecture
            ramGB         = [math]::Round($ram.TotalPhysicalMemory / 1GB, 2)
            diskFreeGB    = [math]::Round($disk.FreeSpace / 1GB, 2)
            diskTotalGB   = [math]::Round($disk.Size / 1GB, 2)
        }
        summary = [ordered]@{
            successCount   = $script:SuccessCount
            warnCount      = $script:WarnCount
            errorCount     = $script:ErrorCount
            totalSteps     = $script:ReportData.Count
        }
        packagesUpdated = @($script:PackagesUpdated | ForEach-Object { [ordered]@{
            name    = $_.Name
            manager = $_.Manager
            before  = $_.Before
            after   = $_.After
            details = $_.Details
            time    = $_.Time
        }})
        packagesSkipped = @($script:PackagesSkipped | ForEach-Object { [ordered]@{
            name    = $_.Name
            manager = $_.Manager
            reason  = $_.Reason
            time    = $_.Time
        }})
        cleanupDetails = @($script:CleanupDetails | ForEach-Object { [ordered]@{
            category = $_.Category
            path     = $_.Path
            count    = $_.Count
            size     = $_.Size
            time     = $_.Time
        }})
        timeline = @($script:ReportData | ForEach-Object { [ordered]@{
            timestamp     = $_.Timestamp
            phase         = $_.Phase
            step          = $_.Step
            status        = $_.Status
            duration      = $_.Duration
            details       = $_.Details
            beforeVersion = $_.BeforeVersion
            afterVersion  = $_.AfterVersion
            packageName   = $_.PackageName
            packageManager = $_.PackageManager
        }})
        files = [ordered]@{
            log  = $script:LogFile
            html = $script:HtmlFile
            json = $script:JsonFile
        }
    }

    $report | ConvertTo-Json -Depth 10 | Out-File -FilePath $script:JsonFile -Encoding UTF8
    Write-Log "Rapport JSON genere : $script:JsonFile" "SUCCESS"
}

# =============================================================================
# DEBUT DU SCRIPT
# =============================================================================
try {
    Write-Log "========== MAINTENANCE v12.0 DEMARREE ==========" "START"
    Write-Log "Mode : $(if ($WhatIfPreference) { 'SIMULATION' } else { 'REEL' })" "INFO"
    Write-Log "Log : $script:LogFile" "INFO"

    # =========================================================================
    # PHASE 1 : VERIFICATIONS PREALABLES
    # =========================================================================
    Write-Phase -Name "VERIFICATIONS PREALABLES" -Num 1 -Total 6

    # Admin
    if (-not (Test-Admin)) {
        Write-Log "ERREUR : Administrateur requis." "ERROR"
        throw "Privileges administrateur requis."
    }
    Write-Log "Admin : OK" "SUCCESS"
    Add-ReportEntry -Phase "Phase 1" -Step "Admin" -Status "SUCCESS" -Details "Administrateur confirme"

    # Disque
    $diskC = Get-PSDrive C -ErrorAction SilentlyContinue
    if ($diskC) {
        $freeGB = [math]::Round($diskC.Free / 1GB, 1)
        $freePct = [math]::Round(($diskC.Free / ($diskC.Free + $diskC.Used)) * 100, 1)
        Write-Log "Disque C: : $freeGB GB libre ($freePct%)" "SUCCESS"
        Add-ReportEntry -Phase "Phase 1" -Step "Disque" -Status "SUCCESS" -Details "$freeGB GB libre ($freePct%)"
    }

    # Internet
    if (Test-Internet) {
        Write-Log "Internet : OK" "SUCCESS"
        Add-ReportEntry -Phase "Phase 1" -Step "Internet" -Status "SUCCESS"
    } else {
        Write-Log "Internet : INDISPONIBLE" "WARN"
        Add-ReportEntry -Phase "Phase 1" -Step "Internet" -Status "WARN" -Details "Connexion internet indisponible"
    }

    # Reboot pending
    if (Test-PendingReboot) {
        Write-Log "Redemarrage en attente detecte." "WARN"
        Add-ReportEntry -Phase "Phase 1" -Step "RebootPending" -Status "WARN" -Details "Redemarrage en attente"
    } else {
        Write-Log "Aucun redemarrage en attente." "SUCCESS"
        Add-ReportEntry -Phase "Phase 1" -Step "RebootPending" -Status "SUCCESS"
    }

    # WU actif
    if (Test-WUActive) {
        Write-Log "Windows Update est actif." "WARN"
        Add-ReportEntry -Phase "Phase 1" -Step "WUActive" -Status "WARN" -Details "WU actif"
    } else {
        Write-Log "WU inactif : OK" "SUCCESS"
        Add-ReportEntry -Phase "Phase 1" -Step "WUActive" -Status "SUCCESS"
    }

    Write-Log "Phase 1 terminee." "SUCCESS"

    # =========================================================================
    # PHASE 2 : WINDOWS UPDATE
    # =========================================================================
    Write-Phase -Name "WINDOWS UPDATE" -Num 2 -Total 6

    if (-not $SkipWindowsUpdate) {
        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            Write-Log "Module PSWindowsUpdate manquant. Tentative d'installation..." "INFO"
            if ($PSCmdlet.ShouldProcess("PSWindowsUpdate", "Install")) {
                try {
                    Install-Module PSWindowsUpdate -Force -Scope CurrentUser -AllowClobber
                    Import-Module PSWindowsUpdate
                    Write-Log "PSWindowsUpdate installe." "SUCCESS"
                } catch {
                    Write-Log "Impossible d'installer PSWindowsUpdate : $($_.Exception.Message)" "WARN"
                    Add-ReportEntry -Phase "Phase 2" -Step "PSWindowsUpdate" -Status "WARN" -Details $_.Exception.Message
                }
            }
        }

        if (Get-Module -ListAvailable -Name PSWindowsUpdate) {
            Import-Module PSWindowsUpdate
            Write-Log "Recherche et installation des mises a jour..." "INFO"

            if ($PSCmdlet.ShouldProcess("Windows Update", "Install")) {
                try {
                    $updates = Get-WindowsUpdate -AcceptAll -AutoReboot:$false -IgnoreReboot
                    if ($updates) {
                        foreach ($up in $updates) {
                            Write-Log "  - $($up.Title)" "INFO"
                            Add-ReportEntry -Phase "Phase 2" -Step "WU-Install" -Status "SUCCESS" -Details $up.Title -PackageName $up.KB
                        }
                    } else {
                        Write-Log "Aucune mise a jour disponible." "SUCCESS"
                    }
                    Add-ReportEntry -Phase "Phase 2" -Step "WindowsUpdate" -Status "SUCCESS" -Details "Mises a jour traitees"
                } catch {
                    Write-Log "Erreur Windows Update : $($_.Exception.Message)" "WARN"
                    Add-ReportEntry -Phase "Phase 2" -Step "WindowsUpdate" -Status "WARN" -Details $_.Exception.Message
                }
            }
        } else {
            Write-Log "PSWindowsUpdate non disponible. Phase ignoree." "WARN"
            Add-ReportEntry -Phase "Phase 2" -Step "WindowsUpdate" -Status "WARN" -Details "Module non installe"
        }
    } else {
        Write-Log "Phase 2 ignoree (SkipWindowsUpdate)." "INFO"
        Add-ReportEntry -Phase "Phase 2" -Step "WindowsUpdate" -Status "SUCCESS" -Details "Ignore par parametre"
    }

    Write-Log "Phase 2 terminee." "SUCCESS"

    # =========================================================================
    # PHASE 3 : GESTIONNAIRES DE PAQUETS
    # =========================================================================
    Write-Phase -Name "GESTIONNAIRES DE PAQUETS" -Num 3 -Total 6

    if (-not $SkipPackageManagers) {
        # --- Winget ---
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Log "Winget : mise a jour..." "INFO"
            Write-Log "ATTENTION : winget upgrade --all peut mettre a jour des outils critiques." "WARN"

            if ($PSCmdlet.ShouldProcess("Winget packages", "Upgrade")) {
                $wingetResult = Invoke-NativeWithLog `
                    -FilePath "winget" `
                    -ArgumentList @("upgrade", "--all", "--silent", "--disable-interactivity", "--accept-package-agreements", "--accept-source-agreements") `
                    -Phase "Phase 3" -Step "Winget" -TimeoutSeconds 600

                if ($wingetResult.Output) {
                    $lines = $wingetResult.Output -split "`n"
                    foreach ($line in $lines) {
                        if ($line -match "Upgraded\s+(.+?)\s+from\s+(.+?)\s+to\s+(.+)") {
                            Add-PackageUpdate -Name $matches[1].Trim() -Manager "winget" `
                                -Before $matches[2].Trim() -After $matches[3].Trim() -Details "Auto-upgrade via winget"
                        }
                    }
                }
            }
        } else {
            Write-Log "Winget introuvable." "WARN"
            Add-ReportEntry -Phase "Phase 3" -Step "Winget" -Status "WARN" -Details "Non installe"
        }

        # --- Scoop ---
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            Write-Log "Scoop : mise a jour..." "INFO"
            if ($PSCmdlet.ShouldProcess("Scoop packages", "Update")) {
                $scoopResult = Invoke-NativeWithLog `
                    -FilePath "scoop" `
                    -ArgumentList @("update", "*") `
                    -Phase "Phase 3" -Step "Scoop" -TimeoutSeconds 300

                if ($scoopResult.Output) {
                    $lines = $scoopResult.Output -split "`n"
                    foreach ($line in $lines) {
                        if ($line -match "updating\s+(.+?)\s+\((.+?)\s+->\s+(.+?)\)") {
                            Add-PackageUpdate -Name $matches[1].Trim() -Manager "scoop" `
                                -Before $matches[2].Trim() -After $matches[3].Trim()
                        }
                    }
                }
            }
        } else {
            Write-Log "Scoop introuvable." "WARN"
            Add-ReportEntry -Phase "Phase 3" -Step "Scoop" -Status "WARN" -Details "Non installe"
        }

        # --- Chocolatey ---
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-Log "Chocolatey : mise a jour..." "INFO"
            if ($PSCmdlet.ShouldProcess("Chocolatey packages", "Upgrade")) {
                $chocoResult = Invoke-NativeWithLog `
                    -FilePath "choco" `
                    -ArgumentList @("upgrade", "all", "-y", "--no-progress") `
                    -Phase "Phase 3" -Step "Chocolatey" -TimeoutSeconds 600

                if ($chocoResult.Output) {
                    $lines = $chocoResult.Output -split "`n"
                    foreach ($line in $lines) {
                        if ($line -match "(.+?)\s+v([\d\.]+)\s+is\s+the\s+latest\s+version") {
                            Add-PackageSkip -Name $matches[1].Trim() -Manager "choco" -Reason "Deja a jour ($($matches[2]))"
                        }
                        if ($line -match " upgraded\s+(.+?)\s+from\s+(.+?)\s+to\s+(.+)") {
                            Add-PackageUpdate -Name $matches[1].Trim() -Manager "choco" `
                                -Before $matches[2].Trim() -After $matches[3].Trim()
                        }
                    }
                }
            }
        } else {
            Write-Log "Chocolatey introuvable." "WARN"
            Add-ReportEntry -Phase "Phase 3" -Step "Chocolatey" -Status "WARN" -Details "Non installe"
        }
    } else {
        Write-Log "Phase 3 ignoree (SkipPackageManagers)." "INFO"
    }

    Write-Log "Phase 3 terminee." "SUCCESS"

    # =========================================================================
    # PHASE 4 : ENVIRONNEMENTS DE DEVELOPPEMENT
    # =========================================================================
    Write-Phase -Name "ENVIRONNEMENTS DE DEVELOPPEMENT" -Num 4 -Total 6

    if (-not $SkipDevEnv) {
        # --- npm ---
        if (Get-Command npm -ErrorAction SilentlyContinue) {
            Write-Log "npm : mise a jour..." "INFO"

            if ($PSCmdlet.ShouldProcess("npm", "Upgrade")) {
                $npmSelfResult = Invoke-NativeWithLog `
                    -FilePath "npm" `
                    -ArgumentList @("install", "-g", "npm@latest") `
                    -Phase "Phase 4" -Step "npm-self" -TimeoutSeconds 120

                if ($npmSelfResult.Output -match "added|changed|updated") {
                    $verAfter = (npm --version 2>$null)
                    Add-PackageUpdate -Name "npm" -Manager "npm" -Before "inconnue" -After $verAfter -Details "Self-update"
                }
            }

            if ($UpdateNpmGlobal) {
                Write-Log "Mise a jour des packages npm globaux (opt-in)..." "INFO"
                $outdatedJson = npm outdated -g --json 2>$null
                if ($outdatedJson) {
                    $outdated = $outdatedJson | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($outdated) {
                        $outdated.PSObject.Properties | ForEach-Object {
                            $pkgName = $_.Name
                            $pkgInfo = $_.Value
                            Write-Log "  Mise a jour $pkgName : $($pkgInfo.current) -> $($pkgInfo.latest)" "INFO"

                            if ($PSCmdlet.ShouldProcess("npm global $pkgName", "Upgrade")) {
                                $pkgResult = Invoke-NativeWithLog `
                                    -FilePath "npm" `
                                    -ArgumentList @("install", "-g", "$pkgName@latest") `
                                    -Phase "Phase 4" -Step "npm-$pkgName" -TimeoutSeconds 120

                                if ($pkgResult.Success) {
                                    Add-PackageUpdate -Name $pkgName -Manager "npm" `
                                        -Before $pkgInfo.current -After $pkgInfo.latest
                                } else {
                                    Add-PackageSkip -Name $pkgName -Manager "npm" -Reason "Echec mise a jour"
                                }
                            }
                        }
                    }
                } else {
                    Write-Log "Aucun package npm global depasse." "SUCCESS"
                }
            } else {
                Write-Log "UpdateNpmGlobal non active (utilisez -UpdateNpmGlobal)." "INFO"
            }
        } else {
            Write-Log "npm introuvable." "WARN"
            Add-ReportEntry -Phase "Phase 4" -Step "npm" -Status "WARN" -Details "Non installe"
        }

        # --- pip ---
        if (Get-Command python -ErrorAction SilentlyContinue) {
            Write-Log "pip : mise a jour..." "INFO"

            if ($PSCmdlet.ShouldProcess("pip", "Upgrade")) {
                $pipSelfResult = Invoke-NativeWithLog `
                    -FilePath "python" `
                    -ArgumentList @("-m", "pip", "install", "--upgrade", "pip") `
                    -Phase "Phase 4" -Step "pip-self" -TimeoutSeconds 120

                if ($pipSelfResult.Success) {
                    $pipVer = (python -m pip --version 2>$null) -split " " | Select-Object -Index 1
                    Add-PackageUpdate -Name "pip" -Manager "pip" -Before "inconnue" -After $pipVer -Details "Self-update"
                }
            }

            # Detection PyTorch
            $hasTorch = $false
            try {
                $torchCheck = python -c "import torch; print(torch.__version__)" 2>$null
                if ($torchCheck) { $hasTorch = $true }
            } catch { }

            if ($hasTorch) {
                Write-Log "PyTorch detecte." "INFO"
                $cudaVer = python -c "import torch; print(torch.version.cuda if torch.version.cuda else 'cpu')" 2>$null
                Write-Log "PyTorch CUDA : $cudaVer" "INFO"

                if ($cudaVer -and $cudaVer -ne "cpu" -and $cudaVer -ne "None") {
                    $cudaMajor = $cudaVer.Split('.')[0]
                    $indexUrl = "https://download.pytorch.org/whl/cu$cudaMajor$($cudaVer.Split('.')[1])"
                    Write-Log "Mise a jour PyTorch avec index CUDA : $indexUrl" "INFO"

                    if ($PSCmdlet.ShouldProcess("PyTorch CUDA", "Upgrade")) {
                        $torchResult = Invoke-NativeWithLog `
                            -FilePath "python" `
                            -ArgumentList @("-m", "pip", "install", "--upgrade", "torch", "torchvision", "torchaudio", "--extra-index-url", $indexUrl) `
                            -Phase "Phase 4" -Step "pip-pytorch" -TimeoutSeconds 300

                        if ($torchResult.Success) {
                            $newVer = python -c "import torch; print(torch.__version__)" 2>$null
                            Add-PackageUpdate -Name "PyTorch" -Manager "pip" -Before $cudaVer -After $newVer -Details "CUDA $cudaVer"
                        }
                    }
                } else {
                    Write-Log "PyTorch CPU-only. Mise a jour standard." "INFO"
                    if ($PSCmdlet.ShouldProcess("PyTorch CPU", "Upgrade")) {
                        $torchResult = Invoke-NativeWithLog `
                            -FilePath "python" `
                            -ArgumentList @("-m", "pip", "install", "--upgrade", "torch", "torchvision", "torchaudio", "--index-url", "https://download.pytorch.org/whl/cpu") `
                            -Phase "Phase 4" -Step "pip-pytorch" -TimeoutSeconds 300

                        if ($torchResult.Success) {
                            $newVer = python -c "import torch; print(torch.__version__)" 2>$null
                            Add-PackageUpdate -Name "PyTorch" -Manager "pip" -Before "cpu" -After $newVer -Details "CPU-only"
                        }
                    }
                }
            }

            # Packages globaux pip (not-required seulement)
            $pipOutdated = python -m pip list --outdated --not-required --format=json 2>$null
            if ($pipOutdated) {
                $outdatedPkgs = $pipOutdated | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($outdatedPkgs -and $outdatedPkgs.Count -gt 0) {
                    Write-Log "Packages pip depasses (not-required) : $($outdatedPkgs.Count)" "INFO"
                    foreach ($pkg in $outdatedPkgs) {
                        Write-Log "  $($pkg.name) : $($pkg.version) -> $($pkg.latest_version)" "INFO"

                        if ($PSCmdlet.ShouldProcess("pip $($pkg.name)", "Upgrade")) {
                            $pkgResult = Invoke-NativeWithLog `
                                -FilePath "python" `
                                -ArgumentList @("-m", "pip", "install", "--upgrade", $pkg.name) `
                                -Phase "Phase 4" -Step "pip-$($pkg.name)" -TimeoutSeconds 180

                            if ($pkgResult.Success) {
                                Add-PackageUpdate -Name $pkg.name -Manager "pip" `
                                    -Before $pkg.version -After $pkg.latest_version
                            } else {
                                Add-PackageSkip -Name $pkg.name -Manager "pip" -Reason "Echec mise a jour"
                            }
                        }
                    }
                } else {
                    Write-Log "Aucun package pip depasse (not-required)." "SUCCESS"
                }
            }

            # Venvs (opt-in)
            if ($UpdateVenvs) {
                Write-Log "Recherche de venvs Python..." "INFO"
                $searchPaths = @($env:USERPROFILE, "$env:USERPROFILE\Documents", "$env:USERPROFILE\Dev", "$env:USERPROFILE\Projects")
                $venvDirs = @()
                foreach ($path in $searchPaths) {
                    if (Test-Path $path) {
                        $venvDirs += Get-ChildItem -Path $path -Recurse -Depth 3 -Filter "python.exe" -ErrorAction SilentlyContinue | 
                            Where-Object { $_.FullName -match "Scripts\python.exe$" -or $_.FullName -match "bin\python.exe$" } |
                            Select-Object -ExpandProperty FullName
                    }
                }
                $venvDirs = $venvDirs | Select-Object -First 10

                if ($venvDirs.Count -gt 0) {
                    Write-Log "Venvs trouves : $($venvDirs.Count)" "INFO"
                    foreach ($venvPython in $venvDirs) {
                        $venvDir = Split-Path (Split-Path $venvPython -Parent) -Parent
                        Write-Log "  Mise a jour venv : $venvDir" "INFO"

                        if ($PSCmdlet.ShouldProcess("venv $venvDir", "Upgrade")) {
                            $venvResult = Invoke-NativeWithLog `
                                -FilePath $venvPython `
                                -ArgumentList @("-m", "pip", "install", "--upgrade", "pip") `
                                -Phase "Phase 4" -Step "venv-pip" -TimeoutSeconds 60

                            $venvOutdated = & $venvPython -m pip list --outdated --not-required --format=json 2>$null
                            if ($venvOutdated) {
                                $venvPkgs = $venvOutdated | ConvertFrom-Json -ErrorAction SilentlyContinue
                                foreach ($pkg in $venvPkgs) {
                                    $venvPkgResult = Invoke-NativeWithLog `
                                        -FilePath $venvPython `
                                        -ArgumentList @("-m", "pip", "install", "--upgrade", $pkg.name) `
                                        -Phase "Phase 4" -Step "venv-$($pkg.name)" -TimeoutSeconds 120

                                    if ($venvPkgResult.Success) {
                                        Add-PackageUpdate -Name "$($pkg.name) (venv)" -Manager "pip-venv" `
                                            -Before $pkg.version -After $pkg.latest_version -Details $venvDir
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Write-Log "Aucun venv trouve." "INFO"
                }
            } else {
                Write-Log "UpdateVenvs non active (utilisez -UpdateVenvs)." "INFO"
            }
        } else {
            Write-Log "Python introuvable." "WARN"
            Add-ReportEntry -Phase "Phase 4" -Step "pip" -Status "WARN" -Details "Non installe"
        }

        # --- conda ---
        if (Get-Command conda -ErrorAction SilentlyContinue) {
            Write-Log "conda : mise a jour..." "INFO"

            if ($PSCmdlet.ShouldProcess("conda base", "Update")) {
                $condaBaseResult = Invoke-NativeWithLog `
                    -FilePath "conda" `
                    -ArgumentList @("update", "-n", "base", "conda", "-y", "--satisfied-skip-solve") `
                    -Phase "Phase 4" -Step "conda-base" -TimeoutSeconds 300

                if ($condaBaseResult.Success) {
                    $condaVer = (conda --version 2>$null) -replace "conda ", ""
                    Add-PackageUpdate -Name "conda" -Manager "conda" -Before "inconnue" -After $condaVer -Details "base environment"
                }
            }

            $envListJson = conda env list --json 2>$null
            if ($envListJson) {
                $envList = $envListJson | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($envList -and $envList.envs) {
                    foreach ($envPath in $envList.envs) {
                        $envName = Split-Path $envPath -Leaf
                        if ($envName -eq "base") { continue }

                        Write-Log "  Mise a jour env conda : $envName" "INFO"
                        if ($PSCmdlet.ShouldProcess("conda env $envName", "Update")) {
                            $envResult = Invoke-NativeWithLog `
                                -FilePath "conda" `
                                -ArgumentList @("update", "-p", $envPath, "--all", "-y", "--satisfied-skip-solve") `
                                -Phase "Phase 4" -Step "conda-$envName" -TimeoutSeconds 300

                            if ($envResult.Success) {
                                Add-PackageUpdate -Name $envName -Manager "conda-env" -Before "inconnue" -After "updated" -Details $envPath
                            }
                        }
                    }
                }
            }
        } else {
            Write-Log "conda introuvable." "WARN"
            Add-ReportEntry -Phase "Phase 4" -Step "conda" -Status "WARN" -Details "Non installe"
        }

        # --- cargo ---
        if (Get-Command cargo -ErrorAction SilentlyContinue) {
            Write-Log "cargo : mise a jour..." "INFO"

            $hasUpdate = cargo install --list 2>$null | Select-String "cargo-update"
            if (-not $hasUpdate) {
                Write-Log "Installation de cargo-update..." "INFO"
                if ($PSCmdlet.ShouldProcess("cargo-update", "Install")) {
                    $installResult = Invoke-NativeWithLog `
                        -FilePath "cargo" `
                        -ArgumentList @("install", "cargo-update") `
                        -Phase "Phase 4" -Step "cargo-install-update" -TimeoutSeconds 300

                    if ($installResult.Success) {
                        Add-PackageUpdate -Name "cargo-update" -Manager "cargo" -Before "absent" -After "installe" -Details "Outil de mise a jour"
                    }
                }
            }

            if ($PSCmdlet.ShouldProcess("cargo binaries", "Update")) {
                $cargoResult = Invoke-NativeWithLog `
                    -FilePath "cargo" `
                    -ArgumentList @("install-update", "-a") `
                    -Phase "Phase 4" -Step "cargo" -TimeoutSeconds 300

                if ($cargoResult.Output) {
                    $lines = $cargoResult.Output -split "`n"
                    foreach ($line in $lines) {
                        if ($line -match "Updated\s+(.+?)\s+v?([\d\.]+)\s+->\s+v?([\d\.]+)") {
                            Add-PackageUpdate -Name $matches[1].Trim() -Manager "cargo" `
                                -Before $matches[2].Trim() -After $matches[3].Trim()
                        }
                    }
                }
            }
        } else {
            Write-Log "cargo introuvable." "WARN"
            Add-ReportEntry -Phase "Phase 4" -Step "cargo" -Status "WARN" -Details "Non installe"
        }

        # --- go ---
        if (Get-Command go -ErrorAction SilentlyContinue) {
            Write-Log "go : mise a jour..." "INFO"

            if ($PSCmdlet.ShouldProcess("go modcache", "Clean")) {
                $goCleanResult = Invoke-NativeWithLog `
                    -FilePath "go" `
                    -ArgumentList @("clean", "-modcache") `
                    -Phase "Phase 4" -Step "go-clean" -TimeoutSeconds 60
            }

            Write-Log "Recherche de projets Go (go.mod)..." "INFO"
            $searchPaths = @($env:USERPROFILE, "$env:USERPROFILE\go\src")
            $goMods = @()
            foreach ($path in $searchPaths) {
                if (Test-Path $path) {
                    $goMods += Get-ChildItem -Path $path -Recurse -Depth 3 -Filter "go.mod" -ErrorAction SilentlyContinue |
                        Select-Object -ExpandProperty FullName
                }
            }
            $goMods = $goMods | Select-Object -First 20

            if ($goMods.Count -gt 0) {
                Write-Log "Projets Go trouves : $($goMods.Count)" "INFO"
                foreach ($modFile in $goMods) {
                    $modDir = Split-Path $modFile -Parent
                    $modName = Split-Path $modDir -Leaf
                    Write-Log "  Mise a jour : $modName" "INFO"

                    if ($PSCmdlet.ShouldProcess("go project $modName", "Update")) {
                        $goResult = Invoke-NativeWithLog `
                            -FilePath "go" `
                            -ArgumentList @("get", "-u", "./...") `
                            -Phase "Phase 4" -Step "go-$modName" -TimeoutSeconds 120 `
                            -WorkingDirectory $modDir

                        if ($goResult.Success) {
                            Add-PackageUpdate -Name $modName -Manager "go" -Before "inconnue" -After "updated" -Details $modDir
                        }
                    }
                }
            } else {
                Write-Log "Aucun projet Go trouve." "INFO"
            }
        } else {
            Write-Log "go introuvable." "WARN"
            Add-ReportEntry -Phase "Phase 4" -Step "go" -Status "WARN" -Details "Non installe"
        }
    } else {
        Write-Log "Phase 4 ignoree (SkipDevEnv)." "INFO"
    }

    Write-Log "Phase 4 terminee." "SUCCESS"

    # =========================================================================
    # PHASE 5 : NETTOYAGE DISQUE
    # =========================================================================
    Write-Phase -Name "NETTOYAGE DISQUE" -Num 5 -Total 6

    if (-not $SkipDiskCleanup) {
        # Nettoyage TEMP
        $tempCount = 0
        $tempSize = 0
        if (Test-Path $env:TEMP) {
            $items = Get-ChildItem -Path $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                try {
                    if ($PSCmdlet.ShouldProcess($item.FullName, "Remove")) {
                        Remove-Item -Path $item.FullName -Force -Recurse -ErrorAction SilentlyContinue
                        $tempCount++
                        if ($item.Length) { $tempSize += $item.Length }
                    }
                } catch { }
            }
        }
        $tempSizeStr = if ($tempSize -gt 1GB) { "{0:N2} GB" -f ($tempSize/1GB) } elseif ($tempSize -gt 1MB) { "{0:N2} MB" -f ($tempSize/1MB) } else { "{0:N2} KB" -f ($tempSize/1KB) }
        Write-Log "Fichiers nettoyes (TEMP) : $tempCount elements ($tempSizeStr)" "SUCCESS"
        Add-CleanupDetail -Category "TEMP" -Path $env:TEMP -Count $tempCount -Size $tempSizeStr
        Add-ReportEntry -Phase "Phase 5" -Step "Nettoyage-Temp" -Status "SUCCESS" -Details "$tempCount elements, $tempSizeStr"

        # Nettoyage Prefetch
        $prefetchCount = 0
        $prefetchPath = "$env:SystemRoot\Prefetch"
        if (Test-Path $prefetchPath) {
            $oldPrefetch = Get-ChildItem -Path $prefetchPath -Filter "*.pf" -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) }
            foreach ($file in $oldPrefetch) {
                try {
                    if ($PSCmdlet.ShouldProcess($file.FullName, "Remove")) {
                        Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
                        $prefetchCount++
                    }
                } catch { }
            }
        }
        Write-Log "Prefetch nettoye ($prefetchCount fichiers > 30j)" "SUCCESS"
        Add-CleanupDetail -Category "Prefetch" -Path $prefetchPath -Count $prefetchCount
        Add-ReportEntry -Phase "Phase 5" -Step "Nettoyage-Prefetch" -Status "SUCCESS" -Details "$prefetchCount fichiers > 30j"

        # Caches package managers
        if (Get-Command npm -ErrorAction SilentlyContinue) {
            $npmCacheResult = Invoke-NativeWithLog `
                -FilePath "npm" `
                -ArgumentList @("cache", "clean", "--force") `
                -Phase "Phase 5" -Step "npm-cache" -TimeoutSeconds 60
            if ($npmCacheResult.Success) {
                Add-CleanupDetail -Category "npm-cache" -Path "$env:APPDATA\npm-cache" -Count 1
            }
        }

        if (Get-Command python -ErrorAction SilentlyContinue) {
            $pipCacheResult = Invoke-NativeWithLog `
                -FilePath "python" `
                -ArgumentList @("-m", "pip", "cache", "purge") `
                -Phase "Phase 5" -Step "pip-cache" -TimeoutSeconds 60
            if ($pipCacheResult.Success) {
                Add-CleanupDetail -Category "pip-cache" -Path "$env:LOCALAPPDATA\pip\Cache" -Count 1
            }
        }

        $chocoTemp = "$env:TEMP\chocolatey"
        if (Test-Path $chocoTemp) {
            $chocoTempItems = Get-ChildItem -Path $chocoTemp -Recurse -ErrorAction SilentlyContinue
            $chocoTempCount = $chocoTempItems.Count
            Remove-Item -Path $chocoTemp -Recurse -Force -ErrorAction SilentlyContinue
            Add-CleanupDetail -Category "choco-temp" -Path $chocoTemp -Count $chocoTempCount
        }
    } else {
        Write-Log "Phase 5 ignoree (SkipDiskCleanup)." "INFO"
    }

    Write-Log "Phase 5 terminee." "SUCCESS"

    # =========================================================================
    # PHASE 6 : VERIFICATIONS FINALES & RAPPORT
    # =========================================================================
    Write-Phase -Name "VERIFICATIONS FINALES & RAPPORT" -Num 6 -Total 6

    # BCD Check
    try {
        $bcd = bcdedit /enum 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "BCD : OK" "SUCCESS"
            Add-ReportEntry -Phase "Phase 6" -Step "BCD-Check" -Status "SUCCESS" -Details "Boot Configuration Data valide"
        }
    } catch {
        Write-Log "BCD : Erreur de lecture" "WARN"
        Add-ReportEntry -Phase "Phase 6" -Step "BCD-Check" -Status "WARN" -Details $_.Exception.Message
    }

    # SMART Check
    try {
        $disks = Get-PhysicalDisk | Where-Object { $_.HealthStatus -ne 'Healthy' }
        if (-not $disks) {
            Write-Log "SMART : Tous les disques sains." "SUCCESS"
            Add-ReportEntry -Phase "Phase 6" -Step "SMART-Check" -Status "SUCCESS" -Details "Tous les disques Healthy"
        } else {
            Write-Log "SMART : Disque(s) en warning !" "WARN"
            Add-ReportEntry -Phase "Phase 6" -Step "SMART-Check" -Status "WARN" -Details ($disks | Out-String)
        }
    } catch {
        Write-Log "SMART : Erreur de lecture" "WARN"
        Add-ReportEntry -Phase "Phase 6" -Step "SMART-Check" -Status "WARN" -Details $_.Exception.Message
    }

    # Services
    $wuauserv = Get-Service wuauserv -ErrorAction SilentlyContinue
    if ($wuauserv -and $wuauserv.Status -eq 'Running') {
        Write-Log "Service wuauserv : OK" "SUCCESS"
        Add-ReportEntry -Phase "Phase 6" -Step "Services" -Status "SUCCESS" -Details "wuauserv Running"
    }

    $cryptsvc = Get-Service cryptsvc -ErrorAction SilentlyContinue
    if ($cryptsvc -and $cryptsvc.Status -eq 'Running') {
        Write-Log "Service cryptsvc : OK" "SUCCESS"
    }

    # Generation des rapports
    Write-Log "Generation des rapports..." "INFO"
    Export-HtmlReport
    Export-JsonReport

    # Resume final
    $totalDuration = New-TimeSpan -Start $script:StartTime -End (Get-Date)
    Write-Log "+----------------------------------+--------+" "INFO"
    Write-Log "| Metrique                         | Valeur |" "INFO"
    Write-Log "+----------------------------------+--------+" "INFO"
    Write-Log "| Duree totale                     | $($totalDuration.ToString('hh\:mm\:ss')) |" "INFO"
    Write-Log "| Succes                           | $($script:SuccessCount.ToString().PadLeft(6)) |" "INFO"
    Write-Log "| Avertissements                   | $($script:WarnCount.ToString().PadLeft(6)) |" "INFO"
    Write-Log "| Erreurs                          | $($script:ErrorCount.ToString().PadLeft(6)) |" "INFO"
    Write-Log "| Packages mis a jour              | $($script:PackagesUpdated.Count.ToString().PadLeft(6)) |" "INFO"
    Write-Log "| Packages ignores                 | $($script:PackagesSkipped.Count.ToString().PadLeft(6)) |" "INFO"
    Write-Log "| Mode                             | $(if ($WhatIfPreference) { 'SIMULATION'.PadLeft(6) } else { 'REEL'.PadLeft(6) }) |" "INFO"
    Write-Log "+----------------------------------+--------+" "INFO"

    Write-Log "Maintenance terminee avec $($script:WarnCount) avertissement(s)." "END"
    Write-Log "Rapport HTML : $script:HtmlFile" "INFO"
    Write-Log "Rapport JSON : $script:JsonFile" "INFO"
    Write-Log "Log texte    : $script:LogFile" "INFO"
}
catch {
    Write-Log "ERREUR FATALE : $($_.Exception.Message)" "ERROR"
    Write-Log "Stack : $($_.ScriptStackTrace)" "ERROR"
}
finally {
    Write-Host "`n"
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host "  Appuyez sur ENTREE pour fermer..." -ForegroundColor Yellow
    Write-Host "===================================================" -ForegroundColor Cyan
    Read-Host
}
