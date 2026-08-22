#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Audit Système — PHASE 2 : Software, Dev Environments & Forensics
.DESCRIPTION
    Couvre : Applications installées (Registry), Package Managers (Winget,
    Choco, Scoop), Store Apps, PowerShell Modules, Environnements de
    développement (120+ outils), Services, Tâches planifiées, Comptes locaux,
    TOUS les processus, Event Logs 24h, Fichiers temporaires (scan complet),
    Variables d'environnement, Fichier HOSTS.
    Génère : Audit_Phase2_Software_Dev_Forensics.txt sur le Bureau.
.NOTES
    Version : 1.0.0-MILITARY-PHASE2
    Temps estimé : 1-5 minutes (dépend fortement des outils installés)
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'Continue'

$ReportPath = Join-Path $env:USERPROFILE 'Desktop\Audit_Phase2_Software_Dev_Forensics.txt'
$sb         = [System.Text.StringBuilder]::new()
$errLog     = [System.Text.StringBuilder]::new()
$sectionTimes = [System.Collections.Generic.List[PSCustomObject]]::new()
$scriptStart  = Get-Date

# ─── FONCTIONS ─────────────────────────────────────────────────────────────────

function Invoke-AuditSection {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Number, [Parameter(Mandatory)][scriptblock]$Code)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Progress -Activity 'Audit Phase 2 — Software, Dev & Forensics' -Status "$Number — $Name" -PercentComplete -1
    try {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('─' * 80)
        [void]$sb.AppendLine("## [$Number] $Name")
        [void]$sb.AppendLine('─' * 80)
        & $Code
        $status = 'OK'
    }
    catch {
        $status = "ERREUR : $($_.Exception.Message)"
        [void]$errLog.AppendLine("[$Number — $Name] $($_.Exception.GetType().Name) : $($_.Exception.Message)")
    }
    finally {
        $sw.Stop()
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine("[STATUS] $status | Durée : $($sw.Elapsed.TotalSeconds.ToString('F2'))s")
        [void]$sectionTimes.Add([PSCustomObject]@{ Section=$Name; Number=$Number; Duration=$sw.Elapsed; Status=$status })
    }
}

function Fmt-Table  { param([Parameter(ValueFromPipeline)]$obj) process { $obj | Format-Table -AutoSize | Out-String -Width 4096 } }
function Fmt-List   { param([Parameter(ValueFromPipeline)]$obj) process { $obj | Format-List   | Out-String -Width 4096 } }

function Test-DevEnv {
    param([string]$Name, [string]$Command, [string]$Argument='--version', [switch]$UseStdErr)
    try {
        $cmd = Get-Command $Command -EA SilentlyContinue
        if (-not $cmd) { return [PSCustomObject]@{ Outil=$Name; Statut='NON TROUVÉ'; Version='N/A'; Chemin='N/A' } }
        if ($UseStdErr) { $ver = & $Command $Argument 2>&1 | Select-Object -First 1 }
        else { $ver = & $Command $Argument 2>$null | Select-Object -First 1 }
        return [PSCustomObject]@{ Outil=$Name; Statut='INSTALLÉ'; Version="$ver".Trim(); Chemin=$cmd.Source }
    }
    catch { return [PSCustomObject]@{ Outil=$Name; Statut='ERREUR'; Version=$_.Exception.Message; Chemin='N/A' } }
}

function Get-ProcOwner {
    param([int]$Pid)
    try {
        $p = Get-CimInstance Win32_Process -Filter "ProcessId=$Pid" -EA SilentlyContinue
        if ($p) { $o = Invoke-CimMethod -InputObject $p -MethodName GetOwner -EA SilentlyContinue; if ($o.Domain -and $o.User) { return "$($o.Domain)\$($o.User)" } }
    } catch {}
    return 'N/A'
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ─── HEADER ────────────────────────────────────────────────────────────────────

[void]$sb.AppendLine('╔' + ('═'*78) + '╗')
[void]$sb.AppendLine('║' + (' '*8) + 'AUDIT PHASE 2 — SOFTWARE, DEV & FORENSICS' + (' '*9) + '║')
[void]$sb.AppendLine('╠' + ('═'*78) + '╣')
[void]$sb.AppendLine('║  PowerShell 7.x | Military Grade | Phase 2/2' + (' '*35) + '║')
[void]$sb.AppendLine('╚' + ('═'*78) + '╝')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("Timestamp : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$sb.AppendLine("Machine   : $env:COMPUTERNAME | User: $env:USERNAME | Admin: $(if($isAdmin){'✓'}else{'✗'})")
[void]$sb.AppendLine("PSVersion : $($PSVersionTable.PSVersion)")
[void]$sb.AppendLine('')


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 14 — SOFTWARE: REGISTRY INSTALLED APPS (DÉDUPLICATION HASHTABLE)
# ═══════════════════════════════════════════════════════════════════════════════

Invoke-AuditSection -Name 'SOFTWARE — APPLICATIONS INSTALLÉES (REGISTRE)' -Number '14' -Code {
    [void]$sb.AppendLine("### Applications depuis le Registre (déduplication O(1) via Hashtable)")
    $seen = @{}
    $apps = [System.Collections.Generic.List[PSCustomObject]]::new()
    $regPaths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($rp in $regPaths) {
        try {
            $items = Get-ItemProperty -Path $rp -EA SilentlyContinue | Where-Object { $_.DisplayName }
            foreach ($item in $items) {
                $key = "$($item.DisplayName)|$($item.DisplayVersion)"
                if (-not $seen.ContainsKey($key)) {
                    $seen[$key] = $true
                    $src = if ($rp -match 'WOW6432Node') { 'HKLM-x86' } elseif ($rp -match 'HKCU') { 'HKCU' } else { 'HKLM-x64' }
                    $apps.Add([PSCustomObject]@{ Nom=$item.DisplayName; Version=$item.DisplayVersion; Éditeur=$item.Publisher; InstallDate=$item.InstallDate; Emplacement=$item.InstallLocation; Source=$src })
                }
            }
        } catch {}
    }
    [void]$sb.AppendLine("Nombre total d'applications uniques : $($apps.Count)")
    $apps | Sort-Object Nom | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 15 — SOFTWARE: PACKAGE MANAGERS (SANS TIMEOUT)
# ═══════════════════════════════════════════════════════════════════════════════

Invoke-AuditSection -Name 'SOFTWARE — GESTIONNAIRES DE PAQUETS' -Number '15' -Code {
    [void]$sb.AppendLine("### Winget")
    try {
        $wc = Get-Command winget -EA SilentlyContinue
        if ($wc) {
            [void]$sb.AppendLine("Chemin : $($wc.Source)")
            [void]$sb.AppendLine((winget list --accept-source-agreements 2>$null))
        } else { [void]$sb.AppendLine("Winget non trouvé dans PATH.") }
    } catch { [void]$sb.AppendLine("Erreur Winget : $($_.Exception.Message)") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Chocolatey")
    try {
        $cc = Get-Command choco -EA SilentlyContinue
        if ($cc) {
            [void]$sb.AppendLine("Chemin : $($cc.Source)")
            [void]$sb.AppendLine((choco list -lo 2>$null))
        } else { [void]$sb.AppendLine("Chocolatey non trouvé.") }
    } catch { [void]$sb.AppendLine("Erreur Chocolatey : $($_.Exception.Message)") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Scoop")
    try {
        $sc = Get-Command scoop -EA SilentlyContinue
        if ($sc) {
            [void]$sb.AppendLine("Chemin : $($sc.Source)")
            [void]$sb.AppendLine((scoop list 2>$null))
        } else { [void]$sb.AppendLine("Scoop non trouvé.") }
    } catch { [void]$sb.AppendLine("Erreur Scoop : $($_.Exception.Message)") }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 16 — SOFTWARE: STORE APPS & POWERSHELL MODULES
# ═══════════════════════════════════════════════════════════════════════════════

Invoke-AuditSection -Name 'SOFTWARE — STORE APPS & PS MODULES' -Number '16' -Code {
    [void]$sb.AppendLine("### Applications Microsoft Store (Appx)")
    try {
        if ($isAdmin) { $store = Get-AppxPackage -AllUsers -EA SilentlyContinue }
        else { $store = Get-AppxPackage -EA SilentlyContinue }
        [void]$sb.AppendLine("Nombre : $($store.Count)")
        $store | Select-Object Name, PackageFullName, Version, Publisher, InstallLocation | Sort-Object Name | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) }
    } catch { [void]$sb.AppendLine("Get-AppxPackage indisponible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Modules PowerShell Installés (PowerShellGet)")
    try {
        $mod = Get-InstalledModule -EA SilentlyContinue
        if ($mod) { $mod | Select-Object Name, Version, Repository, PublishedDate | Sort-Object Name | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) } }
        else { [void]$sb.AppendLine("Aucun module installé via PowerShellGet.") }
    } catch { [void]$sb.AppendLine("Get-InstalledModule indisponible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Tous les modules disponibles (Get-Module -ListAvailable)")
    try {
        $all = Get-Module -ListAvailable -EA SilentlyContinue | Select-Object Name, Version, ModuleBase, Author | Sort-Object Name -Unique
        [void]$sb.AppendLine("Nombre total : $($all.Count)")
        $all | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) }
    } catch { [void]$sb.AppendLine("Get-Module indisponible.") }
}


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 17 — SOFTWARE: ENVIRONNEMENTS DE DÉVELOPPEMENT (120+ OUTILS)
# ═══════════════════════════════════════════════════════════════════════════════

Invoke-AuditSection -Name 'SOFTWARE — ENVIRONNEMENTS DE DÉVELOPPEMENT' -Number '17' -Code {
    [void]$sb.AppendLine("### Scan de 120+ outils de développement")
    $tools = @(
        @{N='Python';C='python';A='--version'},@{N='Python3';C='python3';A='--version'},@{N='Pip';C='pip';A='--version'},
        @{N='Node.js';C='node';A='--version'},@{N='NPM';C='npm';A='--version'},@{N='NPX';C='npx';A='--version'},
        @{N='Yarn';C='yarn';A='--version'},@{N='PNPM';C='pnpm';A='--version'},@{N='Bun';C='bun';A='--version'},
        @{N='Deno';C='deno';A='--version'},@{N='Git';C='git';A='--version'},@{N='Git LFS';C='git-lfs';A='version'},
        @{N='GitHub CLI';C='gh';A='--version'},@{N='GitLab CLI';C='glab';A='--version'},@{N='Go';C='go';A='version'},
        @{N='Rust (rustc)';C='rustc';A='--version'},@{N='Cargo';C='cargo';A='--version'},@{N='Rustup';C='rustup';A='--version'},
        @{N='Java';C='java';A='-version';SE=$true},@{N='Javac';C='javac';A='-version'},@{N='Dotnet';C='dotnet';A='--version'},
        @{N='Docker';C='docker';A='--version'},@{N='Docker Compose';C='docker-compose';A='--version'},@{N='WSL';C='wsl';A='--version'},
        @{N='Conda';C='conda';A='--version'},@{N='Mamba';C='mamba';A='--version'},@{N='Ruby';C='ruby';A='--version'},
        @{N='Gem';C='gem';A='--version'},@{N='Bundler';C='bundle';A='--version'},@{N='PHP';C='php';A='--version'},
        @{N='Composer';C='composer';A='--version'},@{N='Perl';C='perl';A='--version'},@{N='CPAN';C='cpan';A='--version'},
        @{N='R';C='Rscript';A='--version';SE=$true},@{N='Julia';C='julia';A='--version'},
        @{N='Kotlin';C='kotlin';A='-version';SE=$true},@{N='Scala';C='scala';A='--version';SE=$true},@{N='SBT';C='sbt';A='sbtVersion'},
        @{N='Clojure';C='clojure';A='-version'},@{N='Leiningen';C='lein';A='version'},@{N='Elixir';C='elixir';A='--version'},
        @{N='Erlang';C='erl';A='+V'},@{N='Haskell (GHC)';C='ghc';A='--version'},@{N='Cabal';C='cabal';A='--version'},
        @{N='Stack';C='stack';A='--version'},@{N='OCaml';C='ocaml';A='-version'},@{N='Opam';C='opam';A='--version'},
        @{N='Swift';C='swift';A='--version'},@{N='Zig';C='zig';A='version'},@{N='Nim';C='nim';A='--version'},
        @{N='Crystal';C='crystal';A='--version'},@{N='V';C='v';A='version'},@{N='Cmake';C='cmake';A='--version'},
        @{N='Make';C='make';A='--version'},@{N='Ninja';C='ninja';A='--version'},@{N='MSBuild';C='msbuild';A='-version'},
        @{N='VSWhere';C='vswhere';A='-version'},@{N='VS Code';C='code';A='--version'},@{N='VS Code Insiders';C='code-insiders';A='--version'},
        @{N='Flutter';C='flutter';A='--version'},@{N='Dart';C='dart';A='--version'},@{N='TypeScript';C='tsc';A='--version'},
        @{N='ESLint';C='eslint';A='--version'},@{N='Prettier';C='prettier';A='--version'},@{N='Webpack';C='webpack';A='--version'},
        @{N='Vite';C='vite';A='--version'},@{N='Next.js';C='next';A='--version'},@{N='Vue CLI';C='vue';A='--version'},
        @{N='Angular CLI';C='ng';A='version'},@{N='React Native';C='react-native';A='--version'},@{N='Expo';C='expo';A='--version'},
        @{N='Ionic';C='ionic';A='--version'},@{N='Electron';C='electron';A='--version'},@{N='Tauri';C='tauri';A='--version'},
        @{N='Poetry';C='poetry';A='--version'},@{N='Pipenv';C='pipenv';A='--version'},@{N='Virtualenv';C='virtualenv';A='--version'},
        @{N='Pyenv';C='pyenv';A='--version'},@{N='Rbenv';C='rbenv';A='--version'},@{N='RVM';C='rvm';A='--version'},
        @{N='NVM';C='nvm';A='--version'},@{N='FNM';C='fnm';A='--version'},@{N='JEnv';C='jenv';A='version'},
        @{N='SDKMAN';C='sdk';A='version'},@{N='Homebrew';C='brew';A='--version'},@{N='Chocolatey';C='choco';A='--version'},
        @{N='Scoop';C='scoop';A='--version'},@{N='Winget';C='winget';A='--version'},@{N='MSYS2';C='msys2';A='--version'},
        @{N='Cygwin';C='cygwin';A='--version'},@{N='MinGW';C='mingw32-make';A='--version'},@{N='LLVM/Clang';C='clang';A='--version'},
        @{N='GCC';C='gcc';A='--version'},@{N='G++';C='g++';A='--version'},@{N='NASM';C='nasm';A='-v'},
        @{N='GDB';C='gdb';A='--version'},@{N='LLDB';C='lldb';A='--version'},@{N='QEMU';C='qemu';A='--version'},
        @{N='VirtualBox';C='vboxmanage';A='--version'},@{N='VMware';C='vmrun';A='--version'},@{N='Hyper-V';C='vmcompute';A='--version'},
        @{N='Docker Desktop';C='docker-desktop';A='--version'},@{N='Rancher Desktop';C='rancher-desktop';A='--version'},
        @{N='Colima';C='colima';A='--version'},@{N='Podman';C='podman';A='--version'},@{N='Buildah';C='buildah';A='--version'},
        @{N='Skopeo';C='skopeo';A='--version'},@{N='containerd';C='containerd';A='--version'},@{N='runc';C='runc';A='--version'},
        @{N='NVIDIA SMI';C='nvidia-smi';A='--version'},@{N='CUDA (nvcc)';C='nvcc';A='--version'},@{N='ROCm Info';C='rocminfo';A='--version'},
        @{N='OpenCL Info';C='clinfo';A='--version'},@{N='AWS CLI';C='aws';A='--version'},@{N='Azure CLI';C='az';A='--version'},
        @{N='Google Cloud';C='gcloud';A='--version'},@{N='Terraform';C='terraform';A='--version'},@{N='Packer';C='packer';A='--version'},
        @{N='Ansible';C='ansible';A='--version'},@{N='Vagrant';C='vagrant';A='--version'},@{N='Kubernetes';C='kubectl';A='version --client'},
        @{N='Helm';C='helm';A='version'},@{N='Minikube';C='minikube';A='version'},@{N='Kind';C='kind';A='version'},
        @{N='OpenSSL';C='openssl';A='version'},@{N='OpenSSH';C='ssh';A='-V';SE=$true},@{N='PuTTY';C='plink';A='-V'},
        @{N='7-Zip';C='7z';A='--help'},@{N='NuGet';C='nuget';A='help'},@{N='Paket';C='paket';A='--version'},
        @{N='Gradle';C='gradle';A='--version'},@{N='Maven';C='mvn';A='-version'},@{N='Ant';C='ant';A='-version'},
        @{N='Meson';C='meson';A='--version'},@{N='Bazel';C='bazel';A='--version'},@{N='Buck';C='buck';A='--version'},
        @{N='Pants';C='pants';A='--version'},@{N='Please';C='plz';A='--version'},@{N='Nix';C='nix';A='--version'},
        @{N='Guix';C='guix';A='--version'},@{N='Spack';C='spack';A='--version'},@{N='EasyBuild';C='eb';A='--version'},
        @{N='Lmod';C='lmod';A='--version'},@{N='Direnv';C='direnv';A='--version'},@{N='ASDF';C='asdf';A='--version'},
        @{N='Mise';C='mise';A='--version'},@{N='Proto';C='proto';A='--version'},@{N='Volta';C='volta';A='--version'},
        @{N='N';C='n';A='--version'},@{N='Nave';C='nave';A='--version'},@{N='Nvm-windows';C='nvm';A='--version'},
        @{N='Nvs';C='nvs';A='--version'},@{N='Nodist';C='nodist';A='--version'}
    )

    $results = foreach ($t in $tools) {
        $se = if ($t.ContainsKey('SE')) { $t.SE } else { $false }
        Test-DevEnv -Name $t.N -Command $t.C -Argument $t.A -UseStdErr:$se
    }

    $found = $results | Where-Object { $_.Statut -eq 'INSTALLÉ' }
    [void]$sb.AppendLine("Trouvés : $($found.Count) / $($results.Count)")
    [void]$sb.AppendLine('')
    $found | Sort-Object Outil | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Détails Python (pip list)")
    try {
        $pl = pip list --format=freeze 2>$null
        if ($pl) {
            [void]$sb.AppendLine("Packages : $($pl.Count)")
            $pl | Select-Object -First 50 | ForEach-Object { [void]$sb.AppendLine("  → $_") }
            if ($pl.Count -gt 50) { [void]$sb.AppendLine("  ... et $($pl.Count - 50) autres") }
        }
    } catch { [void]$sb.AppendLine("pip list indisponible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Détails Node.js (npm list -g)")
    try { $nl = npm list -g --depth=0 2>$null; if ($nl) { [void]$sb.AppendLine($nl) } } catch { [void]$sb.AppendLine("npm list indisponible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Détails Rust (cargo install --list)")
    try { $ci = cargo install --list 2>$null; if ($ci) { [void]$sb.AppendLine($ci) } } catch { [void]$sb.AppendLine("cargo install --list indisponible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Détails Conda (env list)")
    try { $ce = conda env list 2>$null; if ($ce) { [void]$sb.AppendLine($ce) } } catch { [void]$sb.AppendLine("conda env list indisponible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Détails Go (go env)")
    try { $ge = go env 2>$null; if ($ge) { [void]$sb.AppendLine($ge) } } catch { [void]$sb.AppendLine("go env indisponible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Détails Docker (containers en cours)")
    try { $dp = docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>$null; if ($dp) { [void]$sb.AppendLine($dp) } else { [void]$sb.AppendLine("Aucun container en cours.") } } catch { [void]$sb.AppendLine("docker ps indisponible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Détails WSL (distros)")
    try { $wl = wsl -l -v 2>$null; if ($wl) { [void]$sb.AppendLine($wl) } else { [void]$sb.AppendLine("Aucune distribution WSL.") } } catch { [void]$sb.AppendLine("wsl -l -v indisponible.") }
}


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 18 — SYSTEM STATE: SERVICES WINDOWS
# ═══════════════════════════════════════════════════════════════════════════════

Invoke-AuditSection -Name 'SYSTEM STATE — SERVICES WINDOWS' -Number '18' -Code {
    [void]$sb.AppendLine("### Tous les services")
    $svc = Get-CimInstance Win32_Service -EA SilentlyContinue | Select-Object Name, DisplayName, State, StartMode, PathName, StartName, ProcessId | Sort-Object State, Name
    [void]$sb.AppendLine("Nombre total : $($svc.Count)")
    $svc | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Services tiers actifs (hors C:\\Windows)")
    $third = $svc | Where-Object { $_.PathName -and $_.PathName -notmatch '^"?C:\\Windows' -and $_.State -eq 'Running' }
    if ($third) { $third | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) } }
    else { [void]$sb.AppendLine("Aucun service tiers en cours d'exécution.") }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 19 — SYSTEM STATE: TÂCHES PLANIFIÉES
# ═══════════════════════════════════════════════════════════════════════════════

Invoke-AuditSection -Name 'SYSTEM STATE — TÂCHES PLANIFIÉES' -Number '19' -Code {
    try {
        $tasks = Get-ScheduledTask -EA SilentlyContinue
        [void]$sb.AppendLine("Nombre total de tâches : $($tasks.Count)")
        foreach ($t in $tasks) {
            [void]$sb.AppendLine("---")
            [void]$sb.AppendLine("Nom         : $($t.TaskName)")
            [void]$sb.AppendLine("Chemin      : $($t.TaskPath)")
            [void]$sb.AppendLine("État        : $($t.State)")
            [void]$sb.AppendLine("Auteur      : $($t.Author)")
            [void]$sb.AppendLine("Description : $($t.Description)")
            if ($t.Triggers) { foreach ($tr in $t.Triggers) { [void]$sb.AppendLine("  Trigger → $($tr.CimClass.CimClassName) | Enabled: $($tr.Enabled)") } }
            if ($t.Actions) { foreach ($a in $t.Actions) { [void]$sb.AppendLine("  Action  → $($a.Execute) $($a.Arguments)") } }
            try {
                $info = Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath $t.TaskPath -EA SilentlyContinue
                if ($info) {
                    [void]$sb.AppendLine("LastRunTime    : $($info.LastRunTime)")
                    [void]$sb.AppendLine("NextRunTime    : $($info.NextRunTime)")
                    [void]$sb.AppendLine("LastResult     : $($info.LastTaskResult)")
                    [void]$sb.AppendLine("MissedRuns     : $($info.NumberOfMissedRuns)")
                }
            } catch {}
        }
    } catch { [void]$sb.AppendLine("Get-ScheduledTask indisponible.") }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 20 — SYSTEM STATE: COMPTES & GROUPES LOCAUX
# ═══════════════════════════════════════════════════════════════════════════════

Invoke-AuditSection -Name 'SYSTEM STATE — COMPTES & GROUPES LOCAUX' -Number '20' -Code {
    [void]$sb.AppendLine("### Comptes Utilisateurs Locaux")
    try {
        Get-LocalUser -EA SilentlyContinue | Select-Object Name, Enabled, PasswordRequired, PasswordLastSet, PasswordExpires, LastLogon, SID | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) }
    } catch { [void]$sb.AppendLine("Get-LocalUser indisponible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Membres du groupe Administrateurs")
    try {
        Get-LocalGroupMember -Group 'Administrators' -EA SilentlyContinue | Select-Object Name, PrincipalSource, ObjectClass, SID | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) }
    } catch { [void]$sb.AppendLine("Get-LocalGroupMember indisponible.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Groupes locaux")
    try {
        foreach ($g in (Get-LocalGroup -EA SilentlyContinue)) {
            [void]$sb.AppendLine("---")
            [void]$sb.AppendLine("Groupe : $($g.Name) | $($g.Description)")
            try {
                $m = Get-LocalGroupMember -Group $g.Name -EA SilentlyContinue
                [void]$sb.AppendLine("Membres : $($m.Count)")
                foreach ($x in $m) { [void]$sb.AppendLine("  → $($x.Name) ($($x.PrincipalSource))") }
            } catch { [void]$sb.AppendLine("  → Accès refusé") }
        }
    } catch { [void]$sb.AppendLine("Get-LocalGroup indisponible.") }
}



# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 21 — SYSTEM STATE: TOUS LES PROCESSUS (RAPIDE)
# ═══════════════════════════════════════════════════════════════════════════════

Invoke-AuditSection -Name 'SYSTEM STATE — TOUS LES PROCESSUS' -Number '21' -Code {
    $procs = Get-Process -EA SilentlyContinue
    [void]$sb.AppendLine("Nombre total : $($procs.Count)")
    $detail = foreach ($p in $procs) {
        $owner = Get-ProcOwner -Pid $p.Id
        $ram = [math]::Round($p.WorkingSet64 / 1MB, 2)
        $path = if ($p.Path) { $p.Path } else { 'N/A' }
        [PSCustomObject]@{ PID=$p.Id; Name=$p.ProcessName; Path=$path; Owner=$owner; 'RAM(MB)'=$ram; Threads=$p.Threads.Count; Handles=$p.HandleCount; Company=$p.Company; FileVersion=$p.FileVersion }
    }
    $detail | Sort-Object 'RAM(MB)' -Descending | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 22 — SYSTEM STATE: EVENT LOGS 24H (RAPIDE)
# ═══════════════════════════════════════════════════════════════════════════════

Invoke-AuditSection -Name 'SYSTEM STATE — JOURNAUX D''ÉVÉNEMENTS (24H)' -Number '22' -Code {
    $start = (Get-Date).AddHours(-24)
    try {
        $sys = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2,3; StartTime=$start} -MaxEvents 20 -EA SilentlyContinue
        if ($sys) { [void]$sb.AppendLine("### Système (max 20)"); $sys | Select-Object TimeCreated, Id, LevelDisplayName, ProviderName | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) } }
        else { [void]$sb.AppendLine("Aucun événement système critique (24h).") }
    } catch { [void]$sb.AppendLine("Get-WinEvent (System) indisponible.") }

    try {
        $app = Get-WinEvent -FilterHashtable @{LogName='Application'; Level=1,2,3; StartTime=$start} -MaxEvents 20 -EA SilentlyContinue
        if ($app) { [void]$sb.AppendLine("### Application (max 20)"); $app | Select-Object TimeCreated, Id, LevelDisplayName, ProviderName | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) } }
        else { [void]$sb.AppendLine("Aucun événement application critique (24h).") }
    } catch { [void]$sb.AppendLine("Get-WinEvent (Application) indisponible.") }

    try {
        $sec = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4624,4625,4634,4647,4648,4672; StartTime=$start} -MaxEvents 20 -EA SilentlyContinue
        if ($sec) { [void]$sb.AppendLine("### Sécurité (max 20)"); $sec | Select-Object TimeCreated, Id, LevelDisplayName, ProviderName | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) } }
        else { [void]$sb.AppendLine("Aucun événement sécurité (24h) ou journal inaccessible.") }
    } catch { [void]$sb.AppendLine("Get-WinEvent (Security) indisponible.") }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 23 — SYSTEM STATE: FICHIERS TEMPORAIRES (RAPIDE — MINIMUM)
# ═══════════════════════════════════════════════════════════════════════════════

Invoke-AuditSection -Name 'SYSTEM STATE — FICHIERS TEMPORAIRES (RAPIDE)' -Number '23' -Code {
    $paths = @()
    if ($env:TEMP) { $paths += $env:TEMP }
    if ($env:TMP)  { $paths += $env:TMP }
    if ($env:SystemRoot) { $paths += (Join-Path $env:SystemRoot 'Temp') }
    $paths = $paths | Select-Object -Unique | Where-Object { Test-Path $_ }
    foreach ($tp in $paths) {
        [void]$sb.AppendLine("--- $tp")
        try {
            $items = Get-ChildItem -Path $tp -Force -EA SilentlyContinue
            $files = $items | Where-Object { -not $_.PSIsContainer }
            $dirs  = $items | Where-Object { $_.PSIsContainer }
            $size = ($files | Measure-Object -Property Length -Sum).Sum
            $sizeMB = if ($size) { [math]::Round($size / 1MB, 2) } else { 0 }
            [void]$sb.AppendLine("  Fichiers: $($files.Count) | Dossiers: $($dirs.Count) | Taille: $sizeMB MB")
        } catch { [void]$sb.AppendLine("  ERREUR: $($_.Exception.Message)") }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 24 — SYSTEM STATE: ENVIRONNEMENT & PATH
# ═══════════════════════════════════════════════════════════════════════════════

Invoke-AuditSection -Name 'SYSTEM STATE — ENVIRONNEMENT & PATH' -Number '24' -Code {
    [void]$sb.AppendLine("### Variables Système")
    ([Environment]::GetEnvironmentVariables('Machine')).GetEnumerator() | Sort-Object Key | ForEach-Object { [void]$sb.AppendLine("$($_.Key) = $($_.Value)") }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Variables Utilisateur")
    ([Environment]::GetEnvironmentVariables('User')).GetEnumerator() | Sort-Object Key | ForEach-Object { [void]$sb.AppendLine("$($_.Key) = $($_.Value)") }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### PATH Décomposé")
    ($env:Path -split ';') | Where-Object { $_ } | Sort-Object | ForEach-Object { [void]$sb.AppendLine("  → $_") }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Démarrage (Startup)")
    @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup") | ForEach-Object {
        [void]$sb.AppendLine("--- $_")
        if (Test-Path $_) { Get-ChildItem $_ -Force -EA SilentlyContinue | ForEach-Object { [void]$sb.AppendLine("  → $($_.Name)") } }
        else { [void]$sb.AppendLine("  Chemin inexistant.") }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 25 — FORENSICS: FICHIER HOSTS & MOUNT POINTS
# ═══════════════════════════════════════════════════════════════════════════════

Invoke-AuditSection -Name 'FORENSICS — HOSTS & MOUNT POINTS' -Number '25' -Code {
    [void]$sb.AppendLine("### Fichier HOSTS")
    $hp = "$env:SystemRoot\System32\drivers\etc\hosts"
    if (Test-Path $hp) {
        $lines = Get-Content $hp -EA SilentlyContinue | Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne '' }
        [void]$sb.AppendLine("Entrées actives : $($lines.Count)")
        foreach ($l in $lines) { [void]$sb.AppendLine("  → $l") }
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("### Contenu brut")
        Get-Content $hp -EA SilentlyContinue | ForEach-Object { [void]$sb.AppendLine("  $_") }
    } else { [void]$sb.AppendLine("Fichier HOSTS introuvable.") }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Points de montage / Junctions")
    @('C:\Users','C:\ProgramData','C:\Program Files','C:\Program Files (x86)','C:\Windows') | ForEach-Object {
        try {
            $item = Get-Item $_ -EA SilentlyContinue
            if ($item.Target) { [void]$sb.AppendLine("$_ → $($item.Target)") }
        } catch {}
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# FINALISATION PHASE 2
# ═══════════════════════════════════════════════════════════════════════════════

$scriptEnd = Get-Date
$total = $scriptEnd - $scriptStart

[void]$sb.AppendLine('')
[void]$sb.AppendLine('╔' + ('═'*78) + '╗')
[void]$sb.AppendLine('║' + (' '*24) + 'RAPPORT PHASE 2' + (' '*39) + '║')
[void]$sb.AppendLine('╠' + ('═'*78) + '╣')

[void]$sb.AppendLine('')
[void]$sb.AppendLine("### RÉSUMÉ DES ERREURS")
if ($errLog.Length -gt 0) { [void]$sb.AppendLine($errLog.ToString()) }
else { [void]$sb.AppendLine("Aucune erreur détectée. ✓") }

[void]$sb.AppendLine('')
[void]$sb.AppendLine("### TIMING PAR SECTION")
$sectionTimes | Select-Object Number, Section, @{N='Durée_s';E={$_.Duration.TotalSeconds.ToString('F2')}}, Status | Fmt-Table | ForEach-Object { [void]$sb.AppendLine($_) }

[void]$sb.AppendLine('')
[void]$sb.AppendLine("### MÉTRIQUES GLOBALES")
[void]$sb.AppendLine("Durée totale    : $($total.TotalSeconds.ToString('F2')) secondes")
[void]$sb.AppendLine("Sections        : $($sectionTimes.Count)")
[void]$sb.AppendLine("OK              : $(($sectionTimes | Where-Object Status -eq 'OK').Count)")
[void]$sb.AppendLine("ERREURS         : $(($sectionTimes | Where-Object Status -like 'ERREUR*').Count)")

$report = $sb.ToString()
$sha256 = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($report))).Replace('-','')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("Hash SHA-256 : $sha256")
[void]$sb.AppendLine('╚' + ('═'*78) + '╝')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== FIN PHASE 2 ===')

Write-Progress -Activity 'Audit Phase 2' -Status 'Écriture du rapport...' -PercentComplete -1
try {
    Set-Content -Path $ReportPath -Value $sb.ToString() -Encoding UTF8 -Force
    Write-Host "`n╔══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║           PHASE 2 TERMINÉE — SOFTWARE, DEV & FORENSICS                     ║" -ForegroundColor Green
    Write-Host "╠══════════════════════════════════════════════════════════════════════════════╣" -ForegroundColor Green
    Write-Host "║  Rapport  : $ReportPath" -ForegroundColor Green
    Write-Host "║  Durée    : $($total.TotalSeconds.ToString('F2'))s | Sections OK: $(($sectionTimes | Where-Object Status -eq 'OK').Count)/$(($sectionTimes.Count))" -ForegroundColor Green
    Write-Host "║  SHA-256  : $sha256" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
} catch {
    Write-Host "`n╔══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║                     ERREUR D'ÉCRITURE                                        ║" -ForegroundColor Red
    Write-Host "╚══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

Write-Host "`nAppuyez sur Entrée pour fermer..." -ForegroundColor Yellow
[void][System.Console]::ReadLine()
