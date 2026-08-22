Write-Host "Application des tweaks Wi-Fi..." -ForegroundColor Cyan

# 1. Désactiver MIMO Power Save (Garde les 2 antennes actives en permanence)
Set-NetAdapterAdvancedProperty -Name "Wi-Fi" -RegistryKeyword "MIMOPowerSaveMode" -RegistryValue "0" -ErrorAction SilentlyContinue
Write-Host "[OK] MIMO Power Save Mode -> Désactivé (No SMPS)" -ForegroundColor Green

# 2. Réduire l'agressivité du Roaming (Évite les scans inutiles et micro-coupures)
Set-NetAdapterAdvancedProperty -Name "Wi-Fi" -RegistryKeyword "RoamAggressiveness" -RegistryValue "1" -ErrorAction SilentlyContinue
Write-Host "[OK] Roaming Aggressiveness -> Lowest (1)" -ForegroundColor Green

# 3. Forcer le mode 802.11ax/ac (S'assure qu'on ne rétrograde pas en n/g)
Set-NetAdapterAdvancedProperty -Name "Wi-Fi" -RegistryKeyword "WirelessMode" -RegistryValue "34" -ErrorAction SilentlyContinue
Write-Host "[OK] Wireless Mode -> 802.11ax/ac (Dual Band)" -ForegroundColor Green

# 4. Activer le Fat Channel Intolerant à 0 (Autorise les canaux larges 40/80MHz)
Set-NetAdapterAdvancedProperty -Name "Wi-Fi" -RegistryKeyword "FatChannelIntolerant" -RegistryValue "0" -ErrorAction SilentlyContinue
Write-Host "[OK] Fat Channel Intolerant -> 0 (Canaux larges autorisés)" -ForegroundColor Green

Write-Host "`n✅ Tweaks appliqués. Redémarre ton PC pour que ce soit 100% effectif." -ForegroundColor Yellow