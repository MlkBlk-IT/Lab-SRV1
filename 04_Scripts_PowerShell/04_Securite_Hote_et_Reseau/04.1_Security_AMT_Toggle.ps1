#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Intel AMT / LMS Port Security Toggle
    Auteur  : Tech-Malik
    Machine : TECH-MALIK — Dell Latitude 5420 (i7 vPro)
    Ports   : 623, 664, 16992, 16993 (Intel AMT/LMS)
    Usage   : .\AMT-Toggle.ps1
#>

$LogFile  = "D:\AMT-Toggle-Log.txt"
$Ports    = @(623, 664, 16992, 16993)
$RuleName = "TECH-MALIK_AMT_Block"

function Write-Log {
    param([string]$Message)
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Add-Content -Path $LogFile -Value $entry
}

function Show-Status {
    $svc       = Get-Service -Name LMS -ErrorAction SilentlyContinue
    $rules     = Get-NetFirewallRule -DisplayName "${RuleName}_IN_623" -ErrorAction SilentlyContinue
    $listeners = Get-NetTCPConnection | Where-Object { $_.LocalPort -in $Ports -and $_.State -eq "Listen" }

    Write-Host ""
    Write-Host "====== STATUT INTEL AMT / LMS ======" -ForegroundColor Cyan

    # Service
    if ($svc) {
        $color = if ($svc.Status -eq "Running") { "Yellow" } else { "Green" }
        Write-Host "  Service LMS    : $($svc.Status) / Demarrage: $($svc.StartType)" -ForegroundColor $color
    } else {
        Write-Host "  Service LMS    : Introuvable" -ForegroundColor Red
    }

    # Firewall
    if ($rules) {
        Write-Host "  Firewall       : ACTIF — ports bloques" -ForegroundColor Green
        Write-Host "  Securite       : SECURISE" -ForegroundColor Green
    } else {
        Write-Host "  Firewall       : INACTIF — ports exposes" -ForegroundColor Yellow
        Write-Host "  Securite       : EXPOSE" -ForegroundColor Yellow
    }

    # Ports
    Write-Host "  Ports en ecoute :" -ForegroundColor Cyan
    if ($listeners) {
        foreach ($l in $listeners) {
            Write-Host "    Port $($l.LocalPort) — $($l.LocalAddress) — PID $($l.OwningProcess)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "    Aucun port AMT visible sur le reseau" -ForegroundColor Green
    }

    Write-Host "====================================" -ForegroundColor Cyan
    Write-Host ""

    # Retourne l'etat pour savoir quoi proposer
    return ($null -ne $rules)
}

function Do-Lock {
    foreach ($port in $Ports) {
        $nameIn  = "${RuleName}_IN_$port"
        $nameOut = "${RuleName}_OUT_$port"
        Remove-NetFirewallRule -DisplayName $nameIn  -ErrorAction SilentlyContinue
        Remove-NetFirewallRule -DisplayName $nameOut -ErrorAction SilentlyContinue
        New-NetFirewallRule -DisplayName $nameIn  -Direction Inbound  -Protocol TCP -LocalPort $port  -Action Block -Profile Any -Enabled True | Out-Null
        New-NetFirewallRule -DisplayName $nameOut -Direction Outbound -Protocol TCP -RemotePort $port -Action Block -Profile Any -Enabled True | Out-Null
    }
    Write-Log "ACTION: Lock — Ports AMT 623/664/16992/16993 bloques via Firewall"
    Write-Host "  Ports AMT bloques avec succes." -ForegroundColor Green
}

function Do-Unlock {
    foreach ($port in $Ports) {
        Remove-NetFirewallRule -DisplayName "${RuleName}_IN_$port"  -ErrorAction SilentlyContinue
        Remove-NetFirewallRule -DisplayName "${RuleName}_OUT_$port" -ErrorAction SilentlyContinue
    }
    Write-Log "ACTION: Unlock — Ports AMT 623/664/16992/16993 reuverts"
    Write-Host "  Ports AMT reuverts avec succes." -ForegroundColor Yellow
}

# ─── MAIN ───────────────────────────────────────────────────────────────────

Clear-Host
Write-Host ""
Write-Host "  INTEL AMT PORT MANAGER — TECH-MALIK" -ForegroundColor Cyan
Write-Host ""

# Etape 1 — Afficher le statut actuel
Write-Host "  [1/3] Statut actuel :" -ForegroundColor White
$isLocked = Show-Status

# Etape 2 — Demander l'action
if ($isLocked) {
    Write-Host "  Ports actuellement BLOQUES." -ForegroundColor Green
    Write-Host "  Que voulez-vous faire ?" -ForegroundColor White
    Write-Host "    [L] Lock   (reappliquer)"
    Write-Host "    [U] Unlock (ouvrir les ports)"
} else {
    Write-Host "  Ports actuellement EXPOSES." -ForegroundColor Yellow
    Write-Host "  Que voulez-vous faire ?" -ForegroundColor White
    Write-Host "    [L] Lock   (bloquer les ports)"
    Write-Host "    [U] Unlock (laisser ouverts)"
}

Write-Host ""
$choice = Read-Host "  Entrez L ou U"
Write-Host ""

# Etape 3 — Executer
switch ($choice.ToUpper()) {
    "L" {
        Write-Host "  [2/3] Execution : Lock en cours..." -ForegroundColor White
        Do-Lock
    }
    "U" {
        Write-Host "  [2/3] Execution : Unlock en cours..." -ForegroundColor White
        Do-Unlock
    }
    default {
        Write-Host "  Choix invalide. Script termine." -ForegroundColor Red
        exit
    }
}

Write-Host ""

# Etape 4 — Confirmer le nouveau statut
Write-Host "  [3/3] Nouveau statut :" -ForegroundColor White
Show-Status | Out-Null

Write-Host "  Log enregistre dans : D:\AMT-Toggle-Log.txt" -ForegroundColor Cyan
Write-Host ""