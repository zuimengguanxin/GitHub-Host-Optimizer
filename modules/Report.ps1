<#
.SYNOPSIS
    Report module
#>

function Show-ExecutionReport {
    param([Parameter(Mandatory=$true)][array]$Results)

    $total = $Global:Stats.TotalDomains
    $normal = $Global:Stats.NormalCount
    $replaced = $Global:Stats.ReplacedCount
    $failed = $Global:Stats.FailedCount
    $availableRate = if ($total -gt 0) { [math]::Round(($total - $failed) / $total * 100, 1) } else { 0 }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "            SUMMARY                     " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    Write-Host "  Total domains: $total" -ForegroundColor White
    Write-Host "  Normal:        $normal" -ForegroundColor Green
    Write-Host "  Replaced:      $replaced" -ForegroundColor Yellow
    Write-Host "  Failed:        $failed" -ForegroundColor Red
    Write-Host "  Available:     $availableRate%" -ForegroundColor $(if ($availableRate -ge 90) { 'Green' } elseif ($availableRate -ge 70) { 'Yellow' } else { 'Red' })

    Write-Host "----------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Backup pool:   $(if ($Global:Stats.BackupPoolUpdated) { 'Updated' } else { 'Skipped' })"
    Write-Host "  System hosts:  $(if ($Global:Stats.SystemHostsWritten) { 'Updated' } else { 'Skipped' })"

    if ($Global:Stats.FailedSources.Count -gt 0) {
        Write-Host ""
        Write-Host "  [!] Failed sources:" -ForegroundColor Yellow
        foreach ($src in $Global:Stats.FailedSources) {
            Write-Host "      - $src" -ForegroundColor Red
        }
    }

    if ($Global:Stats.FailedApis.Count -gt 0) {
        Write-Host ""
        Write-Host "  [!] Failed APIs:" -ForegroundColor Yellow
        foreach ($api in $Global:Stats.FailedApis) {
            Write-Host "      - $api" -ForegroundColor Red
        }
    }

    if ($failed -gt 0) {
        Write-Host ""
        Write-Host "  [!] Failed domains:" -ForegroundColor Yellow
        foreach ($result in $Results) {
            if ($result.Status -eq 'Failed') {
                Write-Host "      - $($result.Domain)" -ForegroundColor Red
            }
        }
    }

    Write-Host "========================================" -ForegroundColor Cyan
}
