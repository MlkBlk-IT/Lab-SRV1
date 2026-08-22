#Requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference='Continue'

$Desktop=[Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
$AuditDir=Join-Path $Desktop 'Audit'
if(-not(Test-Path $AuditDir)){New-Item -ItemType Directory -Path $AuditDir|Out-Null}
$Report=Join-Path $AuditDir ("Server2025_BasicAudit_{0}.txt" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))

function Write-Section($Title){
    $line='='*70
    Add-Content $Report "`r`n$line`r`n$Title`r`n$line"
    Write-Host "`n$Title" -ForegroundColor Cyan
}
function Write-Data($Data){
    $txt=$Data|Out-String -Width 4096
    $txt|Add-Content $Report
    Write-Host $txt
}

"Windows Server 2025 Basic Audit`r`nGenerated: $(Get-Date)"|Set-Content $Report

Write-Section "SYSTEM"
Write-Data (Get-ComputerInfo|Select CsName,WindowsProductName,WindowsVersion,OsBuildNumber,OsUptime)

Write-Section "CPU / MEMORY"
Write-Data (Get-CimInstance Win32_Processor|Select Name,NumberOfCores,NumberOfLogicalProcessors)
Write-Data (Get-CimInstance Win32_ComputerSystem|Select @{N='RAM_GB';E={[math]::Round($_.TotalPhysicalMemory/1GB,2)}})

Write-Section "DISKS"
Write-Data (Get-Disk|Select Number,FriendlyName,@{N='SizeGB';E={[math]::Round($_.Size/1GB,2)}},OperationalStatus)
Write-Data (Get-Volume|Select DriveLetter,FileSystem,@{N='SizeGB';E={[math]::Round($_.Size/1GB,2)}},@{N='FreeGB';E={[math]::Round($_.SizeRemaining/1GB,2)}})

Write-Section "NETWORK"
$cfg=Get-NetIPConfiguration|ForEach-Object{
[pscustomobject]@{
NIC=$_.InterfaceAlias
IPv4=($_.IPv4Address.IPAddress -join ', ')
Gateway=$_.IPv4DefaultGateway.NextHop
DNS=($_.DnsServer.ServerAddresses -join ', ')
}}
Write-Data $cfg

Write-Section "FIREWALL"
Write-Data (Get-NetFirewallProfile|Select Name,Enabled)

Write-Section "SERVICES"
$svc='DNS','DHCPServer','RemoteAccess','WinRM','W32Time','LanmanServer','LanmanWorkstation'
Write-Data (Get-Service -EA SilentlyContinue|?{$svc -contains $_.Name}|Select Name,Status,StartType)

$roles=0
if(Get-Command Get-WindowsFeature -EA SilentlyContinue){
Write-Section "ROLES"
$r=Get-WindowsFeature|? Installed|Select Name,DisplayName
$roles=$r.Count
Write-Data $r
}

Write-Section "SUMMARY"
Write-Data ([pscustomobject]@{Adapters=(Get-NetAdapter).Count;Disks=(Get-Disk).Count;Volumes=(Get-Volume).Count;InstalledRoles=$roles;Report=$Report})

Write-Host "`nReport saved to:`n$Report" -ForegroundColor Green
