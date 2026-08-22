<#
Audit des programmes installés + analyse du disque D:
- Liste tous les programmes (Registre, Winget, Choco, Scoop, Store)
- Affiche leur chemin d'installation
- Détecte si installés sur D:
- Détecte si utilisés récemment (via LastWriteTime)
- Génère un rapport sur le Bureau
Compatible PowerShell 7.x
#>

$ErrorActionPreference = "Stop"

# Chemin du rapport
$desktop = [Environment]::GetFolderPath("Desktop")
$report  = Join-Path $desktop "Audit_D_Applications.txt"

# Buffer
$result = [System.Collections.Generic.List[string]]::new()

function Add {
    param([string]$t)
    $result.Add($t)
}

function Section {
    param([string]$title)
    Add ""
    Add ("=" * 80)
    Add $title
    Add ("=" * 80)
}

# --- Fonction pour récupérer les apps du registre ---
function Get-RegApps {
    param([string]$path)
    try {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName } |
            Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation
    }
    catch { @() }
}

# --- SECTION : PROGRAMMES INSTALLÉS ---
Section "PROGRAMMES INSTALLÉS (REGISTRE)"

$regPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$apps = foreach ($p in $regPaths) { Get-RegApps -path $p }
$apps = $apps | Sort-Object DisplayName -Unique

foreach ($app in $apps) {
    $loc = $app.InstallLocation
    if (-not $loc) { $loc = "[Chemin non fourni]" }

    # Détection si installé sur D:
    $onD = $loc -like "D:*"

    # Détection d'utilisation (si dossier existe)
    $used = "Inconnu"
    if (Test-Path $loc) {
        $last = (Get-ChildItem $loc -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
        if ($last) {
            $used = "Dernière activité : " + $last.LastWriteTime
        }
    }

    Add "Nom              : $($app.DisplayName)"
    Add "Version          : $($app.DisplayVersion)"
    Add "Éditeur          : $($app.Publisher)"
    Add "Chemin           : $loc"
    Add "Installé sur D:  : $onD"
    Add "Utilisation      : $used"
    Add ""
}

# --- SECTION : WINGET ---
Section "APPLICATIONS WINGET"

if (Get-Command winget -ErrorAction SilentlyContinue) {
    $wg = winget list --accept-source-agreements 2>$null
    Add $wg
} else {
    Add "Winget non installé."
}

# --- SECTION : CHOCOLATEY ---
Section "APPLICATIONS CHOCOLATEY"

if (Get-Command choco -ErrorAction SilentlyContinue) {
    $ch = choco list -lo 2>$null
    Add $ch
} else {
    Add "Chocolatey non installé."
}

# --- SECTION : SCOOP ---
Section "APPLICATIONS SCOOP"

if (Get-Command scoop -ErrorAction SilentlyContinue) {
    $sc = scoop list 2>$null
    Add $sc
} else {
    Add "Scoop non installé."
}

# --- SECTION : MICROSOFT STORE ---
Section "APPLICATIONS MICROSOFT STORE"

try {
    $store = Get-AppxPackage -ErrorAction SilentlyContinue
    foreach ($s in $store) {
        Add "Nom        : $($s.Name)"
        Add "Version    : $($s.Version)"
        Add "Chemin     : $($s.InstallLocation)"
        Add "Sur D:     : " + ($s.InstallLocation -like "D:*")
        Add ""
    }
}
catch {
    Add "Erreur Microsoft Store : $($_.Exception.Message)"
}

# --- SECTION : DOSSIERS SUR D: ---
Section "CONTENU DU DISQUE D:"

if (Test-Path "D:\") {
    $folders = Get-ChildItem "D:\" -Directory -Force
    foreach ($f in $folders) {
        Add "Dossier : $($f.FullName)"
    }
} else {
    Add "Le lecteur D: n'existe pas."
}

# --- Écriture du rapport ---
Set-Content -Path $report -Value $result -Encoding UTF8

Write-Host "Audit terminé. Rapport sur le Bureau : $report" -ForegroundColor Green
Write-Host "Appuyez sur Entrée pour fermer..." -ForegroundColor Yellow
[void][System.Console]::ReadLine()
