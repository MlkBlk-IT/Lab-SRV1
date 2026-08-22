$File = "$env:USERPROFILE\Desktop\Wifi_Audit.txt"
Clear-Content $File -ErrorAction SilentlyContinue

"=== AUDIT WI-FI & RÉSEAU ===" | Out-File $File
"Date: $(Get-Date)" | Add-Content $File
"" | Add-Content $File

# 1. Interface Wi-Fi Actuelle (netsh)
" [1] INTERFACE WI-FI ACTUELLE" | Add-Content $File
netsh wlan show interfaces | Add-Content $File
"" | Add-Content $File

# 2. Configuration IP et DNS
" [2] CONFIGURATION IP & DNS" | Add-Content $File
$dns = Get-DnsClientServerAddress -InterfaceAlias "Wi-Fi"
$ip = Get-NetIPAddress -InterfaceAlias "Wi-Fi" -AddressFamily IPv4
$route = Get-NetRoute -InterfaceAlias "Wi-Fi" -DestinationPrefix "0.0.0.0/0"

"IP Address: $($ip.IPAddress)" | Add-Content $File
"Prefix Length: $($ip.PrefixLength)" | Add-Content $File
"Gateway: $($route.NextHop)" | Add-Content $File
"DNS Servers:" | Add-Content $File
$dns.ServerAddresses | ForEach-Object { "  - $_" | Add-Content $File }
"" | Add-Content $File

# 3. Propriétés de l'adaptateur (Driver & Hardware)
" [3] ADAPTATEUR & DRIVER" | Add-Content $File
$adapter = Get-NetAdapter -Name "Wi-Fi"
"Name: $($adapter.Name)" | Add-Content $File
"InterfaceDescription: $($adapter.InterfaceDescription)" | Add-Content $File
"DriverVersion: $($adapter.DriverVersion)" | Add-Content $File
"DriverDate: $($adapter.DriverDate)" | Add-Content $File
"LinkSpeed: $($adapter.LinkSpeed)" | Add-Content $File
"MediaConnectionState: $($adapter.MediaConnectionState)" | Add-Content $File
"" | Add-Content $File

# 4. Profils Wi-Fi sauvegardés (Audit de sécurité)
" [4] PROFILS WI-FI SAUVEGARDÉS" | Add-Content $File
netsh wlan show profiles | Add-Content $File
"" | Add-Content $File

# 5. Paramètres avancés (Registry - Tweaks)
" [5] PARAMÈTRES AVANCÉS (REGISTRY)" | Add-Content $File
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}"
$adapters = Get-ChildItem $regPath | Where-Object { $_.PSChildName -match "^\d{4}$" }
foreach ($a in $adapters) {
    $desc = (Get-ItemProperty $a.PSPath).DriverDesc
    if ($desc -like "*Wi-Fi*" -or $desc -like "*Wireless*" -or $desc -like "*AX201*") {
        "Adaptateur: $desc" | Add-Content $File
        $props = Get-ItemProperty $a.PSPath
        $props.PSObject.Properties | Where-Object { 
            $_.Name -notlike "PS*" -and $_.Value -ne $null -and $_.Name -notlike "Inf*" -and $_.Name -notlike "Provider*" 
        } | ForEach-Object {
            "  $($_.Name) = $($_.Value)" | Add-Content $File
        }
    }
}
"" | Add-Content $File

"=== FIN DE L'AUDIT ===" | Add-Content $File
notepad $File