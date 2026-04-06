# GitHub Host 智能优选工具 - 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建 Windows PowerShell 自动化工具，实现 GitHub Host 智能检测、IP 测速优选、多层兜底防护，自动更新系统 hosts 文件。

**Architecture:** 单文件 PowerShell 脚本，模块化函数组织。四层优选流程（主IP → 本地备用池 → 远程备用池 → 第三方API）。JSON 配置文件管理，智能更新系统 hosts（只替换 GitHub 域名，保留其他内容）。

**Tech Stack:** PowerShell 5.1+, TCP Socket 测速, JSON 配置, curl 远程拉取

---

## 文件结构

```
github-host/
├── GitHub-Host-Optimizer.ps1    # 主脚本（单文件，模块化函数组织）
├── config.json                   # 用户配置文件
├── my-github-hosts.txt           # 主 Host 文件（用户维护）
├── backup-pool.json              # 备用 IP 池缓存（自动生成）
└── 一键运行.bat                   # 管理员启动快捷方式
```

---

### Task 1: 创建配置文件模板

**Files:**
- Create: `config.json`

- [ ] **Step 1: 创建空配置文件模板**

```json
{
  "mainHostFile": "my-github-hosts.txt",
  "systemHostsPath": "C:\\Windows\\System32\\drivers\\etc\\hosts",
  "backupPoolFile": "backup-pool.json",
  "remoteHostSources": [],
  "thirdPartyDnsApis": [],
  "testTimeoutMs": 1000,
  "retryCount": 1,
  "autoBackup": true
}
```

---

### Task 2: 创建主 Host 文件模板

**Files:**
- Create: `my-github-hosts.txt`

- [ ] **Step 1: 创建主 Host 文件**

```
# GitHub Hosts - 用户维护
# 格式: IP 域名

140.82.113.26 alive.github.com
140.82.114.25 live.github.com
185.199.109.154 github.githubassets.com
140.82.113.21 central.github.com
185.199.108.133 desktop.githubusercontent.com
185.199.110.133 camo.githubusercontent.com
185.199.111.133 github.map.fastly.net
146.75.121.194 github.global.ssl.fastly.net
140.82.121.4 gist.github.com
185.199.111.153 github.io
140.82.121.3 github.com
192.0.66.2 github.blog
140.82.121.5 api.github.com
185.199.109.133 raw.githubusercontent.com
185.199.110.133 user-images.githubusercontent.com
185.199.110.133 favicons.githubusercontent.com
185.199.111.133 avatars5.githubusercontent.com
185.199.110.133 avatars4.githubusercontent.com
185.199.110.133 avatars3.githubusercontent.com
185.199.108.133 avatars2.githubusercontent.com
185.199.110.133 avatars1.githubusercontent.com
185.199.110.133 avatars0.githubusercontent.com
185.199.109.133 avatars.githubusercontent.com
140.82.121.10 codeload.github.com
3.5.24.249 github-cloud.s3.amazonaws.com
52.217.131.105 github-com.s3.amazonaws.com
16.182.39.25 github-production-release-asset-2e65be.s3.amazonaws.com
16.15.253.166 github-production-user-asset-6210df.s3.amazonaws.com
54.231.204.81 github-production-repository-file-5c1aeb.s3.amazonaws.com
185.199.108.153 githubstatus.com
140.82.113.17 github.community
51.137.3.17 github.dev
140.82.113.21 collector.github.com
13.107.42.16 pipelines.actions.githubusercontent.com
185.199.111.133 media.githubusercontent.com
185.199.110.133 cloud.githubusercontent.com
185.199.110.133 objects.githubusercontent.com
```

---

### Task 3: 创建一键运行批处理文件

**Files:**
- Create: `一键运行.bat`

- [ ] **Step 1: 创建管理员启动批处理文件**

```batch
@echo off
:: GitHub Host 智能优选工具 - 一键运行
:: 自动以管理员身份运行 PowerShell 脚本

cd /d "%~dp0"
powershell -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0GitHub-Host-Optimizer.ps1\"' -Verb RunAs"
```

---

### Task 4: 创建主脚本 - 基础结构与配置加载

**Files:**
- Create: `GitHub-Host-Optimizer.ps1`

- [ ] **Step 1: 创建脚本头部和全局变量**

```powershell
<#
.SYNOPSIS
    GitHub Host 智能优选工具
.DESCRIPTION
    自动检测 GitHub Host 连通性，测速优选最优 IP，多层兜底防护，智能更新系统 hosts
.NOTES
    作者: GitHub Host Optimizer
    版本: 1.0.0
    运行环境: PowerShell 5.1+
    权限要求: 管理员身份（可选）
#>

# 获取脚本所在目录
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# 全局统计
$Global:Stats = @{
    TotalDomains    = 0
    NormalCount     = 0
    ReplacedCount   = 0
    FailedCount     = 0
    BackupPoolUpdated = $false
    SystemHostsWritten = $false
}

# 域名检测结果存储
$Global:DomainResults = @()
```

- [ ] **Step 2: 实现 Write-Log 函数**

```powershell
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info',
        
        [switch]$NoNewLine
    )
    
    $prefix = switch ($Level) {
        'Info'    { '[信息]' }
        'Warning' { '[警告]' }
        'Error'   { '[错误]' }
        'Success' { '[成功]' }
    }
    
    $color = switch ($Level) {
        'Info'    { 'White' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        'Success' { 'Green' }
    }
    
    if ($NoNewLine) {
        Write-Host "$prefix $Message" -ForegroundColor $color -NoNewline
    } else {
        Write-Host "$prefix $Message" -ForegroundColor $color
    }
}
```

- [ ] **Step 3: 实现 Get-Config 函数**

```powershell
function Get-Config {
    $configPath = Join-Path $ScriptDir 'config.json'
    
    $defaultConfig = @{
        mainHostFile = 'my-github-hosts.txt'
        systemHostsPath = 'C:\Windows\System32\drivers\etc\hosts'
        backupPoolFile = 'backup-pool.json'
        remoteHostSources = @()
        thirdPartyDnsApis = @()
        testTimeoutMs = 1000
        retryCount = 1
        autoBackup = $true
    }
    
    if (-not (Test-Path $configPath)) {
        $defaultConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $configPath -Encoding UTF8
        Write-Log "配置文件已创建: $configPath" -Level Warning
        Write-Log "请补充以下配置项:" -Level Warning
        Write-Log "  - remoteHostSources: 远程备用 Host 源 URL 列表" -Level Warning
        Write-Log "  - thirdPartyDnsApis: 第三方 IP 查询 API 列表（可选）" -Level Warning
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
        Write-Log "配置文件解析失败，使用默认配置: $_" -Level Error
        return $defaultConfig
    }
}
```

---

### Task 5: 实现管理员权限检查与申请

**Files:**
- Modify: `GitHub-Host-Optimizer.ps1`

- [ ] **Step 1: 实现 Test-AdminPrivilege 函数**

```powershell
function Test-AdminPrivilege {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
```

- [ ] **Step 2: 实现 Request-AdminPrivilege 函数**

```powershell
function Request-AdminPrivilege {
    param([string]$ScriptPath)
    
    try {
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
        Start-Process powershell -ArgumentList $arguments -Verb RunAs -Wait
        return $true
    } catch {
        Write-Log "管理员权限申请被拒绝或失败: $_" -Level Warning
        return $false
    }
}
```

---

### Task 6: 实现 IP 测速功能

**Files:**
- Modify: `GitHub-Host-Optimizer.ps1`

- [ ] **Step 1: 实现 Test-IPSpeed 函数**

```powershell
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
        } catch {
        } finally {
            if ($tcp.Connected) { $tcp.Close() }
            $stopwatch.Stop()
        }
        
        if ($attempt -lt $RetryCount) { Start-Sleep -Milliseconds 100 }
    }
    
    return @{ Success = $false; Latency = -1 }
}
```

- [ ] **Step 2: 实现 Select-BestIP 函数**

```powershell
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
```

---

### Task 7: 实现主 Host 文件解析

**Files:**
- Modify: `GitHub-Host-Optimizer.ps1`

- [ ] **Step 1: 实现 Read-MainHostFile 函数**

```powershell
function Read-MainHostFile {
    param([Parameter(Mandatory=$true)][string]$FilePath)
    
    $fullPath = if ([System.IO.Path]::IsPathRooted($FilePath)) { $FilePath } else { Join-Path $ScriptDir $FilePath }
    
    if (-not (Test-Path $fullPath)) {
        Write-Log "主 Host 文件不存在: $fullPath" -Level Warning
        $defaultContent = "# GitHub Hosts - 用户维护`n# 格式: IP 域名`n`n140.82.121.3 github.com`n140.82.121.5 api.github.com"
        $defaultContent | Out-File -FilePath $fullPath -Encoding UTF8
        Write-Log "默认模板已创建，请补充域名配置" -Level Warning
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
```

---

### Task 8: 实现备用池管理

**Files:**
- Modify: `GitHub-Host-Optimizer.ps1`

- [ ] **Step 1: 实现 Get-BackupPool 函数**

```powershell
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
        Write-Log "备用池缓存解析失败: $_" -Level Warning
        return @{ lastUpdated = $null; domains = @{} }
    }
}
```

- [ ] **Step 2: 实现 Update-BackupPool 函数**

```powershell
function Update-BackupPool {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Sources,
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    
    if ($Sources.Count -eq 0) {
        Write-Log "未配置远程 Host 源，跳过备用池更新" -Level Warning
        return $null
    }
    
    Write-Log "正在更新备用池..." -Level Info
    
    $allDomains = @{}
    $successCount = 0
    
    foreach ($source in $Sources) {
        try {
            Write-Log "拉取: $source" -Level Info
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
                    }
                }
            }
            $successCount++
        } catch {
            Write-Log "拉取失败: $source - $_" -Level Warning
        }
    }
    
    if ($successCount -eq 0) {
        Write-Log "所有远程源均拉取失败" -Level Error
        return $null
    }
    
    $fullPath = if ([System.IO.Path]::IsPathRooted($FilePath)) { $FilePath } else { Join-Path $ScriptDir $FilePath }
    
    $poolData = @{
        lastUpdated = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
        domains = $allDomains
    }
    
    $poolData | ConvertTo-Json -Depth 10 | Out-File -FilePath $fullPath -Encoding UTF8
    Write-Log "备用池已更新，共 $($allDomains.Count) 个域名" -Level Success
    
    $Global:Stats.BackupPoolUpdated = $true
    
    return $poolData
}
```

---

### Task 9: 实现第三方 DNS API 查询

**Files:**
- Modify: `GitHub-Host-Optimizer.ps1`

- [ ] **Step 1: 实现 Get-IPsFromDnsApi 函数**

```powershell
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
            
            Write-Log "调用 API: $url" -Level Info
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
            Write-Log "API 调用失败: $api - $_" -Level Warning
        }
    }
    
    return @($ips | Select-Object -Unique)
}
```

---

### Task 10: 实现四层优选流程

**Files:**
- Modify: `GitHub-Host-Optimizer.ps1`

- [ ] **Step 1: 实现 Invoke-DomainOptimization 函数**

```powershell
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
    
    # 第一层：主 IP 测速
    Write-Log "检测: $Domain ($OriginalIP)..." -Level Info -NoNewLine
    
    $result = Test-IPSpeed -IP $OriginalIP -TimeoutMs $timeout -RetryCount $retry
    
    if ($result.Success) {
        Write-Host " 正常 ($($result.Latency)ms)" -ForegroundColor Green
        $Global:Stats.NormalCount++
        return @{ Domain = $Domain; Status = 'Normal'; IP = $OriginalIP; Latency = $result.Latency; OldIP = $null }
    }
    
    Write-Host " 失效" -ForegroundColor Red
    
    # 第二层：本地备用池优选
    $candidateIPs = @()
    if ($BackupPool.domains.ContainsKey($Domain)) {
        $candidateIPs = @($BackupPool.domains[$Domain])
    }
    
    if ($candidateIPs.Count -gt 0) {
        Write-Log "备用池: $Domain 找到 $($candidateIPs.Count) 个候选 IP" -Level Info
        $bestIP = Select-BestIP -IPs $candidateIPs -TimeoutMs $timeout -RetryCount $retry
        
        if ($bestIP) {
            Write-Log "替换: $Domain ($OriginalIP -> $($bestIP.IP))" -Level Success
            $Global:Stats.ReplacedCount++
            return @{ Domain = $Domain; Status = 'Replaced'; IP = $bestIP.IP; Latency = $bestIP.Latency; OldIP = $OriginalIP }
        }
    }
    
    # 第三层：更新备用池 + 重试
    if (-not $BackupPoolUpdated.Value) {
        $newPool = Update-BackupPool -Sources $Config.remoteHostSources -FilePath $Config.backupPoolFile
        if ($newPool) {
            $BackupPoolUpdated.Value = $true
            $BackupPool = $newPool
            
            if ($BackupPool.domains.ContainsKey($Domain)) {
                $candidateIPs = @($BackupPool.domains[$Domain])
                
                if ($candidateIPs.Count -gt 0) {
                    $bestIP = Select-BestIP -IPs $candidateIPs -TimeoutMs $timeout -RetryCount $retry
                    
                    if ($bestIP) {
                        Write-Log "替换: $Domain ($OriginalIP -> $($bestIP.IP))" -Level Success
                        $Global:Stats.ReplacedCount++
                        return @{ Domain = $Domain; Status = 'Replaced'; IP = $bestIP.IP; Latency = $bestIP.Latency; OldIP = $OriginalIP }
                    }
                }
            }
        }
    }
    
    # 第四层：第三方 API 兜底
    if ($Config.thirdPartyDnsApis.Count -gt 0) {
        Write-Log "第三方 API 兜底: $Domain" -Level Info
        $apiIPs = Get-IPsFromDnsApi -Domain $Domain -Apis $Config.thirdPartyDnsApis
        
        if ($apiIPs.Count -gt 0) {
            $bestIP = Select-BestIP -IPs $apiIPs -TimeoutMs $timeout -RetryCount $retry
            
            if ($bestIP) {
                Write-Log "替换: $Domain ($OriginalIP -> $($bestIP.IP))" -Level Success
                $Global:Stats.ReplacedCount++
                return @{ Domain = $Domain; Status = 'Replaced'; IP = $bestIP.IP; Latency = $bestIP.Latency; OldIP = $OriginalIP }
            }
        }
    }
    
    # 所有层级全失效
    Write-Log "无可用 IP: $Domain" -Level Error
    $Global:Stats.FailedCount++
    
    return @{ Domain = $Domain; Status = 'Failed'; IP = $OriginalIP; Latency = -1; OldIP = $null }
}
```

---

### Task 11: 实现主 Host 文件更新

**Files:**
- Modify: `GitHub-Host-Optimizer.ps1`

- [ ] **Step 1: 实现 Update-MainHostFile 函数**

```powershell
function Update-MainHostFile {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][array]$Results
    )
    
    $fullPath = if ([System.IO.Path]::IsPathRooted($FilePath)) { $FilePath } else { Join-Path $ScriptDir $FilePath }
    
    $ipMap = @{}
    foreach ($result in $Results) {
        if ($result.Status -eq 'Replaced') {
            $ipMap[$result.Domain] = $result.IP
        }
    }
    
    if ($ipMap.Count -eq 0) {
        Write-Log "主 Host 文件无需更新" -Level Info
        return
    }
    
    $content = Get-Content -Path $fullPath -Encoding UTF8
    $newContent = @()
    
    foreach ($line in $content) {
        $trimmedLine = $line.Trim()
        
        if ($trimmedLine -eq '' -or $trimmedLine.StartsWith('#')) {
            $newContent += $line
            continue
        }
        
        $parts = $trimmedLine -split '\s+', 2
        if ($parts.Count -eq 2) {
            $domain = $parts[1].Trim()
            
            if ($ipMap.ContainsKey($domain)) {
                $newContent += "$($ipMap[$domain]) $domain"
            } else {
                $newContent += $line
            }
        } else {
            $newContent += $line
        }
    }
    
    $newContent | Out-File -FilePath $fullPath -Encoding UTF8
    Write-Log "主 Host 文件已更新" -Level Success
}
```

---

### Task 12: 实现系统 Hosts 智能更新

**Files:**
- Modify: `GitHub-Host-Optimizer.ps1`

- [ ] **Step 1: 实现 Backup-SystemHosts 函数**

```powershell
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
        Write-Log "系统 hosts 已备份: $backupFile" -Level Info
        return $true
    } catch {
        Write-Log "系统 hosts 备份失败: $_" -Level Warning
        return $false
    }
}
```

- [ ] **Step 2: 实现 Update-SystemHosts 函数**

```powershell
function Update-SystemHosts {
    param(
        [Parameter(Mandatory=$true)][string]$HostsPath,
        [Parameter(Mandatory=$true)][array]$Results,
        [bool]$AutoBackup = $true
    )
    
    if (-not (Test-AdminPrivilege)) {
        Write-Log "无管理员权限，无法写入系统 hosts" -Level Warning
        return $false
    }
    
    $ipMap = @{}
    foreach ($result in $Results) {
        $ipMap[$result.Domain] = $result.IP
    }
    
    if ($ipMap.Count -eq 0) {
        Write-Log "无需更新系统 hosts" -Level Info
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
        $newContent += "# GitHub Hosts (自动添加)"
        foreach ($domain in $newDomains) {
            $newContent += "$($ipMap[$domain]) $domain"
        }
    }
    
    try {
        $newContent | Out-File -FilePath $HostsPath -Encoding UTF8
        Write-Log "系统 hosts 已更新" -Level Success
        $Global:Stats.SystemHostsWritten = $true
        return $true
    } catch {
        Write-Log "系统 hosts 写入失败: $_" -Level Error
        return $false
    }
}
```

---

### Task 13: 实现执行报告输出

**Files:**
- Modify: `GitHub-Host-Optimizer.ps1`

- [ ] **Step 1: 实现 Show-ExecutionReport 函数**

```powershell
function Show-ExecutionReport {
    param([Parameter(Mandatory=$true)][array]$Results)
    
    Write-Host ""
    Write-Host "========== 域名可用性检查 ==========" -ForegroundColor Cyan
    
    foreach ($result in $Results) {
        switch ($result.Status) {
            'Normal' {
                $statusText = "[正常]"
                $detail = "$($result.Domain) ($($result.IP)) - $($result.Latency)ms"
                $color = 'Green'
            }
            'Replaced' {
                $statusText = "[替换]"
                $detail = "$($result.Domain) ($($result.IP)) - 原 IP 失效"
                $color = 'Yellow'
            }
            'Failed' {
                $statusText = "[失效]"
                $detail = "$($result.Domain) - 无可用 IP"
                $color = 'Red'
            }
        }
        
        Write-Host "$statusText $detail" -ForegroundColor $color
    }
    
    Write-Host ""
    Write-Host "========== 执行统计 ==========" -ForegroundColor Cyan
    
    $total = $Global:Stats.TotalDomains
    $normal = $Global:Stats.NormalCount
    $replaced = $Global:Stats.ReplacedCount
    $failed = $Global:Stats.FailedCount
    $availableRate = if ($total -gt 0) { [math]::Round(($total - $failed) / $total * 100, 1) } else { 0 }
    
    Write-Host "检测域名: $total 个"
    Write-Host "正常: $normal 个" -ForegroundColor Green
    Write-Host "已替换: $replaced 个" -ForegroundColor Yellow
    Write-Host "失效: $failed 个" -ForegroundColor Red
    Write-Host "可用率: $availableRate%"
    Write-Host "备用池更新: $(if ($Global:Stats.BackupPoolUpdated) { '是' } else { '否' })"
    Write-Host "系统hosts写入: $(if ($Global:Stats.SystemHostsWritten) { '成功' } else { '未执行' })"
    Write-Host "==============================" -ForegroundColor Cyan
}
```

---

### Task 14: 实现主流程入口

**Files:**
- Modify: `GitHub-Host-Optimizer.ps1`

- [ ] **Step 1: 实现 Invoke-MainProcess 函数**

```powershell
function Invoke-MainProcess {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   GitHub Host 智能优选工具 v1.0.0     " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    $hasAdmin = Test-AdminPrivilege
    
    if (-not $hasAdmin) {
        Write-Log "当前无管理员权限，尝试申请..." -Level Warning
        
        $scriptPath = $MyInvocation.ScriptName
        if (-not $scriptPath) { $scriptPath = $PSCommandPath }
        
        $elevated = Request-AdminPrivilege -ScriptPath $scriptPath
        
        if ($elevated) { return }
        
        Write-Log "管理员权限申请被拒绝，将以普通用户模式运行" -Level Warning
        Write-Log "将仅更新主 Host 文件，不写入系统 hosts" -Level Warning
        Write-Host ""
    } else {
        Write-Log "已获取管理员权限" -Level Success
    }
    
    $config = Get-Config
    
    Write-Log "正在解析主 Host 文件..." -Level Info
    $mainHosts = Read-MainHostFile -FilePath $config.mainHostFile
    
    if ($mainHosts.Count -eq 0) {
        Write-Log "主 Host 文件为空或不存在，请配置后重新运行" -Level Error
        return
    }
    
    $Global:Stats.TotalDomains = $mainHosts.Count
    Write-Log "共发现 $($mainHosts.Count) 个域名" -Level Info
    Write-Host ""
    
    $backupPool = Get-BackupPool -FilePath $config.backupPoolFile
    $backupPoolUpdated = $false
    
    Write-Log "开始检测..." -Level Info
    Write-Host ""
    
    foreach ($domain in $mainHosts.Keys) {
        $originalIP = $mainHosts[$domain]
        
        $result = Invoke-DomainOptimization `
            -Domain $domain `
            -OriginalIP $originalIP `
            -Config $config `
            -BackupPool $backupPool `
            -BackupPoolUpdated ([ref]$backupPoolUpdated)
        
        $Global:DomainResults += $result
    }
    
    Write-Host ""
    Write-Log "正在更新主 Host 文件..." -Level Info
    Update-MainHostFile -FilePath $config.mainHostFile -Results $Global:DomainResults
    
    if ($hasAdmin) {
        Write-Log "正在更新系统 hosts..." -Level Info
        Update-SystemHosts -HostsPath $config.systemHostsPath -Results $Global:DomainResults -AutoBackup $config.autoBackup
    } else {
        Write-Host ""
        Write-Log "无管理员权限，已更新主 Host 文件" -Level Warning
        Write-Log "请手动复制到系统 hosts 或以管理员身份重新运行" -Level Warning
    }
    
    Show-ExecutionReport -Results $Global:DomainResults
}

Invoke-MainProcess

Write-Host ""
Write-Host "按任意键退出..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
```

---

## 自检清单

- [x] 配置文件创建与加载
- [x] 主 Host 文件解析与更新
- [x] TCP 443 端口测速
- [x] 备用池缓存管理
- [x] 远程源拉取与解析
- [x] 第三方 DNS API 调用
- [x] 四层优选流程
- [x] 管理员权限申请与降级
- [x] 系统 hosts 智能更新
- [x] 执行报告输出
- [x] 每个域名可用性检查
