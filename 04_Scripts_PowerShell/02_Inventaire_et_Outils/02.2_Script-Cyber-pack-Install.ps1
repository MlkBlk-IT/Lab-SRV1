<#
.SYNOPSIS
    INSTALLATION CYBER-PACK - Script unifié d'installation complète.
.DESCRIPTION
    Installe Hyper-V, WSL2, Virtual Machine Platform, Windows Sandbox, 
    Windows Containers, Telnet et les outils RSAT (AD, DNS, GPO).
    Utilise Windows Update (-Online) pour récupérer toutes les sources.
    Nécessite un seul redémarrage à la fin pour finaliser l'ensemble.
#>
#Requires -RunAsAdministrator

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " INSTALLATION CYBER-PACK (Stack Complète)" -ForegroundColor Cyan
Write-Host "========================================================`n" -ForegroundColor Cyan

$restartNeeded = $false

# --- SECTION 1 : FONCTIONNALITÉS WINDOWS (DISM) ---
Write-Host "[1] Activation des fonctionnalités Windows (via Windows Update)..." -ForegroundColor Yellow
$dismFeatures = @(
    "Microsoft-Hyper-V-All",             # Hyper-V Complet (Hyperviseur, Services, Outils)
    "Microsoft-Windows-Subsystem-Linux", # WSL
    "VirtualMachinePlatform",            # Plateforme VM (Requis WSL2/Sandbox)
    "Containers-DisposableClientVM",     # Windows Sandbox
    "Containers",                        # Windows Containers
    "TelnetClient"                        # Client Telnet
)

foreach ($feat in $dismFeatures) {
    Write-Host "  Installation de $feat..." -ForegroundColor Gray
    try {
        $result = Enable-WindowsOptionalFeature -Online -FeatureName $feat -All -NoRestart -ErrorAction Stop
        if ($result.RestartNeeded) { $restartNeeded = $true }
        Write-Host "    [OK] $feat activé." -ForegroundColor Green
    } catch {
        Write-Warning "  [ERREUR] Échec de $feat : $_"
    }
}

# --- SECTION 2 : OUTILS RSAT (Features on Demand) ---
Write-Host "`n[2] Installation des outils RSAT (via Windows Update)..." -ForegroundColor Yellow
$rsatCapabilities = @(
    "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0",
    "Rsat.DNS.Tools~~~~0.0.1.0",
    "Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0"
)

foreach ($cap in $rsatCapabilities) {
    Write-Host "  Installation de $cap..." -ForegroundColor Gray
    try {
        $result = Add-WindowsCapability -Online -Name $cap -ErrorAction Stop
        if ($result.RestartNeeded) { $restartNeeded = $true }
        Write-Host "    [OK] $cap installé." -ForegroundColor Green
    } catch {
        Write-Warning "  [ERREUR] Échec de $cap : $_"
        Write-Warning "  Vérifiez votre connexion Internet / Windows Update."
    }
}

# --- SECTION 3 : MISE À JOUR DU NOYAU WSL ---
Write-Host "`n[3] Mise à jour du noyau WSL..." -ForegroundColor Yellow
try {
    wsl --update --web-download 2>&1 | Out-Null
    Write-Host "    [OK] Noyau WSL mis à jour." -ForegroundColor Green
} catch {
    Write-Warning "  [INFO] Mise à jour WSL ignorée ou déjà à jour."
}

# --- RÉSUMÉ FINAL ---
Write-Host "`n========================================================" -ForegroundColor Cyan
if ($restartNeeded) {
    Write-Host "✅ INSTALLATION CYBER-PACK TERMINÉE." -ForegroundColor Green
    Write-Host "⚠ UN REDÉMARRAGE DU SYSTÈME EST OBLIGATOIRE." -ForegroundColor Yellow
    Write-Host "Après le redémarrage, nous passerons à la Phase 4 (Architecture D:\VM & Réseau)." -ForegroundColor Cyan
} else {
    Write-Host "✅ INSTALLATION TERMINÉE. AUCUN REDÉMARRAGE REQUIS." -ForegroundColor Green
}
Write-Host "========================================================" -ForegroundColor Cyan