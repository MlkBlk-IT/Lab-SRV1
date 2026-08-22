#Requires -Version 7.0
<#
.SYNOPSIS
    Audit Réseau Complet - PowerShell 7.6.4
.DESCRIPTION
    Script d'audit réseau exhaustif : Internet, DNS, Switch, vSwitch, Adapters,
    bande passante, ports ouverts, firewall, mapping app/port, et verification
    de la "proprete" du reseau.
    Les rapports HTML et LOG sont sauvegardes sur le BUREAU de l'utilisateur.
.PARAMETER TestBandwidth
    Active le test de bande passante (telechargement test).
.PARAMETER BandwidthTarget
    URL ou IP cible pour le test de bande passante.
.EXAMPLE
    .\Audit-ReseauComplet.ps1 -Verbose
    .\Audit-ReseauComplet.ps1 -TestBandwidth
.NOTES
    Auteur  : Auto-genere
    Version : 2.0
    Date    : 2026-07-25
    Requis  : PowerShell 7.6.4+, execution en administrateur recommandee
#>
[CmdletBinding()]
param(
    [switch]$TestBandwidth,
    [string]$BandwidthTarget = "speedtest.tele2.net"
)

#region --- INITIALISATION & CHEMIN BUREAU ---
$ErrorActionPreference = 'Continue'
$ReportSections = [System.Collections.Generic.List[hashtable]]::new()
$StartTime = Get-Date

# Chemin du Bureau (Desktop) - fonctionne pour tous les profils utilisateurs
$DesktopPath = [Environment]::GetFolderPath("Desktop")
if (-not $DesktopPath -or -not (Test-Path $DesktopPath)) {
    $DesktopPath = "$env:USERPROFILE\Desktop"
}
if (-not (Test-Path $DesktopPath)) {
    $DesktopPath = "$env:HOMEDRIVE$env:HOMEPATH\Desktop"
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$HtmlPath = "$DesktopPath\Audit_Reseau_$Timestamp.html"
$LogPath  = "$DesktopPath\Audit_Reseau_$Timestamp.log"

# Fonction d'ecriture dans le log ET la console
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
    switch ($Level) {
        "OK"    { Write-Host $line -ForegroundColor Green }
        "WARN"  { Write-Host $line -ForegroundColor Yellow }
        "FAIL"  { Write-Host $line -ForegroundColor Red }
        "INFO"  { Write-Host $line -ForegroundColor Cyan }
        default { Write-Host $line }
    }
}

function Write-Section {
    param([string]$Title, [string]$Status = "INFO", [object]$Data)
    Write-Log -Message "=== $Title ===" -Level $Status
    if ($Data) { 
        $tableStr = $Data | Format-Table -AutoSize | Out-String
        Add-Content -Path $LogPath -Value $tableStr -ErrorAction SilentlyContinue
        $tableStr | Write-Host 
    }
    $ReportSections.Add(@{ Title = $Title; Status = $Status; Data = $Data; Time = Get-Date })
}

function Test-IsAdmin {
    if ($IsWindows -or ($PSVersionTable.PSVersion.Major -le 5)) {
        return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    return $false
}

$IsAdmin = Test-IsAdmin
Write-Log -Message "Demarrage de l'audit reseau complet" -Level "INFO"
Write-Log -Message "Bureau detecte : $DesktopPath" -Level "INFO"
Write-Log -Message "Mode administrateur : $IsAdmin" -Level $(if($IsAdmin){"OK"}else{"WARN"})
Write-Log -Message "Fichiers de sortie : HTML=$HtmlPath | LOG=$LogPath" -Level "INFO"

if (-not $IsAdmin) {
    Write-Log -Message "ATTENTION : Ce script n'est PAS execute en administrateur. Certaines informations (firewall detaille, ports systeme, vSwitch) seront incompletes." -Level "WARN"
}
#endregion

#region --- 1. CONNECTIVITE INTERNET ---
Write-Section -Title "1. CONNECTIVITE INTERNET" -Status "INFO"

$InternetTests = @()
$targets = @(
    @{Host="1.1.1.1"; Name="Cloudflare DNS"},
    @{Host="8.8.8.8"; Name="Google DNS"},
    @{Host="google.com"; Name="Google HTTP"},
    @{Host="github.com"; Name="GitHub"}
)

foreach ($t in $targets) {
    $ping = Test-Connection -TargetName $t.Host -Count 2 -TimeoutSeconds 2 -ErrorAction SilentlyContinue
    $latency = if ($ping) { ($ping | Measure-Object Latency -Average).Average } else { $null }
    $InternetTests += [PSCustomObject]@{
        Cible        = $t.Name
        Adresse      = $t.Host
        Accessible   = [bool]$ping
        Latence_ms   = [math]::Round($latency,2)
        Paquets_OK   = if ($ping) { $ping.Count } else { 0 }
    }
}

# Test HTTP/HTTPS basique
try {
    $httpTest = Invoke-RestMethod -Uri "https://httpbin.org/get" -TimeoutSec 5 -ErrorAction Stop
    $httpStatus = "OK"
    Write-Log -Message "Test HTTP(S) httpbin.org : SUCCES" -Level "OK"
} catch {
    $httpStatus = "FAIL: $($_.Exception.Message)"
    Write-Log -Message "Test HTTP(S) httpbin.org : $httpStatus" -Level "FAIL"
}

Write-Section -Title "1. CONNECTIVITE INTERNET" -Status $(if ($InternetTests.Accessible -contains $true) {"OK"} else {"FAIL"}) -Data $InternetTests
#endregion

#region --- 2. DNS ---
Write-Section -Title "2. CONFIGURATION & TEST DNS" -Status "INFO"

$DnsConfig = Get-DnsClientServerAddress -ErrorAction SilentlyContinue | 
    Where-Object { $_.AddressFamily -eq 2 } | 
    Select-Object InterfaceAlias, InterfaceIndex, 
        @{N="DNS_Servers";E={$_.ServerAddresses -join ', '}},
        @{N="Famille";E={"IPv4"}}

# Test de resolution
$DnsTests = @()
$dnsTargets = @("google.com","github.com","microsoft.com","cloudflare.com")
foreach ($d in $dnsTargets) {
    try {
        $res = Resolve-DnsName -Name $d -Type A -ErrorAction Stop | Select-Object -First 1
        $DnsTests += [PSCustomObject]@{ Nom = $d; Resolu = $true; IP = $res.IPAddress }
    } catch {
        $DnsTests += [PSCustomObject]@{ Nom = $d; Resolu = $false; IP = "N/A" }
    }
}

# Cache DNS
$DnsCache = Get-DnsClientCache -ErrorAction SilentlyContinue | 
    Select-Object -First 20 Entry, RecordType, Status, Data

Write-Section -Title "2a. SERVEURS DNS CONFIGURES" -Status $(if($DnsConfig){"OK"}else{"WARN"}) -Data $DnsConfig
Write-Section -Title "2b. TESTS DE RESOLUTION DNS" -Status $(if($DnsTests.Resolu -contains $true){"OK"}else{"FAIL"}) -Data $DnsTests
Write-Section -Title "2c. CACHE DNS (Top 20)" -Status "INFO" -Data $DnsCache
#endregion

#region --- 3. CARTES RESEAU / ADAPTERS ---
Write-Section -Title "3. CARTES RESEAU & ADAPTATEURS" -Status "INFO"

$Adapters = Get-NetAdapter -ErrorAction SilentlyContinue | 
    Select-Object Name, InterfaceDescription, MacAddress, Status, LinkSpeed, 
        MediaConnectionState, DriverVersion, DriverDate, 
        @{N="IPv4";E={ (Get-NetIPAddress -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress -join ', ' }},
        @{N="IPv6";E={ (Get-NetIPAddress -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue | Where-Object {$_.IPAddress -notlike "fe80*"}).IPAddress -join ', ' }},
        @{N="Passerelle";E={ (Get-NetRoute -InterfaceIndex $_.InterfaceIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue).NextHop -join ', ' }},
        @{N="MTU";E={ (Get-NetIPInterface -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).NlMtu }}

$IPConfig = Get-NetIPConfiguration -Detailed -ErrorAction SilentlyContinue | 
    Select-Object InterfaceAlias, InterfaceIndex, NetProfile.Name, NetProfile.NetworkCategory,
        @{N="IPv4Address";E={$_.IPv4Address.IPAddress}},
        @{N="IPv6Address";E={$_.IPv6Address.IPAddress}},
        @{N="Gateway";E={$_.NetIPv4Interface.NextHop}},
        @{N="DNSServers";E={$_.DNSServer.ServerAddresses -join ', '}}

Write-Section -Title "3a. ADAPTATEURS PHYSIQUES/LOGIQUES" -Status "OK" -Data $Adapters
Write-Section -Title "3b. CONFIGURATION IP DETAILLEE" -Status "OK" -Data $IPConfig
#endregion

#region --- 4. VSWITCH (HYPER-V) ---
Write-Section -Title "4. VIRTUAL SWITCHES (HYPER-V)" -Status "INFO"

if (Get-Module -ListAvailable Hyper-V) {
    try {
        $vSwitches = Get-VMSwitch -ErrorAction SilentlyContinue | 
            Select-Object Name, SwitchType, NetAdapterInterfaceDescription, 
                AllowManagementOS, EmbeddedTeamingEnabled, 
                @{N="BandePassante";E={ if ($_.BandwidthReservationMode) { $_.BandwidthReservationMode } else { "Illimite" }}}

        $vAdapters = Get-VMNetworkAdapter -ManagementOS -ErrorAction SilentlyContinue | 
            Select-Object Name, IsManagementOs, SwitchName, IPAddresses, MacAddress, Status

        Write-Section -Title "4a. VMSWITCHES" -Status $(if($vSwitches){"OK"}else{"WARN"}) -Data $vSwitches
        Write-Section -Title "4b. VM NETWORK ADAPTERS (ManagementOS)" -Status "INFO" -Data $vAdapters
    } catch {
        Write-Section -Title "4. VIRTUAL SWITCHES" -Status "WARN" -Data "Hyper-V detecte mais impossible de recuperer les donnees : $($_.Exception.Message)"
    }
} else {
    Write-Section -Title "4. VIRTUAL SWITCHES" -Status "WARN" -Data "Module Hyper-V non disponible. vSwitch non audites."
}
#endregion

#region --- 5. SWITCH PHYSIQUE ---
Write-Section -Title "5. SWITCH PHYSIQUE (INFORMATION LIMITEE)" -Status "INFO"

$SwitchInfo = @()
try {
    $lldp = Get-NetLldpAgent -ErrorAction SilentlyContinue | 
        Select-Object Interface, ChassisID, PortID, ManagementAddress
    if ($lldp) { $SwitchInfo += $lldp }
} catch {}

try {
    $nicConfigs = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue | 
        Where-Object { $_.IPEnabled } | 
        Select-Object Description, MACAddress, DefaultIPGateway, DHCPServer, DNSDomain
    if ($nicConfigs) { $SwitchInfo += $nicConfigs }
} catch {}

if ($SwitchInfo.Count -eq 0) {
    $SwitchInfo = [PSCustomObject]@{ 
        Note = "Les switchs physiques manages necessitent LLDP/CDP active ou SNMP. Utilisez Get-NetLldpAgent ou un outil du fabricant (Cisco, Aruba, etc.)." 
    }
}

Write-Section -Title "5. SWITCH PHYSIQUE" -Status "INFO" -Data $SwitchInfo
#endregion

#region --- 6. BANDE PASSANTE ---
Write-Section -Title "6. BANDE PASSANTE & PERFORMANCES" -Status "INFO"

$Counters = @()
$nicNames = (Get-Counter -ListSet "Network Interface" -ErrorAction SilentlyContinue).PathsWithInstances
if ($nicNames) {
    $perfCounters = @(
        "\Network Interface(*)\Bytes Total/sec",
        "\Network Interface(*)\Current Bandwidth",
        "\Network Interface(*)\Packets/sec"
    )
    $perfData = Get-Counter -Counter $perfCounters -MaxSamples 1 -ErrorAction SilentlyContinue
    if ($perfData) {
        $Counters = $perfData.CounterSamples | 
            Select-Object Path, InstanceName, 
                @{N="Value";E={[math]::Round($_.CookedValue,2)}},
                @{N="Unit";E={if($_.Path -like "*Bandwidth*"){"bits/sec"}else{"varie"}}}
    }
}

$BandwidthResult = "Non teste (utilisez -TestBandwidth)"
if ($TestBandwidth) {
    try {
        $url = "http://$BandwidthTarget/10MB.zip"
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $null = Invoke-RestMethod -Uri $url -TimeoutSec 30 -ErrorAction Stop
        $sw.Stop()
        $seconds = $sw.Elapsed.TotalSeconds
        $mbps = [math]::Round((10 * 8) / $seconds, 2)
        $BandwidthResult = "~$mbps Mbps (telechargement 10MB en $([math]::Round($seconds,2))s)"
        Write-Log -Message "Test bande passante : $BandwidthResult" -Level "OK"
    } catch {
        $BandwidthResult = "Echec du test : $($_.Exception.Message)"
        Write-Log -Message "Test bande passante : $BandwidthResult" -Level "FAIL"
    }
}

Write-Section -Title "6a. COMPTEURS DE PERFORMANCE" -Status $(if($Counters){"OK"}else{"WARN"}) -Data $Counters
Write-Section -Title "6b. TEST DE DEBIT" -Status $(if($TestBandwidth){"OK"}else{"INFO"}) -Data $BandwidthResult
#endregion

#region --- 7. PORTS OUVERTS ---
Write-Section -Title "7. PORTS OUVERTS & CONNEXIONS ACTIVES" -Status "INFO"

$TcpConnections = Get-NetTCPConnection -ErrorAction SilentlyContinue | 
    Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess,
        @{N="ProcessName";E={ (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName }},
        @{N="ProcessPath";E={ (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Path }},
        @{N="CreationTime";E={ $_.CreationTime }} | 
    Sort-Object State, LocalPort

$Listening = $TcpConnections | Where-Object { $_.State -eq "Listen" }
$Established = $TcpConnections | Where-Object { $_.State -eq "Established" }

Write-Section -Title "7a. PORTS EN ECOUTE" -Status $(if($Listening){"OK"}else{"WARN"}) -Data ($Listening | Select-Object -First 50)
Write-Section -Title "7b. CONNEXIONS ETABLIES (Top 30)" -Status "INFO" -Data ($Established | Select-Object -First 30)
#endregion

#region --- 8. FIREWALL ---
Write-Section -Title "8. REGLES FIREWALL" -Status "INFO"

if ($IsAdmin) {
    $FirewallRules = Get-NetFirewallRule -Enabled True -ErrorAction SilentlyContinue | 
        Where-Object { $_.Direction -eq "Inbound" -and $_.Action -eq "Allow" } | 
        Select-Object -First 50 DisplayName, Direction, Action, Profile, 
            @{N="LocalPorts";E={ (Get-NetFirewallPortFilter -AssociatedNetFirewallRule $_ -ErrorAction SilentlyContinue).LocalPort }},
            @{N="Protocol";E={ (Get-NetFirewallPortFilter -AssociatedNetFirewallRule $_ -ErrorAction SilentlyContinue).Protocol }},
            @{N="RemoteAddress";E={ (Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $_ -ErrorAction SilentlyContinue).RemoteAddress }}

    $FirewallStats = Get-NetFirewallRule -Enabled True | Group-Object Direction, Action | 
        Select-Object Name, Count

    Write-Section -Title "8a. REGLES INBOUND ALLOW (Top 50)" -Status "INFO" -Data $FirewallRules
    Write-Section -Title "8b. STATISTIQUES FIREWALL" -Status "INFO" -Data $FirewallStats
} else {
    Write-Section -Title "8. FIREWALL" -Status "WARN" -Data "Necessite des privileges administrateur pour lecture complete des regles."
}
#endregion

#region --- 9. APPLICATIONS <-> PORTS ---
Write-Section -Title "9. MAPPING APPLICATIONS / PORTS" -Status "INFO"

$AppPortMapping = Get-NetTCPConnection -ErrorAction SilentlyContinue | 
    Where-Object { $_.State -eq "Listen" } | 
    ForEach-Object {
        $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
        [PSCustomObject]@{
            ProcessName = $proc.ProcessName
            PID         = $_.OwningProcess
            Path        = $proc.Path
            Port        = $_.LocalPort
            Address     = $_.LocalAddress
            Protocol    = "TCP"
        }
    } | Sort-Object Port -Unique

$UdpEndpoints = Get-NetUDPEndpoint -ErrorAction SilentlyContinue | 
    ForEach-Object {
        $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
        [PSCustomObject]@{
            ProcessName = $proc.ProcessName
            PID         = $_.OwningProcess
            Path        = $proc.Path
            Port        = $_.LocalPort
            Address     = $_.LocalAddress
            Protocol    = "UDP"
        }
    } | Sort-Object Port -Unique

Write-Section -Title "9a. APPLICATIONS EN ECOUTE TCP" -Status "INFO" -Data $AppPortMapping
Write-Section -Title "9b. APPLICATIONS EN ECOUTE UDP" -Status "INFO" -Data $UdpEndpoints
#endregion

#region --- 10. VERIFICATION "PROPRETE" RESEAU ---
Write-Section -Title "10. VERIFICATION DE LA PROPRETE DU RESEAU" -Status "INFO"

$CleanChecks = @()

# 10.1 Conflits ARP
try {
    $arpTable = Get-NetNeighbor -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Reachable" }
    $dupMac = $arpTable | Group-Object LinkLayerAddress | Where-Object { $_.Count -gt 1 }
    $CleanChecks += [PSCustomObject]@{
        Check = "Conflit MAC/ARP"
        Status = if ($dupMac) { "ALERTE" } else { "OK" }
        Detail = if ($dupMac) { "MACs dupliquees detectees : $($dupMac.Name -join ', ')" } else { "Aucun conflit ARP detecte" }
    }
} catch {
    $CleanChecks += [PSCustomObject]@{ Check = "Conflit MAC/ARP"; Status = "ERREUR"; Detail = $_.Exception.Message }
}

# 10.2 Plusieurs passerelles par defaut
$defaultRoutes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
$CleanChecks += [PSCustomObject]@{
    Check = "Passerelles par defaut"
    Status = if ($defaultRoutes.Count -gt 1) { "WARN" } else { "OK" }
    Detail = "Nombre de routes par defaut : $($defaultRoutes.Count)"
}

# 10.3 DNS Suffix
$dnsSuffix = (Get-DnsClient -ErrorAction SilentlyContinue).ConnectionSpecificSuffix | Select-Object -Unique
$CleanChecks += [PSCustomObject]@{
    Check = "Suffixes DNS"
    Status = "INFO"
    Detail = "Suffixes trouves : $($dnsSuffix -join ', ')"
}

# 10.4 Proxy systeme
$proxy = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue).ProxyServer
$proxyEnable = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue).ProxyEnable
$CleanChecks += [PSCustomObject]@{
    Check = "Proxy HTTP"
    Status = if ($proxyEnable -eq 1) { "WARN" } else { "OK" }
    Detail = if ($proxyEnable -eq 1) { "Proxy active : $proxy" } else { "Aucun proxy detecte" }
}

# 10.5 Cartes deconnectees avec IP
$disconnectedButConfig = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne "Up" -and (Get-NetIPAddress -InterfaceIndex $_.InterfaceIndex -ErrorAction SilentlyContinue) }
$CleanChecks += [PSCustomObject]@{
    Check = "Cartes deconnectees avec IP"
    Status = if ($disconnectedButConfig) { "WARN" } else { "OK" }
    Detail = if ($disconnectedButConfig) { "Cartes concernees : $($disconnectedButConfig.Name -join ', ')" } else { "Aucune" }
}

# 10.6 MTU incoherent
$mtuValues = (Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.ConnectionState -eq "Connected" }).NlMtu | Sort-Object -Unique
$CleanChecks += [PSCustomObject]@{
    Check = "Coherence MTU"
    Status = if ($mtuValues.Count -gt 1) { "INFO" } else { "OK" }
    Detail = "Valeurs MTU detectees : $($mtuValues -join ', ')"
}

# 10.7 Ports sensibles
$suspiciousPorts = @(135, 445, 3389, 5985, 5986, 22, 23, 21, 25, 110, 143)
$suspiciousListening = $Listening | Where-Object { $_.LocalPort -in $suspiciousPorts }
$CleanChecks += [PSCustomObject]@{
    Check = "Ports sensibles ouverts"
    Status = if ($suspiciousListening) { "WARN" } else { "OK" }
    Detail = if ($suspiciousListening) { "Ports : $($suspiciousListening.LocalPort -join ', ')" } else { "Aucun port sensible en ecoute" }
}

# 10.8 NetBIOS
$netbios = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue | 
    Where-Object { $_.IPEnabled } | 
    Select-Object Description, @{N="NetBIOS";E={switch($_.TcpipNetbiosOptions){0{"Par defaut"}1{"Active"}2{"Desactive"}}}}
$netbiosOn = $netbios | Where-Object { $_.NetBIOS -eq "Active" -or $_.NetBIOS -eq "Par defaut" }
$CleanChecks += [PSCustomObject]@{
    Check = "NetBIOS over TCP/IP"
    Status = if ($netbiosOn) { "INFO" } else { "OK" }
    Detail = if ($netbiosOn) { "Actif sur : $($netbiosOn.Description -join ', ')" } else { "Desactive partout" }
}

Write-Section -Title "10. CONTROLES DE PROPRETE" -Status $(if($CleanChecks.Status -contains "ALERTE"){"FAIL"}elseif($CleanChecks.Status -contains "WARN"){"WARN"}else{"OK"}) -Data $CleanChecks
#endregion

#region --- 11. TABLE DE ROUTAGE ---
Write-Section -Title "11. TABLE DE ROUTAGE" -Status "INFO"

$Routes = Get-NetRoute -ErrorAction SilentlyContinue | 
    Where-Object { $_.DestinationPrefix -notlike "224*" -and $_.DestinationPrefix -notlike "ff0*" } | 
    Select-Object DestinationPrefix, NextHop, InterfaceAlias, RouteMetric, ifIndex, 
        @{N="Type";E={$_.Type}},
        @{N="Persistant";E={$_.Persistent}} | 
    Sort-Object RouteMetric

Write-Section -Title "11. ROUTES ACTIVES" -Status "INFO" -Data $Routes
#endregion

#region --- 12. GENERATION RAPPORT HTML ---
Write-Log -Message "Generation du rapport HTML sur le Bureau..." -Level "INFO"

$html = @"
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>Audit Reseau Complet - $(hostname)</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 40px; background: #f5f5f5; color: #333; }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 30px; border-left: 5px solid #3498db; padding-left: 15px; }
        .ok { color: #27ae60; }
        .warn { color: #f39c12; }
        .fail { color: #e74c3c; }
        .info { color: #3498db; }
        table { border-collapse: collapse; width: 100%; margin: 15px 0; background: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        th, td { border: 1px solid #ddd; padding: 10px; text-align: left; font-size: 13px; }
        th { background: #3498db; color: white; font-weight: 600; }
        tr:nth-child(even) { background: #f9f9f9; }
        .summary { background: white; padding: 20px; border-radius: 8px; margin-bottom: 30px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
        .badge { display: inline-block; padding: 4px 12px; border-radius: 12px; font-size: 12px; font-weight: bold; color: white; }
        .badge-ok { background: #27ae60; }
        .badge-warn { background: #f39c12; }
        .badge-fail { background: #e74c3c; }
        .badge-info { background: #3498db; }
        pre { background: #2c3e50; color: #ecf0f1; padding: 15px; border-radius: 5px; overflow-x: auto; }
        .footer { text-align:center; color:#7f8c8d; font-size:12px; margin-top:40px; }
    </style>
</head>
<body>
    <h1>&#128269; Audit Reseau Complet</h1>
    <div class="summary">
        <strong>Machine :</strong> $(hostname)<br>
        <strong>Date :</strong> $($StartTime)<br>
        <strong>Duree :</strong> $([math]::Round(((Get-Date)-$StartTime).TotalSeconds,2)) secondes<br>
        <strong>PowerShell :</strong> $($PSVersionTable.PSVersion)<br>
        <strong>Administrateur :</strong> $IsAdmin<br>
        <strong>Chemin HTML :</strong> $HtmlPath<br>
        <strong>Chemin LOG :</strong> $LogPath
    </div>
"@

foreach ($section in $ReportSections) {
    $badgeClass = switch ($section.Status) { "OK" { "badge-ok" } "WARN" { "badge-warn" } "FAIL" { "badge-fail" } default { "badge-info" } }
    $html += "<h2>$($section.Title) <span class='badge $badgeClass'>$($section.Status)</span></h2>`n"

    if ($section.Data -is [string]) {
        $html += "<p>$($section.Data)</p>`n"
    } elseif ($section.Data) {
        $html += "<table>`n<tr>"
        $props = $section.Data[0].PSObject.Properties.Name
        foreach ($p in $props) { $html += "<th>$p</th>" }
        $html += "</tr>`n"

        foreach ($row in $section.Data) {
            $html += "<tr>"
            foreach ($p in $props) {
                $val = $row.$p
                if ($val -eq $null) { $val = "" }
                $html += "<td>$([System.Web.HttpUtility]::HtmlEncode($val))</td>"
            }
            $html += "</tr>`n"
        }
        $html += "</table>`n"
    } else {
        $html += "<p><em>Aucune donnee disponible.</em></p>`n"
    }
}

$html += @"
    <div class="footer">
        <hr>
        Genere par Audit-ReseauComplet.ps1 | PowerShell $($PSVersionTable.PSVersion)<br>
        Fichiers sur le Bureau : <strong>$([System.IO.Path]::GetFileName($HtmlPath))</strong> et <strong>$([System.IO.Path]::GetFileName($LogPath))</strong>
    </div>
</body>
</html>
"@

$html | Out-File -FilePath $HtmlPath -Encoding UTF8
Write-Log -Message "Rapport HTML genere : $HtmlPath" -Level "OK"
Write-Log -Message "Fichier LOG genere : $LogPath" -Level "OK"

# Ouverture automatique des fichiers
if ($IsWindows -or ($PSVersionTable.PSVersion.Major -le 5)) {
    try {
        Start-Process $HtmlPath
        Write-Log -Message "Rapport HTML ouvert dans le navigateur" -Level "OK"
    } catch {
        Write-Log -Message "Impossible d'ouvrir le HTML automatiquement" -Level "WARN"
    }
    try {
        Start-Process notepad.exe -ArgumentList $LogPath
        Write-Log -Message "Fichier LOG ouvert dans le Bloc-notes" -Level "OK"
    } catch {
        Write-Log -Message "Impossible d'ouvrir le LOG automatiquement" -Level "WARN"
    }
}
#endregion

Write-Log -Message "Audit termine en $([math]::Round(((Get-Date)-$StartTime).TotalSeconds,2)) secondes." -Level "OK"
Write-Host "`n&#9989; Fichiers sur le BUREAU :" -ForegroundColor Green
Write-Host "   HTML : $HtmlPath" -ForegroundColor Cyan
Write-Host "   LOG  : $LogPath" -ForegroundColor Cyan
