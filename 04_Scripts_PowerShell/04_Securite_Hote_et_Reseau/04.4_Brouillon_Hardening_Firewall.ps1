Write-Host "=== DURCISSEMENT FIREWALL ===" -ForegroundColor Cyan

# Règle 1: Bloquer SMB & NetBIOS (Public uniquement)
New-NetFirewallRule -DisplayName "HARDEN-SMB-NetBIOS-IN-TCP" -Direction Inbound -LocalPort 137,138,139,445 -Protocol TCP -Action Block -Profile Public -Enabled True
New-NetFirewallRule -DisplayName "HARDEN-SMB-NetBIOS-IN-UDP" -Direction Inbound -LocalPort 137,138,139,445 -Protocol UDP -Action Block -Profile Public -Enabled True

# Règle 2: Bloquer RDP (Public uniquement)
New-NetFirewallRule -DisplayName "HARDEN-RDP-IN-TCP" -Direction Inbound -LocalPort 3389 -Protocol TCP -Action Block -Profile Public -Enabled True
New-NetFirewallRule -DisplayName "HARDEN-RDP-IN-UDP" -Direction Inbound -LocalPort 3389 -Protocol UDP -Action Block -Profile Public -Enabled True

# Règle 3: Bloquer Télémétrie Windows (Tous profils)
New-NetFirewallRule -DisplayName "HARDEN-TELEMETRY-DiagTrack" -Direction Outbound -Service DiagTrack -Action Block -Enabled True
New-NetFirewallRule -DisplayName "HARDEN-TELEMETRY-dmwappush" -Direction Outbound -Service dmwappushservice -Action Block -Enabled True

# Règle 4: Bloquer ICMP/Ping (Public uniquement)
New-NetFirewallRule -DisplayName "HARDEN-ICMP-IN" -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Block -Profile Public -Enabled True

# Règle 5: Bloquer SMB/RPC sortant (Tous profils)
New-NetFirewallRule -DisplayName "HARDEN-SMB-RPC-OUT-TCP" -Direction Outbound -RemotePort 135,445 -Protocol TCP -Action Block -Enabled True
New-NetFirewallRule -DisplayName "HARDEN-SMB-RPC-OUT-UDP" -Direction Outbound -RemotePort 135,445 -Protocol UDP -Action Block -Enabled True

Write-Host "✅ Durcissement appliqué avec succès" -ForegroundColor Green
Write-Host "📝 Résumé:" -ForegroundColor Yellow
Write-Host "  - SMB/NetBIOS bloqué en Public (Private autorisé pour imprimantes)" -ForegroundColor Gray
Write-Host "  - RDP bloqué en Public" -ForegroundColor Gray
Write-Host "  - Télémétrie Windows bloquée partout" -ForegroundColor Gray
Write-Host "  - Ping bloqué en Public" -ForegroundColor Gray
Write-Host "  - SMB/RPC sortant bloqué partout" -ForegroundColor Gray