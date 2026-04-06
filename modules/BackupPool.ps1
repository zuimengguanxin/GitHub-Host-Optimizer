<#
.SYNOPSIS
    Backup Pool module
#>

function Get-BackupPool {
    param([Parameter(Mandatory=$true)][string]$FilePath)

    $fullPath = if ([System.IO.Path]::IsPathRooted($FilePath)) { $FilePath } else { Join-Path $ScriptDir $FilePath }

    if (-not (Test-Path $fullPath)) {
        return @{ lastUpdated = $null; domains = @{} }
    }

    try {
        $jsonContent = Get-Content -Path $fullPath -Raw -Encoding UTF8
        $pool = $jsonContent | ConvertFrom-Json

        $domains = @{}
        foreach ($prop in $pool.domains.PSObject.Properties) {
            $domains[$prop.Name] = @($prop.Value)
        }

        return @{ lastUpdated = $pool.lastUpdated; domains = $domains }
    } catch {
        return @{ lastUpdated = $null; domains = @{} }
    }
}

function Update-BackupPool {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Sources,
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        [int]$RetryCount = 2
    )

    if ($Sources.Count -eq 0) {
        Write-Host ""
        Write-Host "  [!] No remote sources configured" -ForegroundColor Yellow
        Write-Host "  [i] Add URLs to config.json -> remoteHostSources" -ForegroundColor DarkGray
        return $null
    }

    Write-Host ""
    Write-Host "  === Fetching remote hosts ===" -ForegroundColor Cyan

    $allDomains = @{}
    $successCount = 0
    $failedSources = @()

    foreach ($source in $Sources) {
        $shortUrl = if ($source.Length -gt 50) { $source.Substring(0, 50) + "..." } else { $source }
        Write-Host "  $shortUrl " -NoNewline

        $fetchSuccess = $false
        $ipCount = 0

        for ($attempt = 0; $attempt -le $RetryCount; $attempt++) {
            try {
                $response = Invoke-WebRequest -Uri $source -UseBasicParsing -TimeoutSec 30
                $content = $response.Content

                $lines = $content -split "`n"
                foreach ($line in $lines) {
                    $trimmedLine = $line.Trim()
                    if ($trimmedLine -eq '' -or $trimmedLine.StartsWith('#')) { continue }

                    $parts = $trimmedLine -split '\s+', 2
                    if ($parts.Count -eq 2) {
                        $ip = $parts[0].Trim()
                        $domain = $parts[1].Trim()

                        if (-not $allDomains.ContainsKey($domain)) {
                            $allDomains[$domain] = @()
                        }

                        if ($allDomains[$domain] -notcontains $ip) {
                            $allDomains[$domain] += $ip
                            $ipCount++
                        }
                    }
                }
                Write-Host "[OK] +$ipCount IPs" -ForegroundColor Green
                $successCount++
                $fetchSuccess = $true
                break
            } catch {
                if ($attempt -lt $RetryCount) {
                    Start-Sleep -Milliseconds 500
                }
            }
        }

        if (-not $fetchSuccess) {
            Write-Host "[FAILED]" -ForegroundColor Red
            $failedSources += $source
            $Global:Stats.FailedSources += $source
        }
    }

    if ($successCount -eq 0) {
        Write-Host ""
        Write-Host "  [X] All sources failed!" -ForegroundColor Red
        return $null
    }

    if ($failedSources.Count -gt 0) {
        Write-Host ""
        Write-Host "  [!] Failed sources ($($failedSources.Count)):" -ForegroundColor Yellow
        foreach ($src in $failedSources) {
            Write-Host "      - $src" -ForegroundColor Red
        }
    }

    $fullPath = if ([System.IO.Path]::IsPathRooted($FilePath)) { $FilePath } else { Join-Path $ScriptDir $FilePath }

    $poolData = @{
        lastUpdated = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
        domains = $allDomains
    }

    $poolData | ConvertTo-Json -Depth 10 | Out-File -FilePath $fullPath -Encoding UTF8
    Write-Host ""
    Write-Host "  [+] Backup pool: $($allDomains.Count) domains" -ForegroundColor Green

    $Global:Stats.BackupPoolUpdated = $true

    return $poolData
}
