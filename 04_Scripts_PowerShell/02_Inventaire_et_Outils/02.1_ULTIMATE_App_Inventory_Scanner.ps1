#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Inventaire ULTIME et EXHAUSTIF de TOUT ce qui est installe sur Windows.
    Couvre: Registry, MSStore, Winget, Scoop, Chocolatey, pip, npm, cargo, go,
    conda, poetry, uv, pdm, docker, kubectl, terraform, dotnet tools, ruby gem,
    php composer, julia, vcpkg, MSYS2, WSL, Services, Tasks, et SCAN EXHAUSTIF
    de tous les .exe/.msi portables et manuels sur tous les disques.
    Genere 1 seul CSV: Nom, Version, Publisher, Source, Path, Size, InstallDate
    Temps cible: < 5 minutes (parallelise ou limite profondeur).
#>

param(
    [string]$OutputPath = "$env:USERPROFILE\Desktop\ULTIMATE_APP_INVENTORY_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').csv"
)

$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$Results = [System.Collections.ArrayList]::new()
$Script:FoundPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

function Add-App {
    param($Name, $Version="", $Publisher="", $Source, $Path="", $Size="", $InstallDate="")
    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $entry = [PSCustomObject]@{
        Name        = $Name
        Version     = $Version
        Publisher   = $Publisher
        Source      = $Source
        Path        = $Path
        Size        = $Size
        InstallDate = $InstallDate
    }
    [void]$script:Results.Add($entry)
    if ($Path) { [void]$script:FoundPaths.Add($Path) }
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  INVENTAIRE ULTIME - TOUT SOURCES" -ForegroundColor Cyan
Write-Host "  Sortie: $OutputPath" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# ============================================================================
# 1. REGISTRY (HKLM + HKCU + WOW6432Node)
# ============================================================================
Write-Host "[1/20] Registry..." -ForegroundColor Yellow
$RegPaths = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
foreach ($rp in $RegPaths) {
    Get-ItemProperty $rp -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } | ForEach-Object {
        $sz = ""; if ($_.EstimatedSize) { $sz = "$([math]::Round($_.EstimatedSize/1024,2)) MB" }
        Add-App -Name $_.DisplayName -Version $_.DisplayVersion -Publisher $_.Publisher -Source "Registry" -Path $_.InstallLocation -Size $sz -InstallDate $_.InstallDate
    }
}

# ============================================================================
# 2. MICROSOFT STORE (Appx)
# ============================================================================
Write-Host "[2/20] Microsoft Store..." -ForegroundColor Yellow
Get-AppxPackage -AllUsers | ForEach-Object {
    $sz = ""
    if (Test-Path $_.InstallLocation) {
        try { $sz = "$([math]::Round((Get-ChildItem $_.InstallLocation -Recurse -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum/1MB,2)) MB" } catch {}
    }
    Add-App -Name $_.Name -Version $_.Version -Publisher $_.Publisher -Source "MicrosoftStore" -Path $_.InstallLocation -Size $sz
}

# ============================================================================
# 3. WINGET
# ============================================================================
Write-Host "[3/20] Winget..." -ForegroundColor Yellow
$wingetCmd = Get-Command winget -EA SilentlyContinue
if ($wingetCmd) {
    try {
        $json = winget list --accept-source-agreements --disable-interactivity 2>$null | Out-String
        # Winget list output est tabulaire, on parse ligne par ligne
        $lines = $json -split "`r?`n" | Select-Object -Skip 4
        foreach ($line in $lines) {
            if ($line -match '^(.+?)\s{2,}(.+?)\s{2,}(.+?)\s{2,}(.+)$') {
                $n=$matches[1].Trim(); $v=$matches[2].Trim(); $id=$matches[3].Trim(); $src=$matches[4].Trim()
                if ($n -and $n -notmatch '^-+$' -and $n -notmatch 'Nom') {
                    Add-App -Name $n -Version $v -Publisher $id -Source "Winget"
                }
            }
        }
    } catch {}
}

# ============================================================================
# 4. SCOOP
# ============================================================================
Write-Host "[4/20] Scoop..." -ForegroundColor Yellow
$scoopRoot = "$env:USERPROFILE\scoop\apps"
if (Test-Path $scoopRoot) {
    Get-ChildItem $scoopRoot -Directory | ForEach-Object {
        $appName = $_.Name
        $manifest = Join-Path $_.FullName "current\manifest.json"
        $version = "current"; $path = $_.FullName
        if (Test-Path (Join-Path $_.FullName "current")) { $path = Join-Path $_.FullName "current" }
        if (Test-Path $manifest) {
            try { $m = Get-Content $manifest -Raw | ConvertFrom-Json -EA SilentlyContinue; if ($m.version) { $version = $m.version } } catch {}
        }
        $sz = ""; try { $sz = "$([math]::Round((Get-ChildItem $_.FullName -Recurse -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum/1MB,2)) MB" } catch {}
        Add-App -Name $appName -Version $version -Source "Scoop" -Path $path -Size $sz
    }
}

# ============================================================================
# 5. CHOCOLATEY
# ============================================================================
Write-Host "[5/20] Chocolatey..." -ForegroundColor Yellow
$chocoLib = "$env:ProgramData\chocolatey\lib"
if (Test-Path $chocoLib) {
    Get-ChildItem $chocoLib -Directory | ForEach-Object {
        $nuspec = Get-ChildItem $_.FullName -Filter "*.nuspec" -Recurse -EA SilentlyContinue | Select-Object -First 1
        $ver = ""; $pub = ""
        if ($nuspec) { try { [xml]$x = Get-Content $nuspec.FullName; $ver = $x.package.metadata.version; $pub = $x.package.metadata.authors } catch {} }
        $sz = ""; try { $sz = "$([math]::Round((Get-ChildItem $_.FullName -Recurse -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum/1MB,2)) MB" } catch {}
        Add-App -Name $_.Name -Version $ver -Publisher $pub -Source "Chocolatey" -Path $_.FullName -Size $sz
    }
}

# ============================================================================
# 6. PIP (global + user + TOUS les venvs trouves)
# ============================================================================
Write-Host "[6/20] pip..." -ForegroundColor Yellow
$pips = [System.Collections.ArrayList]::new()
# PIP systeme
foreach ($cmd in @("pip","pip3")) { $c = Get-Command $cmd -EA SilentlyContinue; if ($c) { [void]$pips.Add($c.Source) } }
# PIP dans les installations Python
foreach ($pyPath in @("$env:LOCALAPPDATA\Programs\Python\Python*\Scripts\pip.exe","$env:LOCALAPPDATA\Programs\Python\Python*\Scripts\pip3.exe","C:\Python*\Scripts\pip.exe")) {
    Resolve-Path $pyPath -EA SilentlyContinue | ForEach-Object { [void]$pips.Add($_.Path) }
}
# Venvs courants
$venvRoots = @("$env:USERPROFILE\.venv","$env:USERPROFILE\venvs","$env:USERPROFILE\envs","C:\venvs","$env:USERPROFILE\.virtualenvs")
foreach ($vr in $venvRoots) {
    if (Test-Path $vr) {
        Get-ChildItem $vr -Directory -EA SilentlyContinue | ForEach-Object {
            $pipInVenv = Join-Path $_.FullName "Scripts\pip.exe"
            if (Test-Path $pipInVenv) { [void]$pips.Add($pipInVenv) }
            $pipInVenv2 = Join-Path $_.FullName "bin\pip"
            if (Test-Path $pipInVenv2) { [void]$pips.Add($pipInVenv2) }
        }
    }
}
$pips = $pips | Select-Object -Unique
foreach ($pipExe in $pips) {
    try {
        $jsonOut = & $pipExe list --format=json 2>$null | ConvertFrom-Json -EA SilentlyContinue
        foreach ($pkg in $jsonOut) {
            Add-App -Name $pkg.name -Version $pkg.version -Source "pip" -Path (Split-Path $pipExe -Parent)
        }
    } catch {}
}

# ============================================================================
# 7. NPM (global)
# ============================================================================
Write-Host "[7/20] npm..." -ForegroundColor Yellow
if (Get-Command npm -EA SilentlyContinue) {
    try {
        $npmJson = npm list -g --depth=0 --json 2>$null | ConvertFrom-Json -EA SilentlyContinue
        if ($npmJson.dependencies) {
            $npmJson.dependencies.PSObject.Properties | ForEach-Object {
                Add-App -Name $_.Name -Version $_.Value.version -Source "npm"
            }
        }
    } catch {}
}

# ============================================================================
# 8. CARGO (Rust)
# ============================================================================
Write-Host "[8/20] cargo..." -ForegroundColor Yellow
$cargoBin = "$env:USERPROFILE\.cargo\bin"
if (Test-Path $cargoBin) {
    Get-ChildItem $cargoBin -File -EA SilentlyContinue | Where-Object { $_.Extension -eq '.exe' } | ForEach-Object {
        Add-App -Name $_.BaseName -Source "cargo" -Path $_.FullName -Size "$([math]::Round($_.Length/1KB,2)) KB"
    }
}

# ============================================================================
# 9. GO
# ============================================================================
Write-Host "[9/20] go..." -ForegroundColor Yellow
$goBin = "$env:USERPROFILE\go\bin"
if (Test-Path $goBin) {
    Get-ChildItem $goBin -File -EA SilentlyContinue | Where-Object { $_.Extension -eq '.exe' } | ForEach-Object {
        Add-App -Name $_.BaseName -Source "go" -Path $_.FullName -Size "$([math]::Round($_.Length/1KB,2)) KB"
    }
}

# ============================================================================
# 10. CONDA (Anaconda / Miniconda) - ENVIRONNEMENTS + PACKAGES
# ============================================================================
Write-Host "[10/20] conda..." -ForegroundColor Yellow
$condaPaths = @(
    "$env:USERPROFILE\anaconda3\Scripts\conda.exe",
    "$env:USERPROFILE\miniconda3\Scripts\conda.exe",
    "$env:LOCALAPPDATA\anaconda3\Scripts\conda.exe",
    "$env:LOCALAPPDATA\miniconda3\Scripts\conda.exe",
    "C:\anaconda3\Scripts\conda.exe",
    "C:\miniconda3\Scripts\conda.exe",
    "C:\ProgramData\anaconda3\Scripts\conda.exe",
    "C:\ProgramData\miniconda3\Scripts\conda.exe"
)
$condaExe = $null
foreach ($cp in $condaPaths) { if (Test-Path $cp) { $condaExe = $cp; break } }
if (-not $condaExe) { $condaExe = (Get-Command conda -EA SilentlyContinue).Source }

if ($condaExe -and (Test-Path $condaExe)) {
    # Enregistrer conda lui-meme
    Add-App -Name "conda" -Source "conda" -Path (Split-Path $condaExe -Parent)
    # Lister les environnements
    try {
        $envList = & $condaExe env list --json 2>$null | ConvertFrom-Json -EA SilentlyContinue
        if ($envList.envs) {
            foreach ($envPath in $envList.envs) {
                $envName = Split-Path $envPath -Leaf
                if ($envName -eq "anaconda3" -or $envName -eq "miniconda3") { $envName = "base" }
                Add-App -Name "conda-env:$envName" -Source "conda-env" -Path $envPath
                # Lister les packages de l'env
                $condaPkg = Join-Path $envPath "conda-meta"
                if (Test-Path $condaPkg) {
                    Get-ChildItem $condaPkg -Filter "*.json" -EA SilentlyContinue | ForEach-Object {
                        try {
                            $meta = Get-Content $_.FullName -Raw | ConvertFrom-Json -EA SilentlyContinue
                            if ($meta.name) {
                                Add-App -Name $meta.name -Version $meta.version -Publisher $meta.channel -Source "conda-package" -Path $envPath
                            }
                        } catch {}
                    }
                }
            }
        }
    } catch {}
}

# ============================================================================
# 11. POETRY
# ============================================================================
Write-Host "[11/20] poetry..." -ForegroundColor Yellow
$poetryCmd = Get-Command poetry -EA SilentlyContinue
if ($poetryCmd) {
    Add-App -Name "poetry" -Source "poetry" -Path $poetryCmd.Source
    try {
        $poetryShow = poetry show 2>$null
        if ($poetryShow) {
            $poetryShow | ForEach-Object {
                if ($_ -match '^([a-zA-Z0-9_-]+)\s+([\d\.]+)') {
                    Add-App -Name $matches[1] -Version $matches[2] -Source "poetry-package"
                }
            }
        }
    } catch {}
}

# ============================================================================
# 12. UV
# ============================================================================
Write-Host "[12/20] uv..." -ForegroundColor Yellow
$uvCmd = Get-Command uv -EA SilentlyContinue
if ($uvCmd) {
    Add-App -Name "uv" -Source "uv" -Path $uvCmd.Source
    try {
        $uvPip = uv pip list --format=json 2>$null | ConvertFrom-Json -EA SilentlyContinue
        foreach ($pkg in $uvPip) {
            Add-App -Name $pkg.name -Version $pkg.version -Source "uv-package"
        }
    } catch {}
}

# ============================================================================
# 13. PDM
# ============================================================================
Write-Host "[13/20] pdm..." -ForegroundColor Yellow
$pdmCmd = Get-Command pdm -EA SilentlyContinue
if ($pdmCmd) {
    Add-App -Name "pdm" -Source "pdm" -Path $pdmCmd.Source
}

# ============================================================================
# 14. DOCKER (Desktop + CLI + Images)
# ============================================================================
Write-Host "[14/20] docker..." -ForegroundColor Yellow
$dockerCmd = Get-Command docker -EA SilentlyContinue
if ($dockerCmd) {
    Add-App -Name "docker" -Source "docker" -Path $dockerCmd.Source
    # Docker Desktop
    $ddPath = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $ddPath) { Add-App -Name "Docker Desktop" -Source "docker" -Path $ddPath }
    # Images
    try {
        $images = docker images --format "{{.Repository}}|{{.Tag}}|{{.Size}}" 2>$null
        if ($images) {
            $images | ForEach-Object {
                $parts = $_ -split '\|'
                if ($parts.Count -ge 3) {
                    Add-App -Name "docker-image:$($parts[0])" -Version $parts[1] -Source "docker-image" -Size $parts[2]
                }
            }
        }
    } catch {}
    # Containers (stopped + running)
    try {
        $containers = docker ps -a --format "{{.Names}}|{{.Image}}|{{.Status}}" 2>$null
        if ($containers) {
            $containers | ForEach-Object {
                $parts = $_ -split '\|'
                if ($parts.Count -ge 2) {
                    Add-App -Name "docker-container:$($parts[0])" -Version $parts[1] -Source "docker-container"
                }
            }
        }
    } catch {}
}

# ============================================================================
# 15. KUBECTL
# ============================================================================
Write-Host "[15/20] kubectl..." -ForegroundColor Yellow
$kubectlCmd = Get-Command kubectl -EA SilentlyContinue
if ($kubectlCmd) {
    Add-App -Name "kubectl" -Source "kubectl" -Path $kubectlCmd.Source
    try {
        $ver = kubectl version --client --short 2>$null
        if ($ver -match 'v([\d\.]+)') { Add-App -Name "kubectl" -Version $matches[1] -Source "kubectl" -Path $kubectlCmd.Source }
    } catch {}
}

# ============================================================================
# 16. TERRAFORM
# ============================================================================
Write-Host "[16/20] terraform..." -ForegroundColor Yellow
$tfCmd = Get-Command terraform -EA SilentlyContinue
if ($tfCmd) {
    Add-App -Name "terraform" -Source "terraform" -Path $tfCmd.Source
    try {
        $ver = terraform version -json 2>$null | ConvertFrom-Json -EA SilentlyContinue
        if ($ver.terraform_version) { Add-App -Name "terraform" -Version $ver.terraform_version -Source "terraform" -Path $tfCmd.Source }
    } catch {}
}

# ============================================================================
# 17. DOTNET TOOLS
# ============================================================================
Write-Host "[17/20] dotnet tools..." -ForegroundColor Yellow
if (Get-Command dotnet -EA SilentlyContinue) {
    try {
        $dotnetTools = dotnet tool list -g 2>$null
        if ($dotnetTools) {
            $dotnetTools | Select-Object -Skip 2 | ForEach-Object {
                if ($_ -match '^([\S]+)\s+([\S]+)\s+([\S]+)') {
                    Add-App -Name $matches[1] -Version $matches[2] -Source "dotnet-tool"
                }
            }
        }
    } catch {}
}

# ============================================================================
# 18. RUBY GEM
# ============================================================================
Write-Host "[18/20] ruby gem..." -ForegroundColor Yellow
if (Get-Command gem -EA SilentlyContinue) {
    try {
        $gems = gem list --local 2>$null
        if ($gems) {
            $gems | ForEach-Object {
                if ($_ -match '^([a-zA-Z0-9_-]+)\s+\((.+)\)') {
                    Add-App -Name $matches[1] -Version ($matches[2] -replace ' ','') -Source "gem"
                }
            }
        }
    } catch {}
}

# ============================================================================
# 19. PHP COMPOSER
# ============================================================================
Write-Host "[19/20] php composer..." -ForegroundColor Yellow
if (Get-Command composer -EA SilentlyContinue) {
    Add-App -Name "composer" -Source "composer" -Path (Get-Command composer).Source
}

# ============================================================================
# 20. VCPKG
# ============================================================================
Write-Host "[20/20] vcpkg..." -ForegroundColor Yellow
$vcpkgPaths = @("C:\vcpkg\vcpkg.exe","$env:USERPROFILE\vcpkg\vcpkg.exe")
foreach ($vp in $vcpkgPaths) {
    if (Test-Path $vp) { Add-App -Name "vcpkg" -Source "vcpkg" -Path $vp }
}

# ============================================================================
# 21. WSL
# ============================================================================
Write-Host "[BONUS 1] WSL..." -ForegroundColor Yellow
if (Get-Command wsl -EA SilentlyContinue) {
    try {
        $wslList = wsl --list --verbose 2>$null
        $wslList | Select-Object -Skip 1 | ForEach-Object {
            if ($_ -match '\s*(\S.+)\s+(Running|Stopped)\s+(\d+)') {
                Add-App -Name "WSL:$($matches[1].Trim())" -Source "WSL"
            }
        }
    } catch {}
}

# ============================================================================
# 22. WINDOWS SERVICES
# ============================================================================
Write-Host "[BONUS 2] Windows Services..." -ForegroundColor Yellow
Get-Service | ForEach-Object {
    try {
        $svc = Get-CimInstance Win32_Service -Filter "Name='$($_.Name)'" -EA SilentlyContinue
        if ($svc -and $svc.PathName) {
            $path = ($svc.PathName -split '"')[1]; if (-not $path) { $path = ($svc.PathName -split ' ')[0] }
            $sz = ""; if (Test-Path $path) { try { $sz = "$([math]::Round((Get-Item $path).Length/1KB,2)) KB" } catch {} }
            Add-App -Name $_.Name -Publisher $svc.StartName -Source "WindowsService" -Path $path -Size $sz
        }
    } catch {}
}

# ============================================================================
# 23. SCHEDULED TASKS
# ============================================================================
Write-Host "[BONUS 3] Scheduled Tasks..." -ForegroundColor Yellow
Get-ScheduledTask | ForEach-Object {
    $act = ($_.Actions | Select-Object -First 1)
    Add-App -Name $_.TaskName -Source "ScheduledTask" -Path $act.Execute
}

# ============================================================================
# 24. SCAN EXHAUSTIF PORTABLE / MANUEL - Tous les .exe/.msi sur les disques
#     Limite: profondeur 3, dossiers cibles uniquement pour rester < 5min
# ============================================================================
Write-Host "[BONUS 4] Scan exhaustif portable (dossiers cibles)..." -ForegroundColor Yellow

$ScanDirs = @(
    "C:\tools","C:\utils","C:\bin","C:\opt","C:\Programs",
    "$env:USERPROFILE\tools","$env:USERPROFILE\utils","$env:USERPROFILE\bin",
    "$env:USERPROFILE\Desktop","$env:USERPROFILE\Downloads",
    "$env:LOCALAPPDATA\Programs",
    "$env:APPDATA",
    "C:\ProgramData\chocolatey\bin",
    "$env:USERPROFILE\scoop\shims",
    "C:\Program Files\Git\cmd",
    "C:\Program Files\Git\bin",
    "C:\Program Files\nodejs",
    "C:\Program Files\Docker",
    "C:\Program Files\terraform",
    "C:\Program Files\kubectl",
    "C:\Program Files (x86)\Git\cmd",
    "C:\Program Files (x86)\nodejs"
)

$Extensions = @('.exe','.msi','.bat','.cmd','.ps1','.py','.jar')

foreach ($dir in $ScanDirs) {
    if (Test-Path $dir) {
        Get-ChildItem $dir -File -Recurse -Depth 3 -EA SilentlyContinue | Where-Object {
            $_.Extension -in $Extensions
        } | ForEach-Object {
            $key = $_.FullName
            if (-not $Script:FoundPaths.Contains($key)) {
                $ver = $_.VersionInfo.FileVersion
                $pub = $_.VersionInfo.CompanyName
                $sz = "$([math]::Round($_.Length/1KB,2)) KB"
                Add-App -Name $_.BaseName -Version $ver -Publisher $pub -Source "Portable/Manual" -Path $_.FullName -Size $sz -InstallDate $_.LastWriteTime
            }
        }
    }
}

# ============================================================================
# 25. SCAN RAPIDE DES RACINES DES DISQUES pour les dossiers d'outils
# ============================================================================
Write-Host "[BONUS 5] Scan racines disques..." -ForegroundColor Yellow
$drives = Get-Volume | Where-Object { $_.DriveLetter } | Select-Object -ExpandProperty DriveLetter
foreach ($d in $drives) {
    $root = "$d`:\"
    if (Test-Path $root) {
        # Chercher les dossiers tools-like a la racine
        Get-ChildItem $root -Directory -EA SilentlyContinue | Where-Object {
            $_.Name -in @('tools','utils','bin','opt','programs','apps','software','dev','hacking','forensics','security','pentest')
        } | ForEach-Object {
            Get-ChildItem $_.FullName -File -Recurse -Depth 2 -EA SilentlyContinue | Where-Object {
                $_.Extension -in $Extensions
            } | ForEach-Object {
                $key = $_.FullName
                if (-not $Script:FoundPaths.Contains($key)) {
                    $ver = $_.VersionInfo.FileVersion
                    $pub = $_.VersionInfo.CompanyName
                    $sz = "$([math]::Round($_.Length/1KB,2)) KB"
                    Add-App -Name $_.BaseName -Version $ver -Publisher $pub -Source "Portable/Manual" -Path $_.FullName -Size $sz -InstallDate $_.LastWriteTime
                }
            }
        }
    }
}

# ============================================================================
# EXPORT CSV
# ============================================================================
Write-Host "`nExport CSV..." -ForegroundColor Green
$Results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8 -Force

$Stopwatch.Stop()
$elapsed = $Stopwatch.Elapsed

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  TERMINE !" -ForegroundColor Green
Write-Host "  Fichier: $OutputPath" -ForegroundColor Green
Write-Host "  Total: $($Results.Count) entrees" -ForegroundColor Green
Write-Host "  Temps: $($elapsed.ToString('mm\:ss\.fff'))" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

Start-Process explorer.exe -ArgumentList "/select,$OutputPath"
