<#
.SYNOPSIS
PathAudit.ps1 (squelette professionnel)

.DESCRIPTION
Audit en lecture seule des variables PATH Machine, User et Process.
Version initiale servant de base à un audit complet.
#>

[CmdletBinding()]
param(
    [string]$OutputPath = "$env:USERPROFILE\Documents\PathAudit"
)

$ErrorActionPreference='Stop'

function Get-PathEntries {
    param([string]$Value)
    if([string]::IsNullOrWhiteSpace($Value)){ return @() }
    $Value -split ';' | ForEach-Object {$_.Trim()} | Where-Object {$_}
}

New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null

$machine = [Environment]::GetEnvironmentVariable("Path","Machine")
$user    = [Environment]::GetEnvironmentVariable("Path","User")
$process = $env:Path

$entries = foreach($scope,$value in @(
    @("Machine",$machine),
    @("User",$user),
    @("Process",$process)
)){
    foreach($e in Get-PathEntries $value){
        $expanded=[Environment]::ExpandEnvironmentVariables($e)
        [pscustomobject]@{
            Scope=$scope
            Original=$e
            Expanded=$expanded
            Exists=Test-Path $expanded
            Duplicate=($value -split ';' | Where-Object { $_.Trim() -eq $e }).Count -gt 1
            ContainsVariable=$e -match '%.+%'
        }
    }
}

$entries | Sort-Object Scope,Original | Format-Table -AutoSize
$entries | Export-Csv (Join-Path $OutputPath "PathAudit.csv") -NoTypeInformation
$entries | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $OutputPath "PathAudit.json")

$summary=@"
PATH AUDIT

Machine entries : $((Get-PathEntries $machine).Count)
User entries    : $((Get-PathEntries $user).Count)
Process entries : $((Get-PathEntries $process).Count)

Missing paths   : $(($entries|? Exists -eq $false).Count)
Duplicates      : $(($entries|? Duplicate).Count)
"@
$summary | Set-Content (Join-Path $OutputPath "Summary.txt")

Write-Host ""
Write-Host "Audit terminé."
Write-Host "Résultats : $OutputPath"
