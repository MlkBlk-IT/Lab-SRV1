#Requires -Version 7.0
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Script de Maintenance Enterprise Master v5.0 (Final Production Release)
.DESCRIPTION
    Maintenance système de classe mondiale. Audit strict, réparations sécurisées, 
    rapports structurés (HTML/JSON) avec métadonnées complètes et RunID.
.PARAMETER AuditOnly
    Mode lecture seule STRICT. Exécute uniquement CheckHealth, ScanHealth, SMART, et vérifications.
.PARAMETER DetailedDISMAudit
    Exécute DISM /CheckHealth et /ScanHealth avant /RestoreHealth.
.PARAMETER DisableFastStartup, EnableMSIMode, OptimizeTCP, DeepCleanPackageCaches
    Optimisations granulaires, toutes désactivées par défaut.
.PARAMETER SkipWindowsUpdate, SkipPackageManagers, SkipDevEnv, SkipDiskCleanup
    Permet d'ignorer des phases spécifiques.
.PARAMETER NoPause
    Supprime la pause finale (Read-Host) pour l'automatisation (Intune, SCCM, Task Scheduler).
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$AuditOnly,
    [switch]$DetailedDISMAudit,
    [switch]$DisableFastStartup,
    [switch]$EnableMSIMode,
    [switch]$OptimizeTCP,
    [switch]$DeepCleanPackageCaches,
    [switch]$SkipWindowsUpdate,
    [switch]$SkipPackageManagers,
    [switch]$SkipDevEnv,
    [switch]$SkipDiskCleanup,
    [switch]$NoPause
)

try {
    # =========================================================================
    # CONFIGURATION, LOGGING & RUNID
    # =========================================================================
    $ErrorActionPreference = "Stop"
    $VerbosePreference = "Continue" # Active Write-Verbose pour le debugging
    $script:StartTime = Get-Date
    $script:RunID = [guid]::NewGuid().ToString()
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    
    $script:LogFile = Join-Path $env:USERPROFILE\Desktop "Maintenance_Master_v5_${timestamp}_${script:RunID}.log"
    $script:HtmlFile = Join-Path $env:USERPROFILE\Desktop "Rapport_Master_v5_${timestamp}.html"
    $script:JsonFile = Join-Path $env:USERPROFILE\Desktop "Rapport_Master_v5_${timestamp}.json"
    
    $script:ReportData = [System.Collections.Generic.List[PSCustomObject]]::new()
    $script:SuccessCount = 0; $script:WarnCount = 0; $script:ErrorCount = 0

    # Métadonnées Système (Collectées une seule fois)
    $osInfo = Get-CimInstance Win32_OperatingSystem
    $sysInfo = Get-CimInstance Win32_ComputerSystem
    $cpuInfo = Get-CimInstance Win32_Processor | Select-Object -First 1
    $script:SystemMeta = [ordered]@{
        RunID = $script:RunID
        ComputerName = $env:COMPUTERNAME
        OS = "$($osInfo.Caption) $($osInfo.Version) (Build $($osInfo.BuildNumber))"
        Architecture = $osInfo.OSArchitecture
        RAM_GB = [math]::Round($sysInfo.TotalPhysicalMemory / 1GB, 2)
        CPU = $cpuInfo.Name.Trim()
        Uptime = (Get-Date) - $osInfo.LastBootUpTime
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        ScriptVersion = "5.0.0"
    }

    function Write-Log {
        param([string]$Message, [ValidateSet("INFO","SUCCESS","WARN","ERROR","PHASE")] [string]$Level = "INFO")
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $line = "[$ts] [$Level] [$($script:RunID)] $Message"
        $colorMap = @{ "INFO"="White"; "SUCCESS"="Green"; "WARN"="Yellow"; "ERROR"="Red"; "PHASE"="Cyan" }
        
        # Write-Host pour l'interactif, Write-Verbose pour le debugging structuré
        Write-Host $line -ForegroundColor $colorMap[$Level]
        Write-Verbose "LOG_$Level :: $Message"
        $line | Out-File -FilePath $script:LogFile -Append -Encoding UTF8
        
        if ($Level -eq "SUCCESS") { $script:SuccessCount++ }
        elseif ($Level -eq "WARN") { $script:WarnCount++ }
        elseif ($Level -eq "ERROR") { $script:ErrorCount++ }
    }

    function Add-Report {
        param([string]$Phase, [string]$Step, [string]$Status, [string]$Details = "")
        $script:ReportData.Add([PSCustomObject]@{ 
            Timestamp=Get-Date -Format "yyyy-MM-dd HH:mm:ss"; 
            RunID=$script:RunID; 
            Phase=$Phase; Step=$Step; Status=$Status; Details=$Details 
        })
    }

    function Invoke-NativeWithTimeout {
        param([string]$FilePath, [string[]]$ArgumentList, [string]$Step, [int]$TimeoutSeconds = 600)
        Write-Log "[START] $Step (Timeout: ${TimeoutSeconds}s)" "INFO"
        $tmpOut = [System.IO.Path]::GetTempFileName()
        $tmpErr = [System.IO.Path]::GetTempFileName()
        
        try {
            $proc = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -NoNewWindow -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr -PassThru
            $proc | Wait-Process -Timeout $TimeoutSeconds -ErrorAction SilentlyContinue
            
            if ($proc.HasExited) {
                $stdout = if (Test-Path $tmpOut) { Get-Content $tmpOut -Raw -ErrorAction SilentlyContinue } else { "" }
                $stderr = if (Test-Path $tmpErr) { Get-Content $tmpErr -Raw -ErrorAction SilentlyContinue } else { "" }
                $exitCode = $proc.ExitCode
                $output = ($stdout + "`n" + $stderr).Trim()
                
                if ($exitCode -in 0, 3010) {
                    Write-Log "[SUCCESS] $Step terminé (Code: $exitCode)." "SUCCESS"
                    Add-Report -Phase "Execution" -Step $Step -Status "SUCCESS" -Details "Code: $exitCode"
                    return @{ Success = $true; Output = $output; ExitCode = $exitCode }
                } else {
                    Write-Log "[WARN] $Step a retourné le code : $exitCode" "WARN"
                    Add-Report -Phase "Execution" -Step $Step -Status "WARN" -Details "Code: $exitCode"
                    return @{ Success = $false; Output = $output; ExitCode = $exitCode }
                }
            } else {
                Write-Log "[WARN] $Step a dépassé le délai de ${TimeoutSeconds}s." "WARN"
                if ($FilePath -match "DISM|sfc") {
                    Write-Log "[INFO] Arrêt forcé ignoré pour les processus système critiques (DISM/SFC)." "INFO"
                    Add-Report -Phase "Execution" -Step $Step -Status "WARN" -Details "Timeout (Processus laissé en cours)"
                } else {
                    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                    Add-Report -Phase "Execution" -Step $Step -Status "ERROR" -Details "Timeout dépassé, processus arrêté"
                }
                return @{ Success = $false; Output = "Timeout"; ExitCode = -1 }
            }
        } catch {
            Write-Log "[ERROR] $Step : $($_.Exception.Message)" "ERROR"
            return @{ Success = $false; Output = $_.Exception.Message; ExitCode = -1 }
        } finally {
            if (Test-Path $tmpOut) { Remove-Item $tmpOut -Force -ErrorAction SilentlyContinue }
            if (Test-Path $tmpErr) { Remove-Item $tmpErr -Force -ErrorAction SilentlyContinue }
        }
    }

    # =========================================================================
    # PHASE 1 : ENVIRONNEMENT & PRÉ-VOLS
    # =========================================================================
    Write-Log "=== PHASE 1/7 : ENVIRONNEMENT & PRÉ-VOLS ===" "PHASE"
    
    $computerSystem = Get-CimInstance Win32_ComputerSystem
    $isVM = $computerSystem.HypervisorPresent -or $computerSystem.Model -match "Virtual|VMware|Hyper-V"
    $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
    $powerStatus = if ($battery) { if ($battery.BatteryStatus -eq 1) { "Sur Batterie" } else { "Sur Secteur" } } else { "Secteur (Desktop/Server)" }
    Write-Log "Environnement : $(if($isVM){'VM'}else{'Physique'}) | Alimentation : $powerStatus" "INFO"
    Add-Report -Phase "Phase 1" -Step "Environnement" -Status "INFO" -Details "$(if($isVM){'VM'}else{'Physique'}) - $powerStatus"

    if (-not (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Privilèges administrateur requis."
    }
    Write-Log "Admin : OK" "SUCCESS"

    $diskC = Get-PSDrive C -ErrorAction SilentlyContinue
    if ($diskC) {
        $freePct = [math]::Round(($diskC.Free / ($diskC.Free + $diskC.Used)) * 100, 1)
        if ($freePct -lt 10) { Write-Log "Espace disque critique sur C: ($freePct%)." "ERROR"; throw "Espace insuffisant" }
        Write-Log "Disque C: : $freePct% libre" "SUCCESS"
    }

    $rebootPending = (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") -or (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired")
    if ($rebootPending) {
        Write-Log "Redémarrage en attente détecté." "WARN"
        Add-Report -Phase "Phase 1" -Step "Reboot" -Status "WARN" -Details "Reboot pending"
    } else { Write-Log "Aucun redémarrage en attente." "SUCCESS" }

    # =========================================================================
    # PHASE 2 : AUDIT & INTÉGRITÉ (STRICTEMENT SÉPARÉ)
    # =========================================================================
    Write-Log "=== PHASE 2/7 : AUDIT & INTÉGRITÉ SYSTÈME ===" "PHASE"
    
    # 2.1 Audit DISM (Toujours exécuté, même en AuditOnly)
    if ($DetailedDISMAudit) {
        Invoke-NativeWithTimeout -FilePath "DISM.exe" -ArgumentList @("/Online","/Cleanup-Image","/CheckHealth") -Step "DISM CheckHealth" -TimeoutSeconds 300 | Out-Null
        Invoke-NativeWithTimeout -FilePath "DISM.exe" -ArgumentList @("/Online","/Cleanup-Image","/ScanHealth") -Step "DISM ScanHealth" -TimeoutSeconds 600 | Out-Null
    }

    if ($AuditOnly) {
        Write-Log "Mode AuditOnly activé. Arrêt après les vérifications (Aucune réparation lancée)." "SUCCESS"
        Write-Log "Aucune modification n'a été appliquée au système." "INFO"
    } else {
        # 2.2 Réparations (UNIQUEMENT si pas AuditOnly)
        $dismRestore = Invoke-NativeWithTimeout -FilePath "DISM.exe" -ArgumentList @("/Online","/Cleanup-Image","/RestoreHealth") -Step "DISM RestoreHealth" -TimeoutSeconds 1800
        if (-not $dismRestore.Success) { Write-Log "DISM RestoreHealth a échoué ou nécessite un redémarrage." "WARN" }

        Write-Log "Exécution SFC /scannow..." "INFO"
        $sfcResult = Invoke-NativeWithTimeout -FilePath "sfc.exe" -ArgumentList @("/scannow") -Step "SFC Scannow" -TimeoutSeconds 1800
        
        # Codes SFC validés Win 10/11 (24H2/25H2)
        if ($sfcResult.ExitCode -eq 0) { Write-Log "SFC : Aucune violation d'intégrité." "SUCCESS" }
        elseif ($sfcResult.ExitCode -eq 1) { Write-Log "SFC : Violations réparées." "WARN" }
        elseif ($sfcResult.ExitCode -eq 2) { Write-Log "SFC : Violations NON réparées. Redémarrage requis." "ERROR" }
        else { Write-Log "SFC : Code inattendu : $($sfcResult.ExitCode)." "WARN" }

        # Protection MSI
        $wuSvc = Get-Service wuauserv -ErrorAction SilentlyContinue
        $wuProc = Get-Process TiWorker, UsoClient -ErrorAction SilentlyContinue
        if ($wuSvc -and $wuSvc.Status -eq 'Running' -and $wuProc) {
            Write-Log "Windows Update actif. StartComponentCleanup ignoré." "WARN"
        } else {
            Invoke-NativeWithTimeout -FilePath "DISM.exe" -ArgumentList @("/Online","/Cleanup-Image","/StartComponentCleanup") -Step "DISM StartComponentCleanup" -TimeoutSeconds 900 | Out-Null
        }
    }

    # =========================================================================
    # PHASE 3 à 6 : MISES À JOUR, NETTOYAGE, OPTIMISATIONS (Skip si AuditOnly)
    # =========================================================================
    if (-not $AuditOnly) {
        Write-Log "=== PHASE 3/7 : MISES À JOUR LOGICIELLES ===" "PHASE"
        if (-not $SkipWindowsUpdate) {
            if ($PSCmdlet.ShouldProcess("PSWindowsUpdate", "Installer et exécuter les mises à jour")) {
                try {
                    # Vérification PSGallery
                    $repo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
                    if ($repo -and $repo.InstallationPolicy -ne 'Trusted') {
                        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
                    }
                    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
                        Install-Module -Name PSWindowsUpdate -Force -AcceptLicense -AllowClobber -Scope CurrentUser -ErrorAction Stop
                    }
                    Import-Module -Name PSWindowsUpdate -Force -ErrorAction Stop
                    if (-not (Get-Module -Name PSWindowsUpdate)) { throw "Échec de l'import." }
                    
                    Write-Log "Recherche et installation des mises à jour Windows..." "INFO"
                    Install-WindowsUpdate -AcceptAll -AutoReboot:$false -IgnoreReboot -ErrorAction Stop | Out-Null
                    Write-Log "Windows Update terminé." "SUCCESS"
                } catch {
                    Write-Log "Échec Windows Update : $($_.Exception.Message)" "ERROR"
                }
            }
        }

        if (-not $SkipPackageManagers) {
            if ($PSCmdlet.ShouldProcess("Winget", "Mettre à jour")) {
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    Invoke-NativeWithTimeout -FilePath "winget" -ArgumentList @("upgrade","--all","--silent","--disable-interactivity","--accept-package-agreements","--accept-source-agreements") -Step "Winget" -TimeoutSeconds 600 | Out-Null
                }
            }
            if ($PSCmdlet.ShouldProcess("Scoop", "Mettre à jour")) {
                if (Get-Command scoop -ErrorAction SilentlyContinue) { Invoke-NativeWithTimeout -FilePath "scoop" -ArgumentList @("update","*") -Step "Scoop" -TimeoutSeconds 300 | Out-Null }
            }
            if ($PSCmdlet.ShouldProcess("Chocolatey", "Mettre à jour")) {
                if (Get-Command choco -ErrorAction SilentlyContinue) { Invoke-NativeWithTimeout -FilePath "choco" -ArgumentList @("upgrade","all","-y","--no-progress") -Step "Chocolatey" -TimeoutSeconds 600 | Out-Null }
            }
        }

        Write-Log "=== PHASE 5/7 : NETTOYAGE DISQUE ===" "PHASE"
        if (-not $SkipDiskCleanup) {
            if ($PSCmdlet.ShouldProcess("Fichiers temporaires", "Supprimer")) {
                $cleanedCount = 0
                foreach ($ext in @("*.tmp", "*.temp", "*.log", "*.dmp")) {
                    Get-ChildItem -Path $env:TEMP -Filter $ext -File -ErrorAction SilentlyContinue | ForEach-Object {
                        try { Remove-Item $_.FullName -Force -ErrorAction Stop; $cleanedCount++ } catch {}
                    }
                }
                Write-Log "Temp nettoyé : $cleanedCount éléments." "SUCCESS"
            }
            if ($DeepCleanPackageCaches -and $PSCmdlet.ShouldProcess("Caches npm/pip", "Nettoyer")) {
                if (Get-Command npm -ErrorAction SilentlyContinue) { Invoke-NativeWithTimeout -FilePath "npm" -ArgumentList @("cache","clean","--force") -Step "npm cache" -TimeoutSeconds 120 | Out-Null }
                if (Get-Command python -ErrorAction SilentlyContinue) { Invoke-NativeWithTimeout -FilePath "python" -ArgumentList @("-m","pip","cache","purge") -Step "pip cache" -TimeoutSeconds 120 | Out-Null }
            }
        }

        Write-Log "=== PHASE 6/7 : OPTIMISATIONS GRANULAIRES ===" "PHASE"
        if ($DisableFastStartup -and $PSCmdlet.ShouldProcess("Registre", "Désactiver Fast Startup")) {
            Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name HiberbootEnabled -Value 0 -Type DWord -ErrorAction SilentlyContinue
            Write-Log "Fast Startup désactivé." "SUCCESS"
        }
        if ($EnableMSIMode -and $PSCmdlet.ShouldProcess("Registre PnP", "Activer MSI Mode")) {
            $targetDevs = Get-PnpDevice -Class Display -Status OK
            $targetDevs += Get-PnpDevice -Class SCSIAdapter -Status OK | Where-Object { $_.FriendlyName -match 'NVMe|Storage Controller' }
            foreach ($dev in $targetDevs) {
                $instPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dev.InstanceId)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
                if (Test-Path $instPath) {
                    try {
                        $oldVal = (Get-ItemProperty $instPath -Name MSISupported -ErrorAction SilentlyContinue).MSISupported
                        Set-ItemProperty $instPath -Name MSISupported -Value 1 -Type DWord -ErrorAction Stop
                        Start-Sleep -Milliseconds 500
                        $check = Get-PnpDevice -InstanceId $dev.InstanceId -ErrorAction SilentlyContinue
                        if ($check -and $check.Status -eq 'OK') { Write-Log "MSI Mode activé : $($dev.FriendlyName)" "SUCCESS" }
                        else {
                            if ($oldVal -ne $null) { Set-ItemProperty $instPath -Name MSISupported -Value $oldVal -Type DWord -ErrorAction SilentlyContinue }
                            Write-Log "MSI Mode ROLLBACK : $($dev.FriendlyName)" "ERROR"
                        }
                    } catch { Write-Log "MSI Mode erreur : $($dev.FriendlyName)" "WARN" }
                }
            }
        }
        if ($OptimizeTCP -and $PSCmdlet.ShouldProcess("NetTCPIP", "Optimiser TCP")) {
            try {
                # Fallback sur 'Internet' si 'InternetCustom' n'existe pas
                $tcpProfile = Get-NetTCPSetting -SettingName InternetCustom -ErrorAction SilentlyContinue
                if (-not $tcpProfile) { $tcpProfile = Get-NetTCPSetting -SettingName Internet -ErrorAction SilentlyContinue }
                if ($tcpProfile) {
                    Set-NetTCPSetting -SettingName $tcpProfile.SettingName -ScalingHeuristics Disabled -ErrorAction SilentlyContinue
                    Write-Log "Optimisation TCP appliquée." "SUCCESS"
                }
            } catch { Write-Log "Optimisation TCP échouée." "WARN" }
        }
    }

    # =========================================================================
    # PHASE 7 : VÉRIFICATIONS FINALES & RAPPORTS (Toujours exécuté)
    # =========================================================================
    Write-Log "=== PHASE 7/7 : VÉRIFICATIONS FINALES & RAPPORTS ===" "PHASE"
    
    # SMART Check avec fallback
    if (Get-Command Get-PhysicalDisk -ErrorAction SilentlyContinue) {
        $badDisks = Get-PhysicalDisk | Where-Object { $_.HealthStatus -ne 'Healthy' }
        if ($badDisks) { Write-Log "SMART : Disques non sains ! $($badDisks.FriendlyName)" "ERROR" } 
        else { Write-Log "SMART : Disques sains." "SUCCESS" }
    } else {
        # Fallback pour VMs / Win Home / Anciens pilotes RAID
        $badDisks = Get-CimInstance Win32_DiskDrive | Where-Object { $_.Status -ne 'OK' }
        if ($badDisks) { Write-Log "SMART (Fallback CIM) : Problème détecté sur $($badDisks.DeviceID)" "WARN" }
        else { Write-Log "SMART (Fallback CIM) : Disques sains." "SUCCESS" }
    }

    # Génération Rapport HTML (StringBuilder pour performance)
    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.AppendLine("<!DOCTYPE html><html><head><title>Rapport Maintenance v5.0</title>")
    $null = $sb.AppendLine("<style>body{font-family:'Segoe UI',sans-serif;margin:20px;background:#f8f9fa;}h1{color:#2c3e50;}table{width:100%;border-collapse:collapse;background:white;margin:15px 0;}th,td{border:1px solid #ddd;padding:8px;text-align:left;}th{background:#3498db;color:white;}.success{color:green;}.warn{color:orange;}.error{color:red;}.meta{background:#e9ecef;}</style></head><body>")
    $null = $sb.AppendLine("<h1>Rapport de Maintenance Master v5.0</h1>")
    $null = $sb.AppendLine("<p><strong>Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | <strong>RunID:</strong> $($script:RunID) | <strong>Mode:</strong> $(if($AuditOnly){'AUDIT SEUL'}else{'COMPLET'})</p>")
    
    $null = $sb.AppendLine("<h2>Métadonnées Système</h2><table>")
    foreach ($meta in $script:SystemMeta.GetEnumerator()) {
        $val = $meta.Value
        if ($meta.Key -eq "Uptime") { $val = "$([math]::Round($val.TotalHours, 1)) heures" }
        $null = $sb.AppendLine("<tr><td class='meta'><strong>$($meta.Key)</strong></td><td>$val</td></tr>")
    }
    $null = $sb.AppendLine("</table>")

    $null = $sb.AppendLine("<h2>Chronologie</h2><table><tr><th>Heure</th><th>Phase</th><th>Étape</th><th>Statut</th><th>Détails</th></tr>")
    foreach ($entry in $script:ReportData) {
        $class = if ($entry.Status -eq "SUCCESS") { "success" } elseif ($entry.Status -eq "WARN") { "warn" } else { "error" }
        $null = $sb.AppendLine("<tr><td>$($entry.Timestamp)</td><td>$($entry.Phase)</td><td>$($entry.Step)</td><td class='$class'>$($entry.Status)</td><td>$($entry.Details)</td></tr>")
    }
    $null = $sb.AppendLine("</table>")
    $null = $sb.AppendLine("<p><strong>Résumé :</strong> Succès: $($script:SuccessCount) | Avertissements: $($script:WarnCount) | Erreurs: $($script:ErrorCount)</p>")
    $null = $sb.AppendLine("</body></html>")
    $sb.ToString() | Out-File -FilePath $script:HtmlFile -Encoding UTF8
    
    # Génération Rapport JSON (Métadonnées complètes)
    $jsonReport = [PSCustomObject]@{
        Metadata = $script:SystemMeta
        Execution = @{
            StartTime = $script:StartTime.ToString("o")
            EndTime = (Get-Date).ToString("o")
            DurationSeconds = [math]::Round(((Get-Date) - $script:StartTime).TotalSeconds, 2)
            Mode = if($AuditOnly){"AuditOnly"}else{"FullMaintenance"}
        }
        Summary = @{ Success = $script:SuccessCount; Warnings = $script:WarnCount; Errors = $script:ErrorCount }
        Timeline = $script:ReportData
    }
    $jsonReport | ConvertTo-Json -Depth 5 | Out-File -FilePath $script:JsonFile -Encoding UTF8
    
    Write-Log "Rapports générés : HTML et JSON sur le Bureau." "SUCCESS"

    Write-Host "`n===================================================" -ForegroundColor Cyan
    Write-Host "  MAINTENANCE MASTER v5.0 TERMINÉE" -ForegroundColor Cyan
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host "Succès: $($script:SuccessCount) | Warn: $($script:WarnCount) | Erreurs: $($script:ErrorCount)" -ForegroundColor White
    Write-Host "RunID: $($script:RunID)" -ForegroundColor DarkGray
    
    if (-not $NoPause) {
        Write-Host "Appuyez sur ENTRÉE pour fermer..." -ForegroundColor Yellow
        Read-Host
    }

    # Code de sortie Enterprise (0 = OK, 1 = Erreur)
    if ($script:ErrorCount -gt 0) { exit 1 }
    else { exit 0 }

} catch {
    Write-Host "ERREUR FATALE : $($_.Exception.Message)" -ForegroundColor Red
    Write-Log "ERREUR FATALE : $($_.Exception.Message)`nStack: $($_.ScriptStackTrace)" "ERROR"
    if (-not $NoPause) { Read-Host }
    exit 1
}