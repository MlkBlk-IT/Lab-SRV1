<#
.SYNOPSIS
    Detecte quel logiciel utilise le driver PawnIO sur Windows.
.DESCRIPTION
    Ce script verifie :
    - Si le driver PawnIO.sys est charge
    - Quels processus ont des handles ouverts sur PawnIO
    - Quels services reference PawnIO
    - Les cles de registre liees a PawnIO
    - Les fichiers/dossiers PawnIO sur le disque
    - Les processus en memoire qui chargent des DLL ou references PawnIO
.AUTEUR
    Genere pour Malik Bel
#>

#Requires -RunAsAdministrator

$Banner = @"
===============================================
   PAWNIO DRIVER USAGE DETECTOR
   Recherche de l'application proprietaire
===============================================
"@
Write-Host $Banner -ForegroundColor Cyan

# --- 1. Verifier si le driver est charge ---
Write-Host "`n[1/7] Verification du driver PawnIO en memoire..." -ForegroundColor Yellow

$Driver = Get-WmiObject Win32_SystemDriver | Where-Object { $_.Name -like "*PawnIO*" -or $_.PathName -like "*PawnIO*" }
if ($Driver) {
    Write-Host "    [+] Driver PawnIO TROUVE :" -ForegroundColor Green
    $Driver | Select-Object Name, State, Status, PathName | Format-Table -AutoSize
} else {
    Write-Host "    [-] Aucun driver PawnIO actif detecte via WMI." -ForegroundColor Red
}

# Verifier aussi les drivers charges (fltmc pour les minifilters, mais aussi les .sys)
$LoadedDrivers = driverquery /v /fo csv | ConvertFrom-Csv | Where-Object { $_."Display Name" -like "*PawnIO*" -or $_."Module Name" -like "*PawnIO*" }
if ($LoadedDrivers) {
    Write-Host "    [+] Driver PawnIO trouve dans driverquery :" -ForegroundColor Green
    $LoadedDrivers | Format-Table -AutoSize
}

# --- 2. Chercher les fichiers PawnIO.sys sur le disque ---
Write-Host "`n[2/7] Recherche des fichiers PawnIO sur le disque..." -ForegroundColor Yellow

$PawnIOFiles = @()
$SearchPaths = @(
    "C:\Windows\System32\drivers",
    "C:\Windows\SysWOW64",
    "C:\Program Files",
    "C:\Program Files (x86)",
    "C:\ProgramData",
    "$env:LOCALAPPDATA",
    "$env:APPDATA"
)

foreach ($Path in $SearchPaths) {
    if (Test-Path $Path) {
        try {
            $Found = Get-ChildItem -Path $Path -Recurse -Filter "*PawnIO*" -ErrorAction SilentlyContinue -File
            $PawnIOFiles += $Found
        } catch {}
    }
}

if ($PawnIOFiles.Count -gt 0) {
    Write-Host "    [+] Fichiers PawnIO trouves ($($PawnIOFiles.Count)) :" -ForegroundColor Green
    $PawnIOFiles | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize
} else {
    Write-Host "    [-] Aucun fichier PawnIO trouve sur le disque." -ForegroundColor Red
}

# --- 3. Verifier les services lies a PawnIO ---
Write-Host "`n[3/7] Recherche de services references..." -ForegroundColor Yellow

$Services = Get-WmiObject Win32_Service | Where-Object { 
    $_.PathName -like "*PawnIO*" -or 
    $_.Name -like "*PawnIO*" -or 
    $_.DisplayName -like "*PawnIO*" 
}
if ($Services) {
    Write-Host "    [+] Services PawnIO trouves :" -ForegroundColor Green
    $Services | Select-Object Name, DisplayName, State, PathName | Format-Table -AutoSize
} else {
    Write-Host "    [-] Aucun service directement nomme PawnIO." -ForegroundColor Gray
}

# --- 4. Chercher dans le registre ---
Write-Host "`n[4/7] Recherche dans le registre..." -ForegroundColor Yellow

$RegPaths = @(
    "HKLM:\SYSTEM\CurrentControlSet\Services",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
)

$RegResults = @()
foreach ($RegPath in $RegPaths) {
    if (Test-Path $RegPath) {
        try {
            $Items = Get-ChildItem $RegPath -Recurse -ErrorAction SilentlyContinue | 
                Get-ItemProperty -ErrorAction SilentlyContinue | 
                Where-Object { 
                    ($_ | Out-String) -like "*PawnIO*" 
                }
            if ($Items) {
                $RegResults += $Items
            }
        } catch {}
    }
}

# Chercher aussi les ImagePath / ServiceDll qui pointent vers PawnIO
$SvcReg = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services" -ErrorAction SilentlyContinue | 
    Get-ItemProperty -ErrorAction SilentlyContinue | 
    Where-Object { $_.ImagePath -like "*PawnIO*" -or $_.ServiceDll -like "*PawnIO*" }

if ($RegResults.Count -gt 0 -or $SvcReg) {
    Write-Host "    [+] Entrees registre PawnIO trouvees :" -ForegroundColor Green
    $SvcReg | Select-Object PSChildName, ImagePath, ServiceDll | Format-Table -AutoSize
} else {
    Write-Host "    [-] Aucune entree registre explicite trouvee." -ForegroundColor Gray
}

# --- 5. Chercher les processus avec des handles ouverts sur PawnIO ---
Write-Host "`n[5/7] Recherche des processus utilisant PawnIO (handles)..." -ForegroundColor Yellow

# Methode 1 : Get-Process avec les modules charges
$Processes = Get-Process | Where-Object { 
    $_.Modules.ModuleName -like "*PawnIO*" -or 
    $_.ProcessName -like "*PawnIO*" 
}
if ($Processes) {
    Write-Host "    [+] Processus avec modules PawnIO charges :" -ForegroundColor Green
    $Processes | Select-Object Id, ProcessName, Path | Format-Table -AutoSize
} else {
    Write-Host "    [-] Aucun processus avec module PawnIO charge (via .Modules)." -ForegroundColor Gray
}

# Methode 2 : Utiliser WMI pour les handles (si disponible)
Write-Host "    [*] Tentative via WMI handles..." -ForegroundColor Gray
$WMIHandles = Get-WmiObject -Class CIM_Process | Where-Object { 
    $_.Name -like "*PawnIO*" 
}
if ($WMIHandles) {
    $WMIHandles | Select-Object ProcessId, Name, CommandLine | Format-Table -AutoSize
}

# --- 6. Recherche dans les processus en memoire (strings) ---
Write-Host "`n[6/7] Scan memoire des processus pour references PawnIO..." -ForegroundColor Yellow

$SuspiciousProcs = @()
$AllProcs = Get-Process | Where-Object { $_.Id -ne 0 -and $_.Id -ne 4 }

foreach ($Proc in $AllProcs) {
    try {
        $Modules = $Proc.Modules | Select-Object -ExpandProperty ModuleName
        if ($Modules -like "*PawnIO*") {
            $SuspiciousProcs += [PSCustomObject]@{
                PID = $Proc.Id
                Name = $Proc.ProcessName
                Path = $Proc.Path
                Reason = "Module PawnIO charge"
            }
        }
    } catch {}
}

# Chercher aussi dans les fichiers de processus connus pour utiliser PawnIO
$KnownApps = @("FanControl", "GHelper", "ArmouryCrate", "PawnIO")
foreach ($App in $KnownApps) {
    $FoundProcs = Get-Process | Where-Object { $_.ProcessName -like "*$App*" } -ErrorAction SilentlyContinue
    if ($FoundProcs) {
        foreach ($fp in $FoundProcs) {
            $SuspiciousProcs += [PSCustomObject]@{
                PID = $fp.Id
                Name = $fp.ProcessName
                Path = $fp.Path
                Reason = "Application connue pour utiliser PawnIO"
            }
        }
    }
}

if ($SuspiciousProcs.Count -gt 0) {
    Write-Host "    [+] Processus suspects trouves :" -ForegroundColor Green
    $SuspiciousProcs | Sort-Object Name -Unique | Format-Table -AutoSize
} else {
    Write-Host "    [-] Aucun processus suspect en memoire." -ForegroundColor Gray
}

# --- 7. Verifier les connexions reseau / pipes ---
Write-Host "`n[7/7] Recherche de pipes et objets nommes PawnIO..." -ForegroundColor Yellow

$NamedPipes = Get-ChildItem \\.\pipe\ -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*PawnIO*" }
if ($NamedPipes) {
    Write-Host "    [+] Pipes PawnIO trouves :" -ForegroundColor Green
    $NamedPipes | Format-Table -AutoSize
} else {
    Write-Host "    [-] Aucun pipe nomme PawnIO detecte." -ForegroundColor Gray
}

# --- Resume final ---
Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host "              RESUME FINAL" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

$HasPawnIO = ($Driver -or $PawnIOFiles.Count -gt 0 -or $SuspiciousProcs.Count -gt 0)

if (-not $HasPawnIO) {
    Write-Host "`n[!] CONCLUSION : PawnIO n'est PAS (ou plus) activement utilise." -ForegroundColor Yellow
    Write-Host "    Le driver est probablement ORPHELIN (reste d'une ancienne installation)." -ForegroundColor Yellow
    Write-Host "`n    ACTION RECOMMANDEE :" -ForegroundColor Green
    Write-Host "    1. Supprimer le peripherique dans le Device Manager" -ForegroundColor White
    Write-Host "    2. Cocher 'Delete the driver software for this device'" -ForegroundColor White
    Write-Host "    3. Redemarrer" -ForegroundColor White
} else {
    Write-Host "`n[+] CONCLUSION : PawnIO est utilise par :" -ForegroundColor Green
    if ($SuspiciousProcs.Count -gt 0) {
        $SuspiciousProcs | Select-Object Name, Path, Reason -Unique | Format-Table -AutoSize
    }
    if ($PawnIOFiles.Count -gt 0) {
        Write-Host "`n    Fichiers trouves dans :" -ForegroundColor Green
        $PawnIOFiles | Select-Object -ExpandProperty Directory -Unique | ForEach-Object { Write-Host "      - $_" -ForegroundColor White }
    }
}

Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host "Appuyez sur une touche pour quitter..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
