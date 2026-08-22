$File = "$env:USERPROFILE\Desktop\Firewall_Audit.txt"
"=== FIREWALL AUDIT ===" | Out-File $File
"Date: $(Get-Date)" | Add-Content $File
"" | Add-Content $File

Get-NetFirewallRule | ForEach-Object {
    $Port = $_ | Get-NetFirewallPortFilter
    "$($_.DisplayName) | $($_.Direction) | $($_.Action) | Port: $($Port.LocalPort ?? 'Any')" | Add-Content $File
}

notepad $File