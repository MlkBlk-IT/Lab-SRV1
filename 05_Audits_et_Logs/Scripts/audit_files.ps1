<#
Audit complet du disque D:
- Analyse tous les fichiers et dossiers
- Catégorisation (VM, ISO, archives, projets, logs, caches, etc.)
- Dernière utilisation (LastWriteTime + LastAccessTime)
- Taille
- Programme probable associé
- Risque si supprimé
- Rapport complet sur le Bureau
Compatible PowerShell 7.x
#>

$ErrorActionPreference = "Stop"

# Chemin du rapport
$desktop = [Environment]::GetFolderPath("Desktop")
$report  = Join-Path $desktop "Audit_D_Fichiers_Complet.txt"

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

# --- Vérification du lecteur D: ---
if (-not (Test-Path "D:\")) {
    Add "Le lecteur D: n'existe pas."
    Set-Content -Path $report -Value $result -Encoding UTF8
    exit
}

# --- SECTION : Résumé global ---
Section "RÉSUMÉ GLOBAL DU DISQUE D:"

$files = Get-ChildItem "D:\" -Recurse -Force -ErrorAction SilentlyContinue
$totalSize = ($files | Measure-Object -Property Length -Sum).Sum
Add ("Taille totale des fichiers : {0:N2} GB" -f ($totalSize / 1GB))
Add ("Nombre total de fichiers  : " + $files.Count)

# --- SECTION : Analyse détaillée ---
Section "ANALYSE DÉTAILLÉE DES FICHIERS"

foreach ($f in $files) {

    $type = "Inconnu"
    $risk = "Inconnu"
    $program = "Inconnu"

    # Catégorisation par extension
    switch ($f.Extension.ToLower()) {
        ".vhdx" { $type = "Disque virtuel Hyper-V"; $risk = "CRITIQUE"; $program = "Hyper-V" }
        ".vmdk" { $type = "Disque virtuel VMware"; $risk = "CRITIQUE"; $program = "VMware" }
        ".qcow2" { $type = "Disque virtuel QEMU"; $risk = "CRITIQUE"; $program = "QEMU" }
        ".vmx" { $type = "Configuration VMware"; $risk = "CRITIQUE"; $program = "VMware" }
        ".iso" { $type = "Image disque ISO"; $risk = "Faible"; $program = "Installateurs / VM" }
        ".zip" { $type = "Archive ZIP"; $risk = "Faible"; $program = "Divers" }
        ".rar" { $type = "Archive RAR"; $risk = "Faible"; $program = "Divers" }
        ".7z" { $type = "Archive 7z"; $risk = "Faible"; $program = "Divers" }
        ".log" { $type = "Fichier log"; $risk = "Faible"; $program = "Applications diverses" }
        ".txt" { $type = "Texte"; $risk = "Faible"; $program = "Divers" }
        ".exe" { $type = "Exécutable"; $risk = "Moyen"; $program = "Programme portable" }
        ".msi" { $type = "Installateur"; $risk = "Faible"; $program = "Setup" }
        ".json" { $type = "Config JSON"; $risk = "Faible"; $program = "Applications diverses" }
        ".xml" { $type = "Config XML"; $risk = "Faible"; $program = "Applications diverses" }
        ".ps1" { $type = "Script PowerShell"; $risk = "Moyen"; $program = "PowerShell" }
        ".py" { $type = "Script Python"; $risk = "Moyen"; $program = "Python" }
        ".js" { $type = "Script JavaScript"; $risk = "Moyen"; $program = "Node.js" }
        ".html" { $type = "Page HTML"; $risk = "Faible"; $program = "Web" }
        ".pdf" { $type = "Document PDF"; $risk = "Faible"; $program = "Documents" }
        ".docx" { $type = "Document Word"; $risk = "Faible"; $program = "Office" }
        ".xlsx" { $type = "Document Excel"; $risk = "Faible"; $program = "Office" }
        default { $type = "Autre / Non catégorisé" }
    }

    Add "Fichier : $($f.FullName)"
    Add ("Taille  : {0:N2} MB" -f ($f.Length / 1MB))
    Add "Type    : $type"
    Add "Programme associé : $program"
    Add "Risque si supprimé : $risk"
    Add "Dernière modification : $($f.LastWriteTime)"
    Add "Dernier accès        : $($f.LastAccessTime)"
    Add ""
}

# --- Écriture du rapport ---
Set-Content -Path $report -Value $result -Encoding UTF8

Write-Host "Audit complet terminé. Rapport sur le Bureau : $report" -ForegroundColor Green
Write-Host "Appuyez sur Entrée pour fermer..." -ForegroundColor Yellow
[void][System.Console]::ReadLine()
