<#
.SYNOPSIS
    Optimizer module
#>

function Invoke-DomainOptimization {
    param(
        [Parameter(Mandatory=$true)][string]$Domain,
        [Parameter(Mandatory=$true)][string]$OriginalIP,
        [Parameter(Mandatory=$true)]$Config,
        [Parameter(Mandatory=$true)]$BackupPool,
        [ref]$BackupPoolUpdated
    )

    $timeout = $Config.testTimeoutMs
    $retry = $Config.retryCount
    $retryCount = if ($Config.remoteSourceRetryCount) { $Config.remoteSourceRetryCount } else { 2 }

    $domainDisplay = $Domain.PadRight(42)
    Write-Host "  $domainDisplay" -NoNewline

    $result = Test-IPSpeed -IP $OriginalIP -TimeoutMs $timeout -RetryCount $retry

    if ($result.Success) {
        $latencyStr = "$($result.Latency)ms".PadLeft(6)
        Write-Host "[OK] " -ForegroundColor Green -NoNewline
        Write-Host $latencyStr -ForegroundColor DarkGray
        $Global:Stats.NormalCount++
        return @{ Domain = $Domain; Status = 'Normal'; IP = $OriginalIP; Latency = $result.Latency; OldIP = $null }
    }

    Write-Host "[--] Testing..." -ForegroundColor Yellow

    # Layer 2: Local backup pool
    $candidateIPs = @()
    if ($BackupPool.domains.ContainsKey($Domain)) {
        $candidateIPs = @($BackupPool.domains[$Domain])
    }

    if ($candidateIPs.Count -gt 0) {
        $bestIP = Select-BestIP -IPs $candidateIPs -TimeoutMs $timeout -RetryCount $retry

        if ($bestIP) {
            Write-Host "  ".PadRight(44) -NoNewline
            Write-Host "[REPL] " -ForegroundColor Yellow -NoNewline
            Write-Host "$($bestIP.IP) ($($bestIP.Latency)ms)" -ForegroundColor Cyan
            $Global:Stats.ReplacedCount++
            return @{ Domain = $Domain; Status = 'Replaced'; IP = $bestIP.IP; Latency = $bestIP.Latency; OldIP = $OriginalIP }
        }
    }

    # Layer 3: Update backup pool
    if (-not $BackupPoolUpdated.Value) {
        $newPool = Update-BackupPool -Sources $Config.remoteHostSources -FilePath $Config.backupPoolFile -RetryCount $retryCount
        if ($newPool) {
            $BackupPoolUpdated.Value = $true
            $BackupPool = $newPool

            if ($BackupPool.domains.ContainsKey($Domain)) {
                $candidateIPs = @($BackupPool.domains[$Domain])

                if ($candidateIPs.Count -gt 0) {
                    $bestIP = Select-BestIP -IPs $candidateIPs -TimeoutMs $timeout -RetryCount $retry

                    if ($bestIP) {
                        Write-Host "  ".PadRight(44) -NoNewline
                        Write-Host "[REPL] " -ForegroundColor Yellow -NoNewline
                        Write-Host "$($bestIP.IP) ($($bestIP.Latency)ms)" -ForegroundColor Cyan
                        $Global:Stats.ReplacedCount++
                        return @{ Domain = $Domain; Status = 'Replaced'; IP = $bestIP.IP; Latency = $bestIP.Latency; OldIP = $OriginalIP }
                    }
                }
            }
        }
    }

    # Layer 4: DNS API
    $apiIPs = Get-IPsFromMultipleSources -Domain $Domain

    if ($apiIPs.Count -gt 0) {
        $bestIP = Select-BestIP -IPs $apiIPs -TimeoutMs $timeout -RetryCount $retry

        if ($bestIP) {
            Write-Host "  ".PadRight(44) -NoNewline
            Write-Host "[REPL] " -ForegroundColor Yellow -NoNewline
            Write-Host "$($bestIP.IP) ($($bestIP.Latency)ms) [API]" -ForegroundColor Cyan
            $Global:Stats.ReplacedCount++
            return @{ Domain = $Domain; Status = 'Replaced'; IP = $bestIP.IP; Latency = $bestIP.Latency; OldIP = $OriginalIP }
        }
    }

    Write-Host "  ".PadRight(44) -NoNewline
    Write-Host "[FAIL] " -ForegroundColor Red -NoNewline
    Write-Host "No available IP" -ForegroundColor DarkGray
    $Global:Stats.FailedCount++

    return @{ Domain = $Domain; Status = 'Failed'; IP = $OriginalIP; Latency = -1; OldIP = $null }
}
