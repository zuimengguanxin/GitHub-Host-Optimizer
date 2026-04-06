<#
.SYNOPSIS
    GitHub Host Optimizer
.DESCRIPTION
    Auto detect GitHub Host connectivity, speed test, update system hosts
.NOTES
    Version: 1.0.0
#>

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $PSCommandPath }
if (-not $ScriptDir) { $ScriptDir = $PWD.Path }

# Global stats
$Global:Stats = @{
    TotalDomains      = 0
    NormalCount       = 0
    ReplacedCount     = 0
    FailedCount       = 0
    BackupPoolUpdated = $false
    SystemHostsWritten = $false
    FailedSources     = @()
    FailedApis        = @()
}

# Domain results
$Global:DomainResults = @()

# Load modules
. "$ScriptDir\modules\Config.ps1"
. "$ScriptDir\modules\Admin.ps1"
. "$ScriptDir\modules\IPTest.ps1"
. "$ScriptDir\modules\HostsFile.ps1"
. "$ScriptDir\modules\BackupPool.ps1"
. "$ScriptDir\modules\DnsApi.ps1"
. "$ScriptDir\modules\Optimizer.ps1"
. "$ScriptDir\modules\Report.ps1"

# Main process
function Invoke-MainProcess {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "       GitHub Host Optimizer v1.0       " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $hasAdmin = Test-AdminPrivilege

    if (-not $hasAdmin) {
        Write-Host "  [!] No admin privilege, requesting..." -ForegroundColor Yellow

        $scriptPath = $MyInvocation.ScriptName
        if (-not $scriptPath) { $scriptPath = $PSCommandPath }

        $elevated = Request-AdminPrivilege -ScriptPath $scriptPath

        if ($elevated) {
            Write-Host "  [+] Admin privilege granted" -ForegroundColor Green
            $hasAdmin = $true
        } else {
            Write-Host "  [!] Admin denied, running in user mode" -ForegroundColor Yellow
            Write-Host "  [i] System hosts will not be updated" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  [+] Admin privilege confirmed" -ForegroundColor Green
    }

    $config = Get-Config

    Write-Host ""
    Write-Host "  === Loading Hosts ===" -ForegroundColor Cyan

    $mainHosts = Read-MainHostFile -FilePath $config.mainHostFile

    if ($mainHosts.Count -eq 0) {
        Write-Host "  [X] No hosts found!" -ForegroundColor Red
        return
    }

    $Global:Stats.TotalDomains = $mainHosts.Count
    Write-Host "  [+] Found $($mainHosts.Count) domains" -ForegroundColor Green

    $backupPool = Get-BackupPool -FilePath $config.backupPoolFile
    $backupPoolUpdated = $false

    Write-Host ""
    Write-Host "  === Testing domains ===" -ForegroundColor Cyan

    foreach ($domain in $mainHosts.Keys) {
        $originalIP = $mainHosts[$domain]

        $result = Invoke-DomainOptimization `
            -Domain $domain `
            -OriginalIP $originalIP `
            -Config $config `
            -BackupPool $backupPool `
            -BackupPoolUpdated ([ref]$backupPoolUpdated)

        $Global:DomainResults += ,$result
    }

    Write-Host ""
    Write-Host "  === Updating files ===" -ForegroundColor Cyan

    Update-MainHostFile -FilePath $config.mainHostFile -Results $Global:DomainResults
    Write-Host "  [+] my-github-hosts.txt updated" -ForegroundColor Green

    if ($hasAdmin) {
        Update-SystemHosts -HostsPath $config.systemHostsPath -Results $Global:DomainResults -AutoBackup $config.autoBackup
        if ($Global:Stats.SystemHostsWritten) {
            Write-Host "  [+] System hosts updated" -ForegroundColor Green
        }
    }

    Show-ExecutionReport -Results $Global:DomainResults
}

# Entry point
Invoke-MainProcess

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
