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

# ============================================================
# Config functions
# ============================================================
function Get-Config {
    $configPath = Join-Path $ScriptDir 'config.json'
    
    $defaultConfig = @{
        mainHostFile = 'my-github-hosts.txt'
        systemHostsPath = 'C:\Windows\System32\drivers\etc\hosts'
        backupPoolFile = 'backup-pool.json'
        remoteHostSources = @()
        testTimeoutMs = 1000
        retryCount = 1
        remoteSourceRetryCount = 2
        apiRetryCount = 3
        autoBackup = $true
    }
    
    if (-not (Test-Path $configPath)) {
        $defaultConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $configPath -Encoding UTF8
        Write-Host ""
        Write-Host "  [!] 配置文件已创建: $configPath" -ForegroundColor Yellow
        Write-Host "  [i] 请在 config.json 中配置 remoteHostSources" -ForegroundColor Gray
        Write-Host ""
    }
    
    try {
        $jsonContent = Get-Content -Path $configPath -Raw -Encoding UTF8
        $config = $jsonContent | ConvertFrom-Json
        
        foreach ($key in $defaultConfig.Keys) {
            if (-not $config.PSObject.Properties.Match($key)) {
                $config | Add-Member -MemberType NoteProperty -Name $key -Value $defaultConfig[$key]
            }
        }
        
        return $config
    } catch {
        return $defaultConfig
    }
}

# ============================================================
# Admin functions
# ============================================================
function Test-AdminPrivilege {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-AdminPrivilege {
    param([string]$ScriptPath)
    
    try {
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
        Start-Process powershell -ArgumentList $arguments -Verb RunAs -Wait
        return $true
    } catch {
        return $false
    }
}

# ============================================================
# IP Speed Test functions
# ============================================================
function Test-IPSpeed {
    param(
        [Parameter(Mandatory=$true)]
        [string]$IP,
        [int]$TimeoutMs = 1000,
        [int]$RetryCount = 1
    )
    
    for ($attempt = 0; $attempt -le $RetryCount; $attempt++) {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        try {
            $asyncResult = $tcp.BeginConnect($IP, 443, $null, $null)
            $success = $asyncResult.AsyncWaitHandle.WaitOne($TimeoutMs)
            
            if ($success) {
                $tcp.EndConnect($asyncResult)
                $stopwatch.Stop()
                $tcp.Close()
                return @{ Success = $true; Latency = $stopwatch.ElapsedMilliseconds }
            }
        } catch {}
        finally {
            if ($tcp.Connected) { $tcp.Close() }
            $stopwatch.Stop()
        }
        
        if ($attempt -lt $RetryCount) { Start-Sleep -Milliseconds 100 }
    }
    
    return @{ Success = $false; Latency = -1 }
}

function Select-BestIP {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$IPs,
        [int]$TimeoutMs = 1000,
        [int]$RetryCount = 1
    )
    
    $results = @()
    
    foreach ($ip in $IPs) {
        $testResult = Test-IPSpeed -IP $ip -TimeoutMs $TimeoutMs -RetryCount $RetryCount
        if ($testResult.Success) {
            $results += @{ IP = $ip; Latency = $testResult.Latency }
        }
    }
    
    if ($results.Count -eq 0) { return $null }
    
    return $results | Sort-Object Latency | Select-Object -First 1
}

# ============================================================
# Host file functions
# ============================================================
function Read-MainHostFile {
    param([Parameter(Mandatory=$true)][string]$FilePath)
    
    $fullPath = if ([System.IO.Path]::IsPathRooted($FilePath)) { $FilePath } else { Join-Path $ScriptDir $FilePath }
    
    if (-not (Test-Path $fullPath)) {
        $defaultContent = "# GitHub Hosts`n140.82.121.3 github.com"
        $defaultContent | Out-File -FilePath $fullPath -Encoding UTF8
        Write-Host "  [!] 已创建默认 hosts 文件" -ForegroundColor Yellow
        return @{}
    }
    
    $hosts = @{}
    $content = Get-Content -Path $fullPath -Encoding UTF8
    
    foreach ($line in $content) {
        $trimmedLine = $line.Trim()
        if ($trimmedLine -eq '' -or $trimmedLine.StartsWith('#')) { continue }
        
        $parts = $trimmedLine -split '\s+', 2
        if ($parts.Count -eq 2) {
            $hosts[$parts[1].Trim()] = $parts[0].Trim()
        }
    }
    
    return $hosts
}

# ============================================================
# Backup pool functions
# ============================================================
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
    Write-Host "  === 正在获取远程 hosts 源 ===" -ForegroundColor Cyan

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
            Write-Host "[失败]" -ForegroundColor Red
            $failedSources += $source
            $Global:Stats.FailedSources += $source
        }
    }

    if ($successCount -eq 0) {
        Write-Host ""
        Write-Host "  [X] 所有源获取失败！请检查网络或更新 config.json" -ForegroundColor Red
        return $null
    }

    if ($failedSources.Count -gt 0) {
        Write-Host ""
        Write-Host "  [!] 失败的源 ($($failedSources.Count)):" -ForegroundColor Yellow
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
    Write-Host "  [+] 备份池: $($allDomains.Count) 个域名" -ForegroundColor Green

    $Global:Stats.BackupPoolUpdated = $true

    return $poolData
}

# ============================================================
# DNS API functions
# ============================================================
function Get-IPFromIpApi {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Domain
    )

    try {
        $url = "https://ip-api.com/json/" + $Domain + "?fields=query,status,message"
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
        $json = $response.Content | ConvertFrom-Json

        if ($json.status -eq "success") {
            return @($json.query)
        }
    } catch {}

    return @()
}

function Get-IPFromDnsGoogle {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Domain
    )

    try {
        $query = "name=" + $Domain + "%26type=A"
        $url = "https://dns.google/resolve?" + $query
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
        $json = $response.Content | ConvertFrom-Json

        $ips = @()
        if ($json.Answer) {
            foreach ($answer in $json.Answer) {
                if ($answer.type -eq 1) {
                    $ips += $answer.data
                }
            }
        }
        return $ips
    } catch {}

    return @()
}

function Get-IPFromDnsCloudflare {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Domain
    )

    try {
        $query = "name=" + $Domain + "%26type=A"
        $url = "https://cloudflare-dns.com/dns-query?" + $query
        $headers = @{"accept" = "application/dns-json"}
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10 -Headers $headers
        $json = $response.Content | ConvertFrom-Json

        $ips = @()
        if ($json.Answer) {
            foreach ($answer in $json.Answer) {
                if ($answer.type -eq 1) {
                    $ips += $answer.data
                }
            }
        }
        return $ips
    } catch {}

    return @()
}

function Get-IPsFromMultipleSources {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Domain
    )

    $allIPs = @()

    $ipApiResult = Get-IPFromIpApi -Domain $Domain
    $allIPs += $ipApiResult

    $dnsGoogleResult = Get-IPFromDnsGoogle -Domain $Domain
    $allIPs += $dnsGoogleResult

    $dnsCloudflareResult = Get-IPFromDnsCloudflare -Domain $Domain
    $allIPs += $dnsCloudflareResult

    return @($allIPs | Select-Object -Unique)
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$ScriptBlock,
        [int]$MaxRetries = 3,
        [int]$DelayMs = 1000
    )

    $attempt = 0
    $lastError = $null

    while ($attempt -lt $MaxRetries) {
        try {
            $result = & $ScriptBlock
            return $result
        } catch {
            $lastError = $_
            $attempt++
            if ($attempt -lt $MaxRetries) {
                Start-Sleep -Milliseconds $DelayMs
            }
        }
    }

    throw $lastError
}

function Test-IsGitHubDomain {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Domain
    )

    $githubDomains = @(
        "github.com",
        "github.global.ssl.fastly.net",
        "githubusercontent.com",
        "github.io",
        "githubapp.com"
    )

    foreach ($githubDomain in $githubDomains) {
        if ($Domain -eq $githubDomain -or $Domain.EndsWith(".$githubDomain")) {
            return $true
        }
    }

    return $false
}

function Get-IPsFromDnsApi {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Domain,
        [string[]]$Apis
    )
    
    if ($Apis.Count -eq 0) { return @() }
    
    $ips = @()
    
    foreach ($api in $Apis) {
        try {
            $url = $api -replace '\{domain\}', $Domain
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
            $content = $response.Content
            
            try {
                $json = $content | ConvertFrom-Json
                
                if ($json.Answer) {
                    foreach ($answer in $json.Answer) {
                        if ($answer.data) { $ips += $answer.data }
                    }
                } elseif ($json.ip) {
                    $ips += $json.ip
                } elseif ($json.A) {
                    $ips += $json.A
                }
            } catch {
                $ipMatches = [regex]::Matches($content, '\b(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\b')
                foreach ($match in $ipMatches) {
                    $ips += $match.Groups[1].Value
                }
            }
        } catch {
            if ($Global:Stats.FailedApis -notcontains $api) {
                $Global:Stats.FailedApis += $api
            }
        }
    }
    
    return @($ips | Select-Object -Unique)
}

# ============================================================
# Domain optimization
# ============================================================
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

    # 层级 1: 测试原始 IP
    $domainDisplay = $Domain.PadRight(42)
    Write-Host "  $domainDisplay" -NoNewline

    $result = Test-IPSpeed -IP $OriginalIP -TimeoutMs $timeout -RetryCount $retry

    if ($result.Success) {
        $latencyStr = "$($result.Latency)ms".PadLeft(6)
        Write-Host "[正常] " -ForegroundColor Green -NoNewline
        Write-Host $latencyStr -ForegroundColor DarkGray
        $Global:Stats.NormalCount++
        return @{ Domain = $Domain; Status = 'Normal'; IP = $OriginalIP; Latency = $result.Latency; OldIP = $null }
    }

    Write-Host "[--] 检测中..." -ForegroundColor Yellow

    # 层级 2: 本地备份池
    $candidateIPs = @()
    if ($BackupPool.domains.ContainsKey($Domain)) {
        $candidateIPs = @($BackupPool.domains[$Domain])
    }

    if ($candidateIPs.Count -gt 0) {
        $bestIP = Select-BestIP -IPs $candidateIPs -TimeoutMs $timeout -RetryCount $retry

        if ($bestIP) {
            Write-Host "  ".PadRight(44) -NoNewline
            Write-Host "[替换] " -ForegroundColor Yellow -NoNewline
            Write-Host "$($bestIP.IP) ($($bestIP.Latency)ms)" -ForegroundColor Cyan
            $Global:Stats.ReplacedCount++
            return @{ Domain = $Domain; Status = 'Replaced'; IP = $bestIP.IP; Latency = $bestIP.Latency; OldIP = $OriginalIP }
        }
    }

    # 层级 3: 更新备份池
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
                        Write-Host "[替换] " -ForegroundColor Yellow -NoNewline
                        Write-Host "$($bestIP.IP) ($($bestIP.Latency)ms)" -ForegroundColor Cyan
                        $Global:Stats.ReplacedCount++
                        return @{ Domain = $Domain; Status = 'Replaced'; IP = $bestIP.IP; Latency = $bestIP.Latency; OldIP = $OriginalIP }
                    }
                }
            }
        }
    }

    # 层级 4: 第三方 DNS API
    $apiIPs = Get-IPsFromMultipleSources -Domain $Domain

    if ($apiIPs.Count -gt 0) {
        $bestIP = Select-BestIP -IPs $apiIPs -TimeoutMs $timeout -RetryCount $retry

        if ($bestIP) {
            Write-Host "  ".PadRight(44) -NoNewline
            Write-Host "[替换] " -ForegroundColor Yellow -NoNewline
            Write-Host "$($bestIP.IP) ($($bestIP.Latency)ms) [API]" -ForegroundColor Cyan
            $Global:Stats.ReplacedCount++
            return @{ Domain = $Domain; Status = 'Replaced'; IP = $bestIP.IP; Latency = $bestIP.Latency; OldIP = $OriginalIP }
        }
    }

    # 所有层级都失败
    Write-Host "  ".PadRight(44) -NoNewline
    Write-Host "[失败] " -ForegroundColor Red -NoNewline
    Write-Host "无可用 IP" -ForegroundColor DarkGray
    $Global:Stats.FailedCount++

    return @{ Domain = $Domain; Status = 'Failed'; IP = $OriginalIP; Latency = -1; OldIP = $null }
}

# ============================================================
# Update functions
# ============================================================
function Update-MainHostFile {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][array]$Results
    )

    $fullPath = if ([System.IO.Path]::IsPathRooted($FilePath)) { $FilePath } else { Join-Path $ScriptDir $FilePath }

    $ipMap = @{}
    foreach ($result in $Results) {
        if ($result.Status -eq 'Replaced') {
            if (-not $ipMap.ContainsKey($result.Domain)) {
                $ipMap[$result.Domain] = $result.IP
            }
        }
    }

    if ($ipMap.Count -eq 0) {
        return
    }

    $content = Get-Content -Path $fullPath -Encoding UTF8
    $newContent = @()
    $processedDomains = @{}

    foreach ($line in $content) {
        $trimmedLine = $line.Trim()

        if ($trimmedLine -eq '' -or $trimmedLine.StartsWith('#')) {
            $newContent += $line
            continue
        }

        $parts = $trimmedLine -split '\s+', 2
        if ($parts.Count -eq 2) {
            $domain = $parts[1].Trim()

            if ($ipMap.ContainsKey($domain) -and -not $processedDomains.ContainsKey($domain)) {
                $newContent += "$($ipMap[$domain]) $domain"
                $processedDomains[$domain] = $true
            } else {
                $newContent += $line
                $processedDomains[$domain] = $true
            }
        } else {
            $newContent += $line
        }
    }

    $newDomains = $ipMap.Keys | Where-Object { -not $processedDomains.ContainsKey($_) }
    if ($newDomains) {
        $newContent += ""
        $newContent += "# GitHub Hosts Updated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        foreach ($domain in $newDomains) {
            $newContent += "$($ipMap[$domain]) $domain"
        }
    }

    $newContent | Out-File -FilePath $fullPath -Encoding UTF8
}

function Backup-SystemHosts {
    param([Parameter(Mandatory=$true)][string]$HostsPath)
    
    $backupDir = Join-Path $ScriptDir 'hosts-backup'
    
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupFile = Join-Path $backupDir "hosts_$timestamp"
    
    try {
        Copy-Item -Path $HostsPath -Destination $backupFile -Force
        return $true
    } catch {
        return $false
    }
}

function Update-SystemHosts {
    param(
        [Parameter(Mandatory=$true)][string]$HostsPath,
        [Parameter(Mandatory=$true)][array]$Results,
        [bool]$AutoBackup = $true
    )

    if (-not (Test-AdminPrivilege)) {
        return $false
    }

    $ipMap = @{}
    foreach ($result in $Results) {
        if (-not $ipMap.ContainsKey($result.Domain)) {
            $ipMap[$result.Domain] = $result.IP
        }
    }

    if ($ipMap.Count -eq 0) {
        return $true
    }

    if ($AutoBackup) { Backup-SystemHosts -HostsPath $HostsPath | Out-Null }

    $content = Get-Content -Path $HostsPath -Encoding UTF8
    $newContent = @()
    $existingDomains = @{}

    foreach ($line in $content) {
        $trimmedLine = $line.Trim()

        if ($trimmedLine -eq '' -or $trimmedLine.StartsWith('#')) {
            $newContent += $line
            continue
        }

        $parts = $trimmedLine -split '\s+', 2
        if ($parts.Count -eq 2) {
            $domain = $parts[1].Trim()
            $existingDomains[$domain] = $true

            if ($ipMap.ContainsKey($domain)) {
                $newContent += "$($ipMap[$domain]) $domain"
            } else {
                $newContent += $line
            }
        } else {
            $newContent += $line
        }
    }

    $newDomains = $ipMap.Keys | Where-Object { -not $existingDomains.ContainsKey($_) }
    if ($newDomains) {
        $newContent += ""
        $newContent += "# GitHub Hosts $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        foreach ($domain in $newDomains) {
            $newContent += "$($ipMap[$domain]) $domain"
        }
    }

    try {
        $newContent | Out-File -FilePath $HostsPath -Encoding UTF8
        $Global:Stats.SystemHostsWritten = $true
        return $true
    } catch {
        return $false
    }
}

# ============================================================
# Report
# ============================================================
function Show-ExecutionReport {
    param([Parameter(Mandatory=$true)][array]$Results)

    $total = $Global:Stats.TotalDomains
    $normal = $Global:Stats.NormalCount
    $replaced = $Global:Stats.ReplacedCount
    $failed = $Global:Stats.FailedCount
    $availableRate = if ($total -gt 0) { [math]::Round(($total - $failed) / $total * 100, 1) } else { 0 }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "               执行摘要                  " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    Write-Host "  域名总数:    $total" -ForegroundColor White
    Write-Host "  正常:        $normal" -ForegroundColor Green
    Write-Host "  已替换:      $replaced" -ForegroundColor Yellow
    Write-Host "  失败:        $failed" -ForegroundColor Red
    Write-Host "  可用率:      $availableRate%" -ForegroundColor $(if ($availableRate -ge 90) { 'Green' } elseif ($availableRate -ge 70) { 'Yellow' } else { 'Red' })

    Write-Host "----------------------------------------" -ForegroundColor DarkGray
    Write-Host "  备份池:      $(if ($Global:Stats.BackupPoolUpdated) { '已更新' } else { '已跳过' })"
    Write-Host "  系统 hosts:  $(if ($Global:Stats.SystemHostsWritten) { '已更新' } else { '已跳过' })"
    
    # Show failed sources
    if ($Global:Stats.FailedSources.Count -gt 0) {
        Write-Host ""
        Write-Host "  [!] 失败的 hosts 源:" -ForegroundColor Yellow
        foreach ($src in $Global:Stats.FailedSources) {
            Write-Host "      - $src" -ForegroundColor Red
        }
    }

    # Show failed APIs
    if ($Global:Stats.FailedApis.Count -gt 0) {
        Write-Host ""
        Write-Host "  [!] 失败的 DNS API:" -ForegroundColor Yellow
        foreach ($api in $Global:Stats.FailedApis) {
            Write-Host "      - $api" -ForegroundColor Red
        }
    }

    # Show failed domains
    if ($failed -gt 0) {
        Write-Host ""
        Write-Host "  [!] 失败的域名:" -ForegroundColor Yellow
        foreach ($result in $Results) {
            if ($result.Status -eq 'Failed') {
                Write-Host "      - $($result.Domain)" -ForegroundColor Red
            }
        }
    }
    
    Write-Host "========================================" -ForegroundColor Cyan
}

# ============================================================
# Main
# ============================================================
function Invoke-MainProcess {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "       GitHub Host Optimizer v1.0       " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $hasAdmin = Test-AdminPrivilege

    if (-not $hasAdmin) {
        Write-Host "  [!] 当前无管理员权限，尝试申请..." -ForegroundColor Yellow
        
        $scriptPath = $MyInvocation.ScriptName
        if (-not $scriptPath) { $scriptPath = $PSCommandPath }
        
        $elevated = Request-AdminPrivilege -ScriptPath $scriptPath
        
        if ($elevated) {
            Write-Host "  [+] 已获取管理员权限，正在继续..." -ForegroundColor Green
            $hasAdmin = $true
        } else {
            Write-Host "  [!] 管理员权限申请被拒绝，将以用户模式运行" -ForegroundColor Yellow
            Write-Host "  [i] 不会更新系统 hosts 文件" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  [+] 已获取管理员权限" -ForegroundColor Green
    }

    $config = Get-Config

    Write-Host ""
    Write-Host "  === 正在加载 Hosts ===" -ForegroundColor Cyan

    $mainHosts = Read-MainHostFile -FilePath $config.mainHostFile

    if ($mainHosts.Count -eq 0) {
        Write-Host "  [X] 未找到 hosts 记录！" -ForegroundColor Red
        return
    }

    $Global:Stats.TotalDomains = $mainHosts.Count
    Write-Host "  [+] 已找到 $($mainHosts.Count) 个域名" -ForegroundColor Green

    $backupPool = Get-BackupPool -FilePath $config.backupPoolFile
    $backupPoolUpdated = $false

    Write-Host ""
    Write-Host "  === 正在测试域名 ===" -ForegroundColor Cyan

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
    Write-Host "  === 正在更新文件 ===" -ForegroundColor Cyan

    Update-MainHostFile -FilePath $config.mainHostFile -Results $Global:DomainResults
    Write-Host "  [+] my-github-hosts.txt 已更新" -ForegroundColor Green

    if ($hasAdmin) {
        Update-SystemHosts -HostsPath $config.systemHostsPath -Results $Global:DomainResults -AutoBackup $config.autoBackup
        if ($Global:Stats.SystemHostsWritten) {
            Write-Host "  [+] 系统 hosts 已更新" -ForegroundColor Green
        }
    }

    Show-ExecutionReport -Results $Global:DomainResults
}

# Entry point
Invoke-MainProcess

Write-Host ""
Write-Host "按任意键退出..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
